import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Service for writing and reading the user's waste-ledger metrics.
class LedgerService {
  SupabaseClient get _db => Supabase.instance.client;

  static const String _weeklyEventsPrefsKey = 'waste_ledger_weekly_events_v1';

  /// Pantry staples: long-shelf-life items that aren't "at risk of going to
  /// waste" the way fresh produce is. These are excluded from the Waste
  /// Ledger's "ingredients rescued" count.
  static const List<String> _pantryStapleKeywords = [
    // Oils & fats
    'olive oil', 'vegetable oil', 'sunflower oil', 'canola oil', 'sesame oil',
    'oil', 'butter', 'ghee',
    // Seasoning
    'salt', 'pepper', 'peppercorn', 'sugar', 'brown sugar', 'honey',
    'aromat', 'bouillon', 'stock cube', 'seasoning',
    // Dry pantry / grains / starches
    'pasta', 'spaghetti', 'penne', 'rice', 'flour', 'breadcrumb',
    'lentil', 'dried bean', 'chickpea', 'couscous', 'quinoa', 'oat',
    // Vinegars / condiments with long shelf life
    'vinegar', 'soy sauce', 'mustard', 'ketchup', 'mayonnaise',
    // Baking
    'baking powder', 'baking soda', 'yeast', 'vanilla extract',
    // Canned / jarred
    'canned', 'tinned', 'jar of', 'stock (carton)',
    // Dried spices/herbs (as opposed to fresh herbs)
    'dried basil', 'dried oregano', 'dried thyme', 'paprika', 'cumin',
    'cinnamon', 'nutmeg', 'chili flakes', 'chilli flakes', 'bay leaf',
    // Long-life alliums & roots: weeks of shelf life, not "at risk" the way
    // fresh produce is.
    'onion', 'garlic', 'shallot', 'ginger', 'potato', 'sweet potato',
  ];


  /// True if [ingredient] looks like a long-shelf-life pantry staple rather
  /// than fresh produce at risk of going to waste.
  static bool _isPantryStaple(String ingredient) {
    final lower = ingredient.toLowerCase();

    // Spring/green onions are fresh and perishable, unlike storage onions —
    // don't let the bare "onion" keyword below catch them.
    final isFreshOnion =
        lower.contains('spring onion') || lower.contains('green onion') || lower.contains('scallion') || lower.contains('salad onion');

    for (final keyword in _pantryStapleKeywords) {
      if (keyword == 'onion' && isFreshOnion) continue;
      if (lower.contains(keyword)) return true;
    }
    return false;
  }

  /// Filters a raw ingredient list down to fresh produce only, dropping
  /// pantry staples like oil, salt, pepper, pasta, rice, etc.
  static List<String> freshProduceOnly(List<String> ingredients) {
    final out = <String>[];
    for (final i in ingredients) {
      final s = i.trim();
      if (s.isEmpty) continue;
      if (_isPantryStaple(s)) continue;
      out.add(s);
    }
    return out;
  }

  /// Logs one completion event to `waste_ledger_events` and returns updated
  /// totals, counting only fresh produce (pantry staples are excluded).
  ///
  /// [source] must be one of: 'fridge_clearer', 'cook_mode', 'custom_ai_recipe'.
  Future<Map<String, dynamic>> logCompletion({
    required String source,
    String? recipeId,
    required List<String> ingredientsRescued,
  }) async {
    try {
      final user = _db.auth.currentUser;
      if (user == null) {
        throw Exception('Not authenticated: cannot log ledger completion.');
      }

      final freshIngredients = freshProduceOnly(ingredientsRescued);

      final ingredientsCount = freshIngredients.length;

      // Persist locally for weekly rollups (no backend dependency). This is
      // best-effort and should never block the main logging flow.
      await _appendWeeklyEvent(freshIngredients);

      await _db.from('waste_ledger_events').insert({
        'user_id': user.id,
        'source': source,
        'recipe_id': (recipeId != null && recipeId.trim().isNotEmpty) ? recipeId.trim() : null,
        'ingredients_rescued': freshIngredients,
        'ingredients_count': ingredientsCount,
      });

      Map<String, dynamic>? totalsRow;
      totalsRow = await _db.from('user_ledger_totals').select().eq('user_id', user.id).maybeSingle();

      int readInt(Map<String, dynamic>? row, List<String> keys) {
        if (row == null) return 0;
        for (final k in keys) {
          final v = row[k];
          if (v is int) return v;
          if (v is num) return v.toInt();
          final parsed = int.tryParse('${v ?? ''}');
          if (parsed != null) return parsed;
        }
        return 0;
      }

      // Per schema: totals are keyed by `user_id` and exposed as these exact columns.
      final lifetimeIngredientsRescued = readInt(totalsRow, ['lifetime_ingredients_rescued']);

      return {
        'ingredientsRescued': ingredientsCount,
        'ingredientsRescuedList': freshIngredients,
        'lifetimeIngredientsRescued': lifetimeIngredientsRescued,
      };
    } catch (e, st) {
      debugPrint('LedgerService.logCompletion failed: $e\n$st');
      throw Exception('Failed to log waste ledger completion: $e');
    }
  }

  /// Returns a weekly + lifetime summary for the Waste Ledger.
  ///
  /// Weekly data is computed from local on-device events persisted by
  /// [logCompletion] (timestamp + ingredients list).
  ///
  /// Returned map keys:
  /// - weeklyIngredientsRescued (int)
  /// - weeklyIngredientsList (List<String>)
  /// - lifetimeIngredientsRescued (int)
  Future<Map<String, dynamic>> getWeeklySummary() async {
    try {
      final events = await _loadWeeklyEvents();
      final start = _startOfCurrentWeekLocal();

      final weeklyIngredients = <String>[];
      for (final e in events) {
        if (e.timestamp.isBefore(start)) continue;
        weeklyIngredients.addAll(e.ingredients);
      }

      // Keep existing lifetime logic as-is (still sourced from the current
      // ledger totals store).
      final user = _db.auth.currentUser;
      int lifetimeIngredientsRescued = 0;
      if (user != null) {
        final totalsRow = await _db.from('user_ledger_totals').select().eq('user_id', user.id).maybeSingle();
        final v = totalsRow?['lifetime_ingredients_rescued'];
        if (v is int) lifetimeIngredientsRescued = v;
        if (v is num) lifetimeIngredientsRescued = v.toInt();
        if (v != null && lifetimeIngredientsRescued == 0) {
          lifetimeIngredientsRescued = int.tryParse('$v') ?? 0;
        }
      }

      return {
        'weeklyIngredientsRescued': weeklyIngredients.length,
        'weeklyIngredientsList': weeklyIngredients,
        'lifetimeIngredientsRescued': lifetimeIngredientsRescued,
      };
    } catch (e, st) {
      debugPrint('LedgerService.getWeeklySummary failed: $e\n$st');
      return {
        'weeklyIngredientsRescued': 0,
        'weeklyIngredientsList': <String>[],
        'lifetimeIngredientsRescued': 0,
      };
    }
  }

  /// Count of fresh-produce ingredients rescued so far this calendar month,
  /// computed from the same local weekly-events store [getWeeklySummary]
  /// already uses (90-day retention comfortably covers a month) — no new
  /// capture logic, just a different date filter. Backs the "Your Month"
  /// recap card (CLAUDE.md Retention Features Backlog item 3).
  Future<int> getMonthlyIngredientsRescuedCount() async {
    try {
      final events = await _loadWeeklyEvents();
      final now = DateTime.now();
      var count = 0;
      for (final e in events) {
        if (e.timestamp.year == now.year && e.timestamp.month == now.month) {
          count += e.ingredients.length;
        }
      }
      return count;
    } catch (e, st) {
      debugPrint('LedgerService.getMonthlyIngredientsRescuedCount failed: $e\n$st');
      return 0;
    }
  }

  DateTime _startOfCurrentWeekLocal() {
    final now = DateTime.now();
    final todayMidnight = DateTime(now.year, now.month, now.day);
    return todayMidnight.subtract(Duration(days: todayMidnight.weekday - DateTime.monday));
  }

  Future<void> _appendWeeklyEvent(List<String> freshIngredients) async {
    if (freshIngredients.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final events = await _loadWeeklyEvents(prefs: prefs);
      events.add(_WeeklyLedgerEvent(timestamp: DateTime.now(), ingredients: List<String>.from(freshIngredients)));

      // Opportunistically prune very old events to keep storage tidy.
      final cutoff = DateTime.now().subtract(const Duration(days: 90));
      events.removeWhere((e) => e.timestamp.isBefore(cutoff));

      await prefs.setString(_weeklyEventsPrefsKey, _encodeWeeklyEvents(events));
    } catch (e, st) {
      debugPrint('LedgerService: failed to persist weekly ledger event: $e\n$st');
    }
  }

  Future<List<_WeeklyLedgerEvent>> _loadWeeklyEvents({SharedPreferences? prefs}) async {
    try {
      final p = prefs ?? await SharedPreferences.getInstance();
      final raw = p.getString(_weeklyEventsPrefsKey);
      final decoded = _decodeWeeklyEvents(raw);
      // Sanitize storage if corrupted entries were skipped.
      await p.setString(_weeklyEventsPrefsKey, _encodeWeeklyEvents(decoded));
      return decoded;
    } catch (e, st) {
      debugPrint('LedgerService: failed to load weekly ledger events: $e\n$st');
      return <_WeeklyLedgerEvent>[];
    }
  }

  String _encodeWeeklyEvents(List<_WeeklyLedgerEvent> events) {
    final list = events
        .map((e) => {
              'ts': e.timestamp.toIso8601String(),
              'ingredients': e.ingredients,
            })
        .toList(growable: false);
    return jsonEncode(list);
  }

  List<_WeeklyLedgerEvent> _decodeWeeklyEvents(String? raw) {
    if (raw == null || raw.trim().isEmpty) return <_WeeklyLedgerEvent>[];

    // Backward/robust parsing: use a very small JSON-ish parser via
    // SharedPreferences string storage. Prefer JSON when possible.
    //
    // If the stored format isn't valid JSON (e.g., from an older build), we
    // gracefully reset.
    try {
      // Attempt JSON first.
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! List) return <_WeeklyLedgerEvent>[];
      final out = <_WeeklyLedgerEvent>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final tsRaw = item['ts'];
        final ingredientsRaw = item['ingredients'];
        final ts = DateTime.tryParse('${tsRaw ?? ''}');
        if (ts == null) continue;
        if (ingredientsRaw is! List) continue;
        final ingredients = <String>[];
        for (final i in ingredientsRaw) {
          final s = '${i ?? ''}'.trim();
          if (s.isEmpty) continue;
          ingredients.add(s);
        }
        if (ingredients.isEmpty) continue;
        out.add(_WeeklyLedgerEvent(timestamp: ts, ingredients: ingredients));
      }
      return out;
    } catch (_) {
      return <_WeeklyLedgerEvent>[];
    }
  }
}

class _WeeklyLedgerEvent {
  _WeeklyLedgerEvent({required this.timestamp, required this.ingredients});

  final DateTime timestamp;
  final List<String> ingredients;
}