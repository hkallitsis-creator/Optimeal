import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One logged fridge item, backing the Fridge Countdown feature.
class FridgeItem {
  const FridgeItem({
    required this.id,
    required this.ingredientName,
    required this.addedDate,
    required this.estimatedShelfLifeDays,
  });

  final String id;
  final String ingredientName;
  final DateTime addedDate;
  final int estimatedShelfLifeDays;

  factory FridgeItem.fromJson(Map<String, dynamic> json) => FridgeItem(
        id: (json['id'] ?? '').toString(),
        ingredientName: (json['ingredient_name'] ?? '').toString(),
        addedDate: DateTime.tryParse('${json['added_date'] ?? ''}') ?? DateTime.now(),
        estimatedShelfLifeDays: (json['estimated_shelf_life_days'] is num)
            ? (json['estimated_shelf_life_days'] as num).toInt()
            : int.tryParse('${json['estimated_shelf_life_days'] ?? ''}') ?? 5,
      );

  /// Whole days left before this item is expected to spoil. Negative once
  /// past the estimate.
  int get daysRemaining {
    final today = DateTime.now();
    final expiresOn = addedDate.add(Duration(days: estimatedShelfLifeDays));
    return DateTime(expiresOn.year, expiresOn.month, expiresOn.day)
        .difference(DateTime(today.year, today.month, today.day))
        .inDays;
  }

  /// 0.0 (just logged) to 1.0 (spoiling today or overdue) — drives the
  /// freshness bar fill.
  double get spoilageRatio {
    if (estimatedShelfLifeDays <= 0) return 1;
    final elapsedDays = estimatedShelfLifeDays - daysRemaining;
    return (elapsedDays / estimatedShelfLifeDays).clamp(0, 1).toDouble();
  }

  /// "Expiring soon" threshold used consistently for the Home chip and the
  /// sheet's urgent grouping: 2 days or fewer remaining, including overdue.
  bool get isExpiringSoon => daysRemaining <= 2;
}

/// Service for the Fridge Countdown feature: user-logged fridge items with
/// an estimated shelf life, used to drive a decaying-freshness "N items
/// expiring soon" chip on Home (see CLAUDE.md Retention Features Backlog
/// item 1).
class FridgeCountdownService {
  SupabaseClient get _db => Supabase.instance.client;

  /// Rough default shelf-life estimates (days) by keyword, used to
  /// pre-fill the add-item form so most users never need to think about an
  /// exact number. Deliberately approximate — the user can always adjust.
  static const Map<String, int> _shelfLifeKeywordDays = {
    // Leafy greens & fresh herbs — shortest life.
    'spinach': 4, 'lettuce': 5, 'arugula': 4, 'rocket': 4, 'kale': 5,
    'basil': 5, 'parsley': 7, 'cilantro': 5, 'coriander': 5, 'mint': 5, 'dill': 5, 'chive': 6,
    // Berries — very short.
    'strawberr': 3, 'raspberr': 2, 'blueberr': 7, 'blackberr': 3,
    // Other fresh produce.
    'mushroom': 6, 'zucchini': 7, 'courgette': 7, 'cucumber': 7, 'tomato': 6,
    'bell pepper': 10, 'broccoli': 6, 'cauliflower': 7, 'asparagus': 4,
    'avocado': 4, 'peach': 4, 'plum': 4, 'grape': 7,
    // Fresh protein — short, safety-relevant.
    'fish': 2, 'salmon': 2, 'shrimp': 2, 'prawn': 2, 'seafood': 2,
    'chicken': 3, 'turkey': 3, 'ground beef': 2, 'mince': 2, 'sausage': 3,
    'beef': 4, 'pork': 4, 'lamb': 4,
    // Dairy & eggs — moderate.
    'milk': 7, 'yogurt': 10, 'yoghurt': 10, 'cream': 7, 'egg': 21,
    'soft cheese': 7, 'mozzarella': 7, 'feta': 14,
    // Longer-life fridge items.
    'hard cheese': 30, 'parmesan': 45, 'cheddar': 30, 'butter': 30,
    'carrot': 21, 'celery': 14, 'cabbage': 21, 'beet': 21,
    // Long-life alliums & roots — barely "at risk," but still trackable.
    'onion': 30, 'garlic': 60, 'potato': 30, 'ginger': 21, 'shallot': 30,
  };

  /// Suggests a default shelf-life (days) for [ingredientName]. Falls back
  /// to 5 days (a safe, mid-range fresh-produce estimate) when nothing
  /// matches.
  static int estimateShelfLifeDays(String ingredientName) {
    final lower = ingredientName.toLowerCase();
    for (final entry in _shelfLifeKeywordDays.entries) {
      if (lower.contains(entry.key)) return entry.value;
    }
    return 5;
  }

  /// All logged items for the current user, soonest-expiring first. Fails
  /// open (returns an empty list) — a transient error should never crash
  /// the Home dashboard.
  Future<List<FridgeItem>> listItems() async {
    try {
      final user = _db.auth.currentUser;
      if (user == null) return const [];
      final rows = await _db.from('fridge_items').select().eq('user_id', user.id);
      final items = rows.map((r) => FridgeItem.fromJson(Map<String, dynamic>.from(r))).toList();
      items.sort((a, b) => a.daysRemaining.compareTo(b.daysRemaining));
      return items;
    } catch (e) {
      debugPrint('FridgeCountdownService.listItems failed (returning empty): $e');
      return const [];
    }
  }

  /// Count of items with 2 or fewer days remaining (including overdue) —
  /// backs the Home "N items expiring soon" chip. Fails open (returns 0).
  Future<int> countExpiringSoon() async {
    final items = await listItems();
    return items.where((i) => i.isExpiringSoon).length;
  }

  Future<void> addItem({required String ingredientName, required int shelfLifeDays, DateTime? addedDate}) async {
    final user = _db.auth.currentUser;
    if (user == null) throw Exception('Not authenticated: cannot add a fridge item.');
    final name = ingredientName.trim();
    if (name.isEmpty) return;
    await _db.from('fridge_items').insert({
      'user_id': user.id,
      'ingredient_name': name,
      'added_date': (addedDate ?? DateTime.now()).toIso8601String().split('T').first,
      'estimated_shelf_life_days': shelfLifeDays,
    });
  }

  Future<void> removeItem(String id) async {
    final user = _db.auth.currentUser;
    if (user == null) return;
    await _db.from('fridge_items').delete().eq('id', id).eq('user_id', user.id);
  }
}
