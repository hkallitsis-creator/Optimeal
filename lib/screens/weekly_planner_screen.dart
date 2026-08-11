import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:optimeal/models/recipe_model.dart';
import 'package:optimeal/nav.dart';
import 'package:optimeal/services/chef_service.dart';
import 'package:optimeal/state/user_profile_controller.dart';
import 'package:optimeal/theme/app_design_tokens.dart';
import 'package:optimeal/theme.dart';
import 'package:optimeal/widgets/app_bottom_sheet.dart';
import 'package:optimeal/widgets/custom_ai_recipe_creator_sheet.dart';
import 'package:optimeal/screens/one_pan_cooking_roadmap_screen.dart';
import 'package:optimeal/services/weekly_planner_intent_service.dart';
import 'package:optimeal/state/ingredient_prep_controller.dart';

class WeeklyPlannerScreen extends StatefulWidget {
  const WeeklyPlannerScreen({super.key});

  @override
  State<WeeklyPlannerScreen> createState() => _WeeklyPlannerScreenState();
}

class _WeeklyPlannerScreenState extends State<WeeklyPlannerScreen> {
  static const _days = <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _daysLong = <String>['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

  int _selectedDayIndex = 0;

  bool _planLoading = true;
  String? _planLoadError;

  /// Inline, per-slot error strings keyed by "dayIndex-slotIndex".
  final Map<String, String> _slotInlineErrors = <String, String>{};

  /// Tracks which slots currently have an in-flight optimistic write.
  final Set<String> _pendingSlotWrites = <String>{};

  /// Each day can hold 1–2 meal slots.
  final Map<int, List<_PlannedMeal>> _planned = <int, List<_PlannedMeal>>{};

  late final VoidCallback _intentListener;

  @override
  void initState() {
    super.initState();
    _intentListener = _consumePendingPlannerIntent;
    WeeklyPlannerIntentService.instance.pendingAddMeal.addListener(_intentListener);
    WidgetsBinding.instance.addPostFrameCallback((_) => _consumePendingPlannerIntent());

    // Hydrate the weekly plan for the signed-in user.
    // (Minimal returning-user loading state: we keep the scaffold structure, but
    // show a lightweight inline loader or retry card in the list body.)
    unawaited(_loadPlanFromSupabase());
  }

  @override
  void dispose() {
    WeeklyPlannerIntentService.instance.pendingAddMeal.removeListener(_intentListener);
    super.dispose();
  }

  void _consumePendingPlannerIntent() {
    if (!mounted) return;
    final intent = WeeklyPlannerIntentService.instance.consumePending();
    if (intent == null) return;
    _addMealToDayFromIntent(intent);
  }

  void _addMealToDayFromIntent(WeeklyPlannerAddMealIntent intent) {
    final dayIndex = intent.dayIndex.clamp(0, 6);
    setState(() => _selectedDayIndex = dayIndex);

    final meals = _planned[dayIndex] ??= <_PlannedMeal>[];
    if (meals.length >= 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_days[dayIndex]} already has 2 meals.'), behavior: SnackBarBehavior.floating),
      );
      return;
    }

    final meal = _PlannedMeal(
      title: intent.recipe.title,
      source: intent.source,
      aisleItems: _aisleItemsFromIngredients(intent.recipe.ingredients, structured: intent.recipe.structuredIngredients),
      recipe: intent.recipe,
    );
    _optimisticallyAddMeal(dayIndex: dayIndex, meal: meal);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Added to ${_daysLong[dayIndex]}!'), behavior: SnackBarBehavior.floating),
    );
  }

  List<_PlannedMeal> _mealsForSelectedDay() => _planned[_selectedDayIndex] ??= <_PlannedMeal>[];

  bool get _dayHasRoom => _mealsForSelectedDay().length < 2;

  Future<void> _showAddMealSheet() async {
    await AppBottomSheet.show<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: false,
      builder: (ctx) => SafeArea(
        child: _AddMealOptionsSheet(
          dayLabel: _days[_selectedDayIndex],
          onClearFridge: () => _postFrame(() async {
            context.pop();
            await _pickMealFromFridgeClearer();
          }),
          onCustomCraving: () => _postFrame(() async {
            context.pop();
            await _customAiCravingForDay();
          }),
          onDiscountMeal: () => _postFrame(() async {
            context.pop();
            await _showDiscountMealFromDealsForDay();
          }),
        ),
      ),
    );
  }

  void _postFrame(Future<void> Function() fn) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await fn();
    });
  }

  void _addMeal(_PlannedMeal meal) {
    if (!_dayHasRoom) return;
    _optimisticallyAddMeal(dayIndex: _selectedDayIndex, meal: meal);
  }

  /// Opens a planned meal in Cook Mode and waits for a completion signal.
  /// Cook Mode's back button pops `true` once a cook has genuinely finished
  /// (all steps done or Finish & Plate), `false`/`null` otherwise (backed out
  /// mid-cook). On a true completion, the originating slot is marked
  /// "Cooked" — it stays visible, nothing is removed.
  Future<void> _openPlannedMeal(int dayIndex, int slotIndex, _PlannedMeal meal) async {
    final recipe = meal.recipe;
    if (recipe == null) {
      debugPrint('WeeklyPlanner: planned meal missing Cook Mode payload: ${meal.title}');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This meal is missing Cook Mode steps.'), behavior: SnackBarBehavior.floating),
      );
      return;
    }

    if (!mounted) return;
    final completed = await context.push<bool>(AppRoutes.onePanCookingRoadmap, extra: recipe);
    if (!mounted) return;
    if (completed == true) {
      _markMealCooked(dayIndex: dayIndex, slotIndex: slotIndex);
    }
  }

  List<_AisleItem> _aisleItemsFromIngredients(List<String> ingredients, {List<RecipeIngredient>? structured}) {
    const fallback = [_AisleItem(aisle: _Aisle.pantry, item: 'Salt'), _AisleItem(aisle: _Aisle.pantry, item: 'Pepper')];

    if (structured != null && structured.isNotEmpty) {
      final out = structured
          .map((ing) => _AisleItem(aisle: _inferAisle(ing.name), item: ing.name, amount: ing.amount, unit: ing.unit))
          .toList(growable: false);
      return out.isEmpty ? fallback : out;
    }

    final out = <_AisleItem>[];
    for (final raw in ingredients) {
      final s = raw.trim();
      if (s.isEmpty) continue;
      out.add(_AisleItem(aisle: _inferAisle(s), item: s));
    }
    return out.isEmpty ? fallback : out;
  }

  /// Merges same-name items within an aisle so the same ingredient across
  /// multiple meals shows as one combined line instead of duplicate rows.
  /// Sums cleanly when every entry shares a unit; otherwise combines
  /// whatever quantity info is available as distinct fragments rather than
  /// silently dropping it.
  List<_AisleItem> _mergeAisleItems(List<_AisleItem> items) {
    final byKey = <String, List<_AisleItem>>{};
    final order = <String>[];
    for (final it in items) {
      final key = it.item.trim().toLowerCase();
      if (key.isEmpty) continue;
      if (!byKey.containsKey(key)) order.add(key);
      (byKey[key] ??= <_AisleItem>[]).add(it);
    }

    String formatAmount(double amount) => amount == amount.roundToDouble() ? amount.toInt().toString() : amount.toStringAsFixed(1);

    final out = <_AisleItem>[];
    for (final key in order) {
      final group = byKey[key]!;
      final first = group.first;
      if (group.length == 1) {
        out.add(first);
        continue;
      }

      final unit = first.unit?.trim().toLowerCase();
      final sameUnit = unit != null && unit.isNotEmpty && group.every((e) => e.unit?.trim().toLowerCase() == unit);
      final allNumeric = sameUnit && group.every((e) => e.amount != null);

      if (allNumeric) {
        final total = group.fold<double>(0, (sum, e) => sum + e.amount!);
        out.add(_AisleItem(aisle: first.aisle, item: first.item, qty: '${formatAmount(total)} ${first.unit}'));
      } else {
        final fragments = group
            .map((e) {
              if (e.qty != null && e.qty!.trim().isNotEmpty) return e.qty!.trim();
              if (e.amount != null) return '${formatAmount(e.amount!)}${e.unit == null || e.unit!.isEmpty ? '' : ' ${e.unit}'}';
              return null;
            })
            .whereType<String>()
            .where((s) => s.isNotEmpty)
            .toList(growable: false);
        out.add(_AisleItem(aisle: first.aisle, item: first.item, qty: fragments.isEmpty ? null : fragments.join(' + ')));
      }
    }
    return out;
  }

  _Aisle _inferAisle(String ingredient) {
    final v = ingredient.toLowerCase();
    if (v.contains('chicken') || v.contains('beef') || v.contains('pork') || v.contains('tofu') || v.contains('fish') || v.contains('salmon') || v.contains('saus') || v.contains('meat')) {
      return _Aisle.meat;
    }
    if (v.contains('milk') || v.contains('cheese') || v.contains('yogurt') || v.contains('cream') || v.contains('butter') || v.contains('egg')) {
      return _Aisle.dairy;
    }
    if (v.contains('lettuce') || v.contains('spinach') || v.contains('zucchini') || v.contains('onion') || v.contains('garlic') || v.contains('tomato') || v.contains('pepper') || v.contains('carrot') || v.contains('potato') || v.contains('lemon') || v.contains('broccoli') || v.contains('mushroom')) {
      return _Aisle.produce;
    }
    return _Aisle.pantry;
  }

  Future<void> _pickMealFromFridgeClearer() async {
    if (!_dayHasRoom) return;

    try {
      final result = await context.push<Object?>(AppRoutes.fridgeClearerPicker);
      if (!mounted) return;

      if (result is! CookModeRecipePayload) return;

      final meal = _PlannedMeal(
        title: result.title,
        source: 'Clear Fridge Leftovers',
        aisleItems: _aisleItemsFromIngredients(result.ingredients, structured: result.structuredIngredients),
        recipe: result,
      );
      _addMeal(meal);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added “${meal.title}”.'), behavior: SnackBarBehavior.floating),
      );
    } catch (e) {
      debugPrint('WeeklyPlanner: fridge picker failed: $e');
    }
  }

  Future<void> _customAiCravingForDay() async {
    if (!_dayHasRoom) return;

    try {
      final payload = await AppBottomSheet.show<CookModeRecipePayload>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (ctx) => const SafeArea(child: CustomAiRecipeCreatorSheet()),
      );
      if (!mounted || payload == null) return;

      final meal = _PlannedMeal(
        title: payload.title,
        source: 'Custom AI Craving',
        aisleItems: _aisleItemsFromIngredients(payload.ingredients, structured: payload.structuredIngredients),
        recipe: payload,
      );
      _addMeal(meal);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added “${meal.title}”.'), behavior: SnackBarBehavior.floating),
      );
    } catch (e) {
      debugPrint('WeeklyPlanner: custom craving failed: $e');
    }
  }

  void _removeMeal(int slotIndex) {
    final meals = _mealsForSelectedDay();
    if (slotIndex < 0 || slotIndex >= meals.length) return;
    _optimisticallyRemoveMeal(dayIndex: _selectedDayIndex, slotIndex: slotIndex);
  }

  String _slotKey(int dayIndex, int slotIndex) => '$dayIndex-$slotIndex';

  User? _currentUser() => Supabase.instance.client.auth.currentUser;

  Map<String, dynamic> _cookModePayloadToJson(CookModeRecipePayload payload) => {
    'title': payload.title,
    'ingredients': payload.ingredients,
    'kitchen_gear': payload.kitchenGear,
    'steps': payload.steps
        .map((s) => {'title': s.title, 'heat': s.heat, 'duration_minutes': s.durationMinutes, 'bullets': s.bullets})
        .toList(growable: false),
    'description': payload.description,
    'structured_ingredients': payload.structuredIngredients?.map((i) => i.toJson()).toList(),
    'base_portions': payload.basePortions,
    'curriculum_lesson_ids': payload.curriculumLessonIds,
  };

  CookModeRecipePayload? _cookModePayloadFromJson(dynamic raw) {
    try {
      final decoded = raw is String ? jsonDecode(raw) : raw;
      if (decoded is! Map) return null;
      final title = (decoded['title'] ?? '').toString().trim();

      final ingredients = <String>[];
      final ingRaw = decoded['ingredients'];
      if (ingRaw is List) {
        for (final e in ingRaw) {
          final s = e.toString().trim();
          if (s.isNotEmpty) ingredients.add(s);
        }
      }

      final gear = <String>[];
      final gearRaw = decoded['kitchen_gear'] ?? decoded['kitchenGear'];
      if (gearRaw is List) {
        for (final e in gearRaw) {
          final s = e.toString().trim();
          if (s.isNotEmpty) gear.add(s);
        }
      }

      final steps = <CookModeStepPayload>[];
      final stepsRaw = decoded['steps'];
      if (stepsRaw is List) {
        for (final s in stepsRaw) {
          if (s is! Map) continue;
          final stepTitle = (s['title'] ?? '').toString().trim();
          if (stepTitle.isEmpty) continue;
          final duration = int.tryParse('${s['duration_minutes'] ?? s['durationMinutes'] ?? ''}'.trim()) ?? 0;
          final heat = (s['heat'] ?? 'medium').toString().trim();
          final bullets = <String>[];
          final bulletsRaw = s['bullets'];
          if (bulletsRaw is List) {
            for (final b in bulletsRaw) {
              final blt = b.toString().trim();
              if (blt.isNotEmpty) bullets.add(blt);
            }
          }
          if (bullets.isEmpty) bullets.add('Keep going and taste as you go.');
          steps.add(CookModeStepPayload(title: stepTitle, heat: heat, durationMinutes: duration, bullets: bullets));
        }
      }

      if (steps.isEmpty) return null;

      final structuredRaw = decoded['structured_ingredients'] ?? decoded['structuredIngredients'];
      final structuredIngredients = structuredRaw is List
          ? structuredRaw.whereType<Map>().map((e) => RecipeIngredient.fromJson(Map<String, dynamic>.from(e))).toList(growable: false)
          : null;

      final curriculumRaw = decoded['curriculum_lesson_ids'] ?? decoded['curriculumLessonIds'];
      final curriculumLessonIds = curriculumRaw is List ? curriculumRaw.map((e) => e.toString()).toList(growable: false) : null;

      return CookModeRecipePayload(
        title: title.isEmpty ? 'Planned meal' : title,
        ingredients: ingredients.isEmpty ? const ['Salt', 'Pepper', 'Cooking oil'] : ingredients,
        steps: steps,
        kitchenGear: gear.isEmpty ? const ['1 Pan or Pot', 'Knife', 'Spoon/Spatula'] : gear,
        description: (decoded['description'] as String?)?.trim(),
        structuredIngredients: (structuredIngredients?.isEmpty ?? true) ? null : structuredIngredients,
        basePortions: int.tryParse('${decoded['base_portions'] ?? decoded['basePortions'] ?? ''}'.trim()),
        curriculumLessonIds: curriculumLessonIds,
      );
    } catch (e) {
      debugPrint('WeeklyPlanner: failed to decode CookMode payload: $e');
      return null;
    }
  }

  Map<String, dynamic> _plannedMealToPlanRow({required String userId, required int dayIndex, required int slotIndex, required _PlannedMeal meal}) => {
    // Expected schema (adjust server-side as needed):
    // user_id (uuid), day_index (int), slot_index (int), title (text), source (text),
    // aisle_items (jsonb), recipe_payload (jsonb), is_cooked (boolean), updated_at (timestamptz)
    'user_id': userId,
    'day_index': dayIndex,
    'slot_index': slotIndex,
    'title': meal.title,
    'source': meal.source,
    'aisle_items': meal.aisleItems
        .map((e) => {'aisle': e.aisle.name, 'item': e.item, 'qty': e.qty})
        .toList(growable: false),
    'recipe_payload': meal.recipe == null ? null : _cookModePayloadToJson(meal.recipe!),
    'is_cooked': meal.cooked,
    'updated_at': DateTime.now().toUtc().toIso8601String(),
  };

  _PlannedMeal? _plannedMealFromPlanRow(Map row) {
    try {
      final title = (row['title'] ?? '').toString().trim();
      final source = (row['source'] ?? '').toString().trim();
      if (title.isEmpty) return null;

      final aisleItems = <_AisleItem>[];
      final itemsRaw = row['aisle_items'] ?? row['aisleItems'];
      if (itemsRaw is List) {
        for (final it in itemsRaw) {
          if (it is! Map) continue;
          final aisleRaw = (it['aisle'] ?? '').toString().trim();
          final aisle = _Aisle.values.cast<_Aisle?>().firstWhere((a) => a?.name == aisleRaw, orElse: () => null);
          final item = (it['item'] ?? '').toString().trim();
          if (aisle == null || item.isEmpty) continue;
          final qty = it['qty']?.toString();
          aisleItems.add(_AisleItem(aisle: aisle, item: item, qty: qty));
        }
      }

      final recipe = _cookModePayloadFromJson(row['recipe_payload'] ?? row['recipePayload']);
      final cooked = (row['is_cooked'] ?? row['isCooked']) == true;
      return _PlannedMeal(
        title: title,
        source: source.isEmpty ? 'Planned meal' : source,
        aisleItems: aisleItems.isEmpty ? _aisleItemsFromIngredients(const ['Salt', 'Pepper']) : aisleItems,
        recipe: recipe,
        cooked: cooked,
      );
    } catch (e) {
      debugPrint('WeeklyPlanner: failed to parse plan row: $e');
      return null;
    }
  }

  Future<void> _loadPlanFromSupabase() async {
    final user = _currentUser();
    if (user == null) {
      // No auth: keep existing local behavior, but stop showing loader.
      if (!mounted) return;
      setState(() {
        _planLoading = false;
        _planLoadError = null;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _planLoading = true;
      _planLoadError = null;
    });

    try {
      final db = Supabase.instance.client;

      final rows = await db
          .from('user_meal_plans')
          .select()
          .eq('user_id', user.id)
          .order('day_index', ascending: true)
          .order('slot_index', ascending: true);

      final next = <int, List<_PlannedMeal>>{};
      if (rows is List) {
        for (final r in rows) {
          if (r is! Map) continue;
          final dayIndex = int.tryParse('${r['day_index'] ?? r['dayIndex'] ?? ''}'.trim());
          final slotIndex = int.tryParse('${r['slot_index'] ?? r['slotIndex'] ?? ''}'.trim());
          if (dayIndex == null || slotIndex == null) continue;
          if (dayIndex < 0 || dayIndex > 6) continue;
          if (slotIndex < 0 || slotIndex > 1) continue;

          final meal = _plannedMealFromPlanRow(r);
          if (meal == null) continue;

          final list = next[dayIndex] ??= <_PlannedMeal>[];
          // Keep slots ordered by slot_index.
          while (list.length <= slotIndex) {
            list.add(const _PlannedMeal(title: '', source: '', aisleItems: <_AisleItem>[], recipe: null));
          }
          list[slotIndex] = meal;
        }
      }

      // Normalize out the placeholder empties created above.
      //
      // IMPORTANT: this must stay a GROWABLE list. `_planned[dayIndex]` gets
      // mutated later via .add()/.removeAt()/.insert() (see
      // _optimisticallyAddMeal, _optimisticallyRemoveMeal, and their retry
      // paths). Using `.toList(growable: false)` here produced a
      // fixed-length list that threw `Unsupported operation: add` the
      // moment a user tried to add a second meal to a day that already had
      // one loaded from Supabase — silently blocking every save on that
      // day before the app ever reached the network call.
      for (final entry in next.entries.toList(growable: false)) {
        final cleaned = entry.value.where((m) => m.title.trim().isNotEmpty).toList();
        next[entry.key] = cleaned;
      }

      if (!mounted) return;
      setState(() {
        _planned
          ..clear()
          ..addAll(next);
        _planLoading = false;
        _planLoadError = null;
        _slotInlineErrors.clear();
        _pendingSlotWrites.clear();
      });
    } catch (e) {
      debugPrint('WeeklyPlanner: loadPlanFromSupabase failed: $e');
      if (!mounted) return;
      setState(() {
        _planLoading = false;
        _planLoadError = 'Could not load your saved plan.';
      });
    }
  }

  /// PGRST303 ("JWT issued at future") fires when Supabase's PostgREST layer
  /// thinks our access token was issued in the future. In practice this is
  /// almost always a *stale* cached token rather than a real problem — a
  /// forced `refreshSession()` mints a fresh token and the retry succeeds.
  bool _isJwtClockSkewError(Object e) {
    if (e is PostgrestException) {
      return e.code == 'PGRST303' || e.message.toLowerCase().contains('jwt issued at future');
    }
    return e.toString().toLowerCase().contains('jwt issued at future');
  }

  Future<T> _withJwtRetry<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (e) {
      if (!_isJwtClockSkewError(e)) rethrow;
      debugPrint('WeeklyPlanner: JWT clock-skew error detected, refreshing session and retrying once.');
      try {
        await Supabase.instance.client.auth.refreshSession();
      } catch (refreshError) {
        debugPrint('WeeklyPlanner: session refresh failed: $refreshError');
        rethrow;
      }
      return await action();
    }
  }

  Future<void> _persistMealSlot({required int dayIndex, required int slotIndex, required _PlannedMeal meal}) async {
    final key = _slotKey(dayIndex, slotIndex);
    final user = _currentUser();
    if (user == null) {
      if (!mounted) return;
      setState(() => _pendingSlotWrites.remove(key));
      return;
    }

    try {
      final db = Supabase.instance.client;
      final row = _plannedMealToPlanRow(userId: user.id, dayIndex: dayIndex, slotIndex: slotIndex, meal: meal);
      await _withJwtRetry(() => db.from('user_meal_plans').upsert(row));
    } catch (e) {
      debugPrint('WeeklyPlanner: persistMealSlot failed: $e');
      rethrow;
    } finally {
      if (!mounted) return;
      setState(() => _pendingSlotWrites.remove(key));
    }
  }

  Future<void> _deleteMealSlot({required int dayIndex, required int slotIndex}) async {
    final key = _slotKey(dayIndex, slotIndex);
    final user = _currentUser();
    if (user == null) {
      if (!mounted) return;
      setState(() => _pendingSlotWrites.remove(key));
      return;
    }

    try {
      final db = Supabase.instance.client;
      await _withJwtRetry(
        () => db.from('user_meal_plans').delete().eq('user_id', user.id).eq('day_index', dayIndex).eq('slot_index', slotIndex),
      );
    } catch (e) {
      debugPrint('WeeklyPlanner: deleteMealSlot failed: $e');
      rethrow;
    } finally {
      if (!mounted) return;
      setState(() => _pendingSlotWrites.remove(key));
    }
  }

  /// Best-effort background sync into `shopping_list_items`. This must NEVER
  /// be allowed to roll back a meal-slot save/delete that already succeeded —
  /// callers wrap this separately and only log failures here.
  ///
  /// Matches the live schema: user_id (uuid), ingredient_name (text),
  /// source (text), updated_at (timestamptz). There's no `aisle` column —
  /// the in-app shopping list sheet builds its aisle grouping from local
  /// planner state, not by reading this table back, so that's fine.
  Future<void> _upsertShoppingListItemsForMeal(_PlannedMeal meal) async {
    final user = _currentUser();
    if (user == null) return;
    try {
      final db = Supabase.instance.client;
      final rows = meal.aisleItems
          .map(
            (e) => {
              'user_id': user.id,
              'ingredient_name': e.item,
              'source': meal.source,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            },
          )
          .toList(growable: false);
      if (rows.isEmpty) return;

      await db.from('shopping_list_items').upsert(rows);
    } catch (e) {
      debugPrint('WeeklyPlanner: upsertShoppingListItemsForMeal failed: $e');
      // Non-fatal for planner UX; we keep local UI state.
    }
  }

  Future<void> _deleteShoppingListItemsNoLongerNeeded() async {
    final user = _currentUser();
    if (user == null) return;

    try {
      final desired = <String>{};
      for (final meals in _planned.values) {
        for (final meal in meals) {
          for (final it in meal.aisleItems) {
            final label = it.item.trim();
            if (label.isNotEmpty) desired.add(label);
          }
        }
      }

      final db = Supabase.instance.client;

      // Fetch current list so we can delete only what disappeared.
      final rows = await db.from('shopping_list_items').select('ingredient_name').eq('user_id', user.id);
      final existing = <String>{};
      if (rows is List) {
        for (final r in rows) {
          if (r is! Map) continue;
          final item = (r['ingredient_name'] ?? '').toString().trim();
          if (item.isNotEmpty) existing.add(item);
        }
      }

      final toDelete = existing.difference(desired).toList(growable: false);
      if (toDelete.isEmpty) return;

      await db.from('shopping_list_items').delete().eq('user_id', user.id).inFilter('ingredient_name', toDelete);
    } catch (e) {
      debugPrint('WeeklyPlanner: deleteShoppingListItemsNoLongerNeeded failed: $e');
    }
  }

  void _optimisticallyAddMeal({required int dayIndex, required _PlannedMeal meal}) {
    final meals = _planned[dayIndex] ??= <_PlannedMeal>[];
    if (meals.length >= 2) return;
    final slotIndex = meals.length;
    final key = _slotKey(dayIndex, slotIndex);

    setState(() {
      _slotInlineErrors.remove(key);
      _pendingSlotWrites.add(key);
      meals.add(meal);
    });

    // 1) Persist the plan row (critical — a failure here rolls back the
    //    optimistic UI update).
    // 2) Then, separately, best-effort sync into the shopping list. A failure
    //    in step 2 must never undo the already-successful save in step 1.
    unawaited(() async {
      try {
        await _persistMealSlot(dayIndex: dayIndex, slotIndex: slotIndex, meal: meal);
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _pendingSlotWrites.remove(key);
          final list = _planned[dayIndex];
          if (list != null && list.length > slotIndex && identical(list[slotIndex], meal)) {
            list.removeAt(slotIndex);
          }
          _slotInlineErrors[key] = 'Couldn\'t save. Tap to retry.';
        });
        return;
      }

      await _upsertShoppingListItemsForMeal(meal);
      await _deleteShoppingListItemsNoLongerNeeded();
    }());
  }

  void _optimisticallyRemoveMeal({required int dayIndex, required int slotIndex}) {
    final meals = _planned[dayIndex] ??= <_PlannedMeal>[];
    if (slotIndex < 0 || slotIndex >= meals.length) return;

    final removed = meals[slotIndex];
    final key = _slotKey(dayIndex, slotIndex);

    setState(() {
      _slotInlineErrors.remove(key);
      _pendingSlotWrites.add(key);
      meals.removeAt(slotIndex);
    });

    // Same critical/non-critical split as _optimisticallyAddMeal above: the
    // shopping-list cleanup must never resurrect a meal that was already
    // successfully deleted.
    unawaited(() async {
      try {
        await _deleteMealSlot(dayIndex: dayIndex, slotIndex: slotIndex);
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _pendingSlotWrites.remove(key);
          final list = _planned[dayIndex] ??= <_PlannedMeal>[];
          list.insert(slotIndex.clamp(0, list.length), removed);
          _slotInlineErrors[key] = 'Couldn\'t remove. Tap to retry.';
        });
        return;
      }

      await _deleteShoppingListItemsNoLongerNeeded();
    }());
  }

  /// Marks the meal at [dayIndex]/[slotIndex] as cooked — optimistic update,
  /// persisted in the background, reverted (with the same inline-error/retry
  /// pattern as add/remove) if the save fails. Never removes the slot.
  void _markMealCooked({required int dayIndex, required int slotIndex}) {
    final meals = _planned[dayIndex] ??= <_PlannedMeal>[];
    if (slotIndex < 0 || slotIndex >= meals.length) return;
    if (meals[slotIndex].cooked) return; // Already marked — nothing to do.

    final previous = meals[slotIndex];
    final updated = previous.copyWith(cooked: true);
    final key = _slotKey(dayIndex, slotIndex);

    setState(() {
      _slotInlineErrors.remove(key);
      _pendingSlotWrites.add(key);
      meals[slotIndex] = updated;
    });

    unawaited(() async {
      try {
        await _persistMealSlot(dayIndex: dayIndex, slotIndex: slotIndex, meal: updated);
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _pendingSlotWrites.remove(key);
          final list = _planned[dayIndex];
          if (list != null && list.length > slotIndex) {
            list[slotIndex] = previous;
          }
          _slotInlineErrors[key] = 'Couldn\'t mark as cooked. Tap to retry.';
        });
      }
    }());
  }

  void _retrySlot(int dayIndex, int slotIndex) {
    final key = _slotKey(dayIndex, slotIndex);
    if (_pendingSlotWrites.contains(key)) return;
    final meals = _planned[dayIndex] ??= <_PlannedMeal>[];

    // If the slot exists, retry upsert. If it doesn't, retry delete.
    if (slotIndex >= 0 && slotIndex < meals.length) {
      final meal = meals[slotIndex];
      setState(() {
        _slotInlineErrors.remove(key);
        _pendingSlotWrites.add(key);
      });
      unawaited(() async {
        try {
          await _persistMealSlot(dayIndex: dayIndex, slotIndex: slotIndex, meal: meal);
        } catch (_) {
          if (!mounted) return;
          setState(() {
            _pendingSlotWrites.remove(key);
            _slotInlineErrors[key] = 'Couldn\'t save. Tap to retry.';
          });
          return;
        }

        await _upsertShoppingListItemsForMeal(meal);
        await _deleteShoppingListItemsNoLongerNeeded();
      }());
    } else {
      // Nothing in this slot locally anymore: ensure Supabase row is deleted.
      setState(() {
        _slotInlineErrors.remove(key);
        _pendingSlotWrites.add(key);
      });
      unawaited(() async {
        try {
          await _deleteMealSlot(dayIndex: dayIndex, slotIndex: slotIndex);
        } catch (_) {
          if (!mounted) return;
          setState(() {
            _pendingSlotWrites.remove(key);
            _slotInlineErrors[key] = 'Couldn\'t remove. Tap to retry.';
          });
          return;
        }

        await _deleteShoppingListItemsNoLongerNeeded();
      }());
    }
  }

  Future<void> _showDiscountMealFromDealsForDay() async {
    final profile = context.read<UserProfileController>().profile;
    final theme = Theme.of(context);

    await AppBottomSheet.show<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: _DealMealSuggestionSheet(
          dayLabel: _days[_selectedDayIndex],
          chefService: ChefService(),
          profile: profile,
          onAddMeal: (meal) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              context.pop();
              _addMeal(meal);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Added “${meal.title}”.'),
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: theme.colorScheme.secondary,
                ),
              );
            });
          },
        ),
      ),
    );
  }

  void _showCombinedShoppingList() {
    final combined = <_Aisle, List<_AisleItem>>{};
    for (final meals in _planned.values) {
      for (final meal in meals) {
        for (final item in meal.aisleItems) {
          (combined[item.aisle] ??= <_AisleItem>[]).add(item);
        }
      }
    }
    combined.updateAll((aisle, items) => _mergeAisleItems(items));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      AppBottomSheet.show<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        // Keep the modal container consistent with the app’s primary card surfaces.
        backgroundColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard)),
        builder: (ctx) => SafeArea(
          child: Material(
            color: AppDesignTokens.surfaceCream,
            elevation: 4,
            shadowColor: Colors.black12,
            borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard),
            clipBehavior: Clip.antiAlias,
            child: _ShoppingListSheet(
              byAisle: combined,
              hasAnyMeals: _planned.values.any((e) => e.isNotEmpty),
            ),
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final mealsToday = _mealsForSelectedDay();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          onPressed: () => context.go(AppRoutes.home),
          tooltip: 'Home',
          icon: Container(
            padding: const EdgeInsets.all(AppDesignTokens.spaceXS),
            decoration: BoxDecoration(
              color: AppDesignTokens.surfaceCream.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(AppDesignTokens.radiusChip),
              border: Border.all(color: AppDesignTokens.textCharcoal.withValues(alpha: 0.12)),
            ),
            child: const Icon(Icons.arrow_back, color: AppDesignTokens.textCharcoal),
          ),
        ),
        title: Text('Weekly Planner', style: AppDesignTokens.headline),
        actions: [
          IconButton(
            onPressed: _showCombinedShoppingList,
            icon: const Icon(Icons.shopping_cart_checkout_rounded, color: AppDesignTokens.textCharcoal),
            tooltip: 'View combined shopping list',
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppDesignTokens.spaceSM, 12, AppDesignTokens.spaceSM, 10),
            child: _SevenDayBar(
              selectedIndex: _selectedDayIndex,
              labels: _days,
              onSelect: (i) => setState(() => _selectedDayIndex = i),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(AppDesignTokens.spaceSM, AppDesignTokens.spaceXS, AppDesignTokens.spaceSM, AppDesignTokens.spaceMD),
              children: [
                _SectionHeader(
                  title: '${_days[_selectedDayIndex]} meals',
                  subtitle: 'Add 1–2 slots. Keep it simple and balanced.',
                  trailing: _dayHasRoom
                      ? TextButton.icon(
                          onPressed: _showAddMealSheet,
                          icon: const Icon(Icons.add_rounded, color: AppDesignTokens.ctaTerracotta),
                          label: const Text('Add meal', style: TextStyle(color: AppDesignTokens.ctaTerracotta, fontWeight: FontWeight.w900)),
                          style: ButtonStyle(overlayColor: WidgetStatePropertyAll(Colors.transparent)),
                        )
                      : null,
                ),
                const SizedBox(height: 10),

                if (_planLoading)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: [
                        const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2.4, color: AppDesignTokens.ctaTerracotta)),
                        const SizedBox(width: 12),
                        Expanded(child: Text('Loading your saved week…', style: AppDesignTokens.body.copyWith(fontWeight: FontWeight.w700))),
                      ],
                    ),
                  )
                else if (_planLoadError != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppDesignTokens.spaceSM),
                    decoration: BoxDecoration(
                      color: scheme.errorContainer.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard),
                      border: Border.all(color: scheme.error.withValues(alpha: 0.20)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.wifi_off_rounded, color: scheme.error),
                        const SizedBox(width: 10),
                        Expanded(child: Text(_planLoadError!, style: AppDesignTokens.body.copyWith(color: scheme.onErrorContainer, fontWeight: FontWeight.w800))),
                        const SizedBox(width: 10),
                        TextButton(
                          onPressed: _loadPlanFromSupabase,
                          style: const ButtonStyle(overlayColor: WidgetStatePropertyAll(Colors.transparent)),
                          child: const Text('Retry', style: TextStyle(color: AppDesignTokens.ctaTerracotta, fontWeight: FontWeight.w900)),
                        ),
                      ],
                    ),
                  ),

                for (var slot = 0; slot < 2; slot++) ...[
                  _MealSlotCard(
                    slotIndex: slot,
                    meal: slot < mealsToday.length ? mealsToday[slot] : null,
                    canAdd: _dayHasRoom && slot == mealsToday.length,
                    onAdd: _showAddMealSheet,
                    onRemove: () => _removeMeal(slot),
                    onTapMeal: slot < mealsToday.length ? () => _openPlannedMeal(_selectedDayIndex, slot, mealsToday[slot]) : null,
                    inlineError: _slotInlineErrors[_slotKey(_selectedDayIndex, slot)],
                    isSaving: _pendingSlotWrites.contains(_slotKey(_selectedDayIndex, slot)),
                    onRetry: () => _retrySlot(_selectedDayIndex, slot),
                  ),
                  const SizedBox(height: 12),
                ],
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _showCombinedShoppingList,
                  icon: const Icon(Icons.shopping_bag_rounded, color: Colors.white),
                  label: Text('🛒 View Combined Shopping List', style: AppDesignTokens.subheadline.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppDesignTokens.ctaTerracotta,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard)),
                    minimumSize: const Size.fromHeight(AppSizing.primaryButtonHeight),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SevenDayBar extends StatelessWidget {
  const _SevenDayBar({required this.selectedIndex, required this.labels, required this.onSelect});

  final int selectedIndex;
  final List<String> labels;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(AppDesignTokens.spaceXS),
      decoration: BoxDecoration(
        color: AppDesignTokens.surfaceCream,
        borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.10)),
        boxShadow: AppDesignTokens.cardShadow,
      ),
      child: Row(
        children: List.generate(labels.length, (i) {
          final isSelected = i == selectedIndex;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: _DayPill(
                label: labels[i],
                selected: isSelected,
                onTap: () => onSelect(i),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _DayPill extends StatefulWidget {
  const _DayPill({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_DayPill> createState() => _DayPillState();
}

class _DayPillState extends State<_DayPill> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bg = widget.selected ? AppDesignTokens.ctaTerracotta : AppDesignTokens.surfaceCream;
    final fg = widget.selected ? Colors.white : AppDesignTokens.textCharcoal;

    return AnimatedScale(
      scale: _pressed ? 0.98 : 1,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: widget.onTap,
          onHighlightChanged: (v) => setState(() => _pressed = v),
          splashFactory: NoSplash.splashFactory,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          hoverColor: Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: (widget.selected ? AppDesignTokens.ctaTerracotta : scheme.outline).withValues(alpha: 0.18),
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppDesignTokens.caption.copyWith(color: fg, fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.subtitle, this.trailing});

  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppDesignTokens.headline),
              const SizedBox(height: 6),
              Text(subtitle, style: AppDesignTokens.body.copyWith(color: AppDesignTokens.textCharcoal.withValues(alpha: 0.75), height: 1.35)),
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 12),
          trailing!,
        ],
      ],
    );
  }
}

class _MealSlotCard extends StatelessWidget {
  const _MealSlotCard({required this.slotIndex, required this.meal, required this.canAdd, required this.onAdd, required this.onRemove, this.onTapMeal, required this.inlineError, required this.isSaving, required this.onRetry});

  final int slotIndex;
  final _PlannedMeal? meal;
  final bool canAdd;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  final VoidCallback? onTapMeal;
  final String? inlineError;
  final bool isSaving;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final shadow = AppDesignTokens.cardShadow;

    if (meal == null) {
      return Container(
        decoration: BoxDecoration(
          color: AppDesignTokens.surfaceCream,
          borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard),
          border: Border.all(color: scheme.outline.withValues(alpha: 0.10)),
          boxShadow: shadow,
        ),
        padding: const EdgeInsets.all(AppDesignTokens.spaceSM),
        child: Row(
          children: [
            Container(
              height: 44,
              width: 44,
              decoration: BoxDecoration(
                color: AppDesignTokens.ctaTerracotta.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppDesignTokens.radiusButton),
                border: Border.all(color: AppDesignTokens.ctaTerracotta.withValues(alpha: 0.18)),
              ),
              child: const Icon(Icons.add_rounded, color: AppDesignTokens.ctaTerracotta),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Slot ${slotIndex + 1}', style: AppDesignTokens.subheadline),
                  const SizedBox(height: 4),
                  Text('Tap to add a meal', style: AppDesignTokens.body.copyWith(color: AppDesignTokens.textCharcoal.withValues(alpha: 0.75))),
                ],
              ),
            ),
            FilledButton(
              onPressed: canAdd ? onAdd : null,
              style: FilledButton.styleFrom(
                backgroundColor: AppDesignTokens.ctaTerracotta,
                foregroundColor: Colors.white,
                // Slot 2 can be present but not addable yet (when Slot 1 is empty).
                // Keep its empty-state CTA styling visually identical to Slot 1.
                disabledBackgroundColor: slotIndex == 1 ? AppDesignTokens.ctaTerracotta : scheme.outline.withValues(alpha: 0.20),
                disabledForegroundColor: slotIndex == 1 ? Colors.white : null,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppDesignTokens.radiusButton)),
                padding: const EdgeInsets.symmetric(horizontal: AppDesignTokens.spaceSM, vertical: 12),
              ),
              child: Text('+ Add Meal', style: AppDesignTokens.subheadline.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      );
    }

    // NOTE (bug fix): the "x" remove button used to live *inside* the same
    // InkWell that opens Cook Mode (onTapMeal). Nesting a tappable IconButton
    // inside an ancestor InkWell puts both recognizers in the same gesture
    // arena and the outer InkWell can end up swallowing the tap before it
    // ever reaches the IconButton's onPressed — which matched exactly what
    // was observed (onRemove never firing, no debugPrint output at all).
    // Fix: the InkWell now wraps ONLY the tappable content region (leading
    // icon + text), and the close IconButton is a sibling outside that
    // InkWell's subtree, so its taps are never contested.
    return Container(
      decoration: BoxDecoration(
        color: AppDesignTokens.surfaceCream,
        borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.10)),
        boxShadow: shadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTapMeal,
                splashFactory: NoSplash.splashFactory,
                splashColor: Colors.transparent,
                highlightColor: Colors.transparent,
                hoverColor: Colors.transparent,
                child: Padding(
                  padding: const EdgeInsets.all(AppDesignTokens.spaceSM),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 44,
                        width: 44,
                        decoration: BoxDecoration(
                          color: meal!.cooked
                              ? const Color(0xFF3F7D53).withValues(alpha: 0.14)
                              : AppDesignTokens.ctaTerracotta.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(AppDesignTokens.radiusButton),
                          border: Border.all(
                            color: meal!.cooked
                                ? const Color(0xFF3F7D53).withValues(alpha: 0.22)
                                : AppDesignTokens.ctaTerracotta.withValues(alpha: 0.18),
                          ),
                        ),
                        child: Icon(
                          meal!.cooked ? Icons.check_rounded : Icons.restaurant_rounded,
                          color: meal!.cooked ? const Color(0xFF3F7D53) : AppDesignTokens.ctaTerracotta,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: Text(meal!.title, style: AppDesignTokens.subheadline.copyWith(height: 1.1))),
                                if (meal!.cooked) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF3F7D53).withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(color: const Color(0xFF3F7D53).withValues(alpha: 0.22)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.check_rounded, size: 12, color: Color(0xFF3F7D53)),
                                        const SizedBox(width: 4),
                                        Text('Cooked', style: AppDesignTokens.caption.copyWith(color: const Color(0xFF3F7D53), fontWeight: FontWeight.w900)),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              meal!.source,
                              style: AppDesignTokens.caption.copyWith(color: AppDesignTokens.textCharcoal.withValues(alpha: 0.70), fontWeight: FontWeight.w700),
                            ),
                            if (isSaving) ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2.2, color: AppDesignTokens.ctaTerracotta)),
                                  const SizedBox(width: 10),
                                  Expanded(child: Text('Saving…', style: AppDesignTokens.caption.copyWith(fontWeight: FontWeight.w800, color: AppDesignTokens.textCharcoal.withValues(alpha: 0.70)))),
                                ],
                              ),
                            ],
                            if (!isSaving && inlineError != null) ...[
                              const SizedBox(height: 8),
                              Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: onRetry,
                                  splashFactory: NoSplash.splashFactory,
                                  splashColor: Colors.transparent,
                                  highlightColor: Colors.transparent,
                                  hoverColor: Colors.transparent,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 2),
                                    child: Row(
                                      children: [
                                        Icon(Icons.error_outline_rounded, size: 18, color: scheme.error.withValues(alpha: 0.9)),
                                        const SizedBox(width: 8),
                                        Expanded(child: Text(inlineError!, style: AppDesignTokens.caption.copyWith(color: scheme.error, fontWeight: FontWeight.w900))),
                                        const SizedBox(width: 8),
                                        const Text('Retry', style: TextStyle(color: AppDesignTokens.ctaTerracotta, fontWeight: FontWeight.w900)),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: meal!.aisleItems.take(4).map((e) {
                                final label = e.qty == null || e.qty!.trim().isEmpty ? e.item : '${e.item} · ${e.qty}';
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: AppDesignTokens.surfaceCream.withValues(alpha: 0.75),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(color: scheme.outline.withValues(alpha: 0.10)),
                                  ),
                                  child: Text(label, style: AppDesignTokens.caption.copyWith(fontWeight: FontWeight.w800)),
                                );
                              }).toList(growable: false),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: AppDesignTokens.spaceXS, right: AppDesignTokens.spaceXS),
            child: IconButton(
              onPressed: onRemove,
              icon: Icon(Icons.close_rounded, color: AppDesignTokens.textCharcoal.withValues(alpha: 0.75)),
              style: const ButtonStyle(overlayColor: WidgetStatePropertyAll(Colors.transparent)),
              tooltip: 'Remove meal',
            ),
          ),
        ],
      ),
    );
  }
}

class _AddMealOptionsSheet extends StatelessWidget {
  const _AddMealOptionsSheet({required this.dayLabel, required this.onClearFridge, required this.onCustomCraving, required this.onDiscountMeal});

  final String dayLabel;
  final VoidCallback onClearFridge;
  final VoidCallback onCustomCraving;
  final VoidCallback onDiscountMeal;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppDesignTokens.spaceSM, AppDesignTokens.spaceXS, AppDesignTokens.spaceSM, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Add meal for $dayLabel', style: AppDesignTokens.headline),
          const SizedBox(height: 6),
          Text('Choose a fast path:', style: AppDesignTokens.body.copyWith(color: AppDesignTokens.textCharcoal.withValues(alpha: 0.75))),
          const SizedBox(height: 14),
          _SheetOptionTile(
            icon: Icons.auto_fix_high_rounded,
            title: 'Clear Fridge Leftovers',
            subtitle: 'Pick scraps, generate 3 ideas, then save one into this day.',
            accent: AppDesignTokens.ctaTerracotta,
            onTap: onClearFridge,
          ),
          const SizedBox(height: 10),
          _SheetOptionTile(
            icon: Icons.auto_awesome_rounded,
            title: 'Custom AI Craving',
            subtitle: 'Type a craving or dish — Chef Harris generates a recipe for this day.',
            accent: AppDesignTokens.ctaTerracotta,
            onTap: onCustomCraving,
          ),
          const SizedBox(height: 10),
          _SheetOptionTile(
            icon: Icons.local_offer_rounded,
            title: 'Supermarket Discount Meal',
            subtitle: 'Budget meal built around current deals (Supabase-backed).',
            accent: AppDesignTokens.ctaTerracotta,
            onTap: onDiscountMeal,
          ),
        ],
      ),
    );
  }
}

class _DealMealSuggestionSheet extends StatefulWidget {
  const _DealMealSuggestionSheet({required this.dayLabel, required this.chefService, required this.profile, required this.onAddMeal});

  final String dayLabel;
  final ChefService chefService;
  final dynamic profile;
  final ValueChanged<_PlannedMeal> onAddMeal;

  @override
  State<_DealMealSuggestionSheet> createState() => _DealMealSuggestionSheetState();
}

class _DealMealSuggestionSheetState extends State<_DealMealSuggestionSheet> {
  bool _loading = true;
  String? _error;
  _PlannedMeal? _meal;
  List<String> _deals = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<List<String>> _fetchDeals({int limit = 10}) async {
    try {
      final db = Supabase.instance.client;

      // 1) Try a dedicated `deals` table if present.
      try {
        final rows = await db.from('deals').select().order('updated_at', ascending: false).range(0, limit - 1);
        if (rows is List) {
          final out = <String>[];
          for (final r in rows) {
            if (r is! Map) continue;
            final name = (r['name'] ?? r['title'] ?? r['item'] ?? '').toString().trim();
            final store = (r['store'] ?? '').toString().trim();
            final price = (r['price'] ?? r['deal_price'] ?? r['discount_price'] ?? '').toString().trim();
            final labelParts = <String>[name];
            if (price.isNotEmpty) labelParts.add(price);
            if (store.isNotEmpty) labelParts.add(store);
            final label = labelParts.where((e) => e.trim().isNotEmpty).join(' · ');
            if (label.isNotEmpty) out.add(label);
          }
          if (out.isNotEmpty) return out.take(limit).toList(growable: false);
        }
      } catch (e) {
        debugPrint('WeeklyPlanner: `deals` table not usable: $e');
      }

      // 2) Fallback: infer deals from `ingredients` badges.
      try {
        final rows = await db.from('ingredients').select().ilike('badge', '%deal%').range(0, limit - 1);
        if (rows is List) {
          final out = rows.whereType<Map>().map((r) => (r['name'] ?? '').toString().trim()).where((e) => e.isNotEmpty).toList(growable: false);
          if (out.isNotEmpty) return out;
        }
      } catch (e) {
        debugPrint('WeeklyPlanner: ingredients badge deal lookup failed: $e');
      }

      try {
        final rows = await db.from('ingredients').select().ilike('badge', '%discount%').range(0, limit - 1);
        if (rows is List) {
          final out = rows.whereType<Map>().map((r) => (r['name'] ?? '').toString().trim()).where((e) => e.isNotEmpty).toList(growable: false);
          if (out.isNotEmpty) return out;
        }
      } catch (e) {
        debugPrint('WeeklyPlanner: ingredients badge discount lookup failed: $e');
      }

      return const [];
    } catch (e) {
      debugPrint('WeeklyPlanner: fetchDeals failed: $e');
      return const [];
    }
  }

  String _buildPrompt(List<String> deals) {
    final dealsText = deals.isEmpty
        ? 'No live deals found in Supabase. Use typical weekly discounts: seasonal veg + chicken/pork + pasta/rice.'
        : 'Current deals (from Supabase):\n- ${deals.take(10).join('\n- ')}';

    return [
      'You are creating ONE budget-friendly weeknight meal for ${widget.dayLabel}.',
      '',
      dealsText,
      '',
      'Rules:',
      '- Base the meal mostly on the deal items. Keep extras minimal (pantry staples only).',
      '- Ingredients should be realistic for a typical supermarket.',
      '',
      'Return ONLY a JSON object with this exact shape:',
      '{"dish":"...","ingredients":[{"aisle":"Produce|Dairy|Meat|Pantry","item":"...","qty":"optional"}]}'
    ].join('\n');
  }

  String _buildCookModePrompt({required String dish, required List<_AisleItem> items}) {
    final ingredients = items
        .map((e) => (e.qty == null || e.qty!.trim().isEmpty) ? e.item : '${e.qty} ${e.item}')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    final ingredientsText = ingredients.isEmpty ? 'Pantry staples only.' : ingredients.join(', ');

    return [
      'Create a cook-mode recipe for this planned meal: "$dish".',
      '',
      'Ingredients available:',
      '- $ingredientsText',
      '- Assume basic pantry staples: salt, pepper, oil.',
      '- Scale realistic quantities for 2 people.',
      '',
      'Return ONLY valid JSON (no markdown, no extra text) matching this schema:',
      '{',
      '  "title": "...",',
      '  "ingredients": [',
      '    {"name": "...", "amount": 0, "unit": "g|ml|tbsp|tsp|piece|clove|slice"}',
      '  ],',
      '  "kitchen_gear": ["..."],',
      '  "steps": [',
      '    {"title":"...","duration_minutes":0,"heat":"low|medium|medium_high|off_heat","bullets":["..."]}',
      '  ]',
      '}',
      '',
      'Guidelines:',
      '- 4–9 steps. Each step duration 1–15 minutes.',
      '- Be precise with heat, timing, and key doneness checks.',
      '- Include ONE witty Chef Harris checkpoint note in a bullet.',
      '- Each ingredient must be a structured object with a numeric "amount" and a "unit". Use "piece", "clove", or "slice" as the unit for whole/countable items instead of inventing a weight.',
    ].join('\n');
  }

  String _formatIngredientAmount(double amount) {
    if (amount == amount.roundToDouble()) return amount.toInt().toString();
    return amount.toStringAsFixed(1);
  }

  String _extractJsonObject(String raw) {
    final t = raw.trim();
    final start = t.indexOf('{');
    final end = t.lastIndexOf('}');
    if (start == -1 || end == -1 || end <= start) return t;
    return t.substring(start, end + 1);
  }

  CookModeRecipePayload? _parseCookModeRecipe(String raw) {
    try {
      final decoded = jsonDecode(_extractJsonObject(raw));
      if (decoded is! Map<String, dynamic>) return null;

      final curriculumLessonIds = _readCurriculumLessonIds(decoded['curriculum_lesson_ids']);

      final title = (decoded['title'] ?? '').toString().trim();

      final ingredients = <String>[];
      final structuredIngredients = <RecipeIngredient>[];
      final ingRaw = decoded['ingredients'];
      if (ingRaw is List) {
        for (final e in ingRaw) {
          if (e is Map) {
            final m = Map<String, dynamic>.from(e);
            final name = (m['name'] ?? '').toString().trim();
            if (name.isEmpty) continue;
            final amount = (m['amount'] is num) ? (m['amount'] as num).toDouble() : double.tryParse('${m['amount'] ?? ''}'.trim()) ?? 0;
            final unit = (m['unit'] ?? '').toString().trim();
            structuredIngredients.add(RecipeIngredient(name: name, amount: amount, unit: unit.isEmpty ? 'piece' : unit));
            final formatted = amount > 0 ? '${_formatIngredientAmount(amount)}${unit.isEmpty ? '' : ' $unit'} $name'.trim() : name;
            ingredients.add(formatted);
          } else {
            // Back-compat: some cached/older responses may still be plain strings.
            final s = e.toString().trim();
            if (s.isNotEmpty) ingredients.add(s);
          }
        }
      }

      final gear = <String>[];
      final gearRaw = decoded['kitchen_gear'];
      if (gearRaw is List) {
        for (final e in gearRaw) {
          final s = e.toString().trim();
          if (s.isNotEmpty) gear.add(s);
        }
      }

      final steps = <CookModeStepPayload>[];
      final stepsRaw = decoded['steps'];
      if (stepsRaw is List) {
        for (final s in stepsRaw) {
          if (s is! Map) continue;
          final stepTitle = (s['title'] ?? '').toString().trim();
          if (stepTitle.isEmpty) continue;
          final duration = int.tryParse('${s['duration_minutes'] ?? ''}'.trim()) ?? 0;
          final heat = (s['heat'] ?? 'medium').toString().trim();
          final bullets = <String>[];
          final bulletsRaw = s['bullets'];
          if (bulletsRaw is List) {
            for (final b in bulletsRaw) {
              final blt = b.toString().trim();
              if (blt.isNotEmpty) bullets.add(blt);
            }
          }
          if (bullets.isEmpty) bullets.add('Keep going and taste as you go.');
          steps.add(CookModeStepPayload(title: stepTitle, heat: heat, durationMinutes: duration, bullets: bullets));
        }
      }

      if (steps.isEmpty) return null;
      return CookModeRecipePayload(
        title: title.isEmpty ? 'Planned meal' : title,
        ingredients: ingredients.isEmpty ? const ['Salt', 'Pepper', 'Cooking oil'] : ingredients,
        steps: steps,
        kitchenGear: gear.isEmpty ? const ['1 Pan or Pot', 'Knife', 'Spoon/Spatula'] : gear,
        structuredIngredients: structuredIngredients.isEmpty ? null : structuredIngredients,
        basePortions: structuredIngredients.isEmpty ? null : 2,
        curriculumLessonIds: curriculumLessonIds,
      );
    } catch (e) {
      debugPrint('WeeklyPlanner: failed to parse cook-mode JSON: $e');
      return null;
    }
  }

  String _buildCurriculumSearchText(CookModeRecipePayload recipe) {
    final b = StringBuffer();
    b.writeln(recipe.title);
    final desc = (recipe.description ?? '').trim();
    if (desc.isNotEmpty) b.writeln(desc);
    for (final step in recipe.steps) {
      b.writeln(step.title);
      for (final bullet in step.bullets) {
        final t = bullet.trim();
        if (t.isNotEmpty) b.writeln(t);
      }
    }
    return b.toString();
  }

  List<String> _readCurriculumLessonIds(dynamic raw) {
    if (raw is! List) return const [];
    final out = <String>[];
    for (final e in raw) {
      final s = e.toString().trim();
      if (s.isNotEmpty) out.add(s);
    }
    return out;
  }

  _PlannedMeal? _parseChefJson(String text) {
    try {
      dynamic decoded;
      try {
        decoded = jsonDecode(text);
      } catch (_) {
        final start = text.indexOf('{');
        final end = text.lastIndexOf('}');
        if (start == -1 || end == -1 || end <= start) return null;
        decoded = jsonDecode(text.substring(start, end + 1));
      }
      if (decoded is! Map) return null;
      final dish = decoded['dish']?.toString().trim();
      final ingredients = decoded['ingredients'];
      if (dish == null || dish.isEmpty || ingredients is! List) return null;

      final items = <_AisleItem>[];
      for (final e in ingredients) {
        if (e is! Map) continue;
        final aisleRaw = e['aisle']?.toString() ?? '';
        final item = e['item']?.toString().trim() ?? '';
        final qty = e['qty']?.toString();
        final aisle = _AisleExt.fromLabel(aisleRaw);
        if (aisle == null || item.isEmpty) continue;
        items.add(_AisleItem(aisle: aisle, item: item, qty: qty));
      }
      if (items.isEmpty) return null;
      return _PlannedMeal(title: dish, source: 'Supermarket Discount Meal', aisleItems: items, recipe: null);
    } catch (e) {
      debugPrint('WeeklyPlanner: parse discount JSON failed: $e');
      return null;
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _meal = null;
    });

    try {
      final deals = await _fetchDeals(limit: 12);
      if (!mounted) return;
      _deals = deals;

      final text = await widget.chefService.askChefHarris(
        userQuery: _buildPrompt(deals),
        profile: widget.profile,
        forceJsonObject: true,
      );
      if (!mounted) return;

      final parsed = _parseChefJson(text);
      if (parsed == null) {
        setState(() {
          _error = 'Chef Harris returned something unexpected. Try again.';
          _loading = false;
        });
        return;
      }

      final cookPrompt = _buildCookModePrompt(dish: parsed.title, items: parsed.aisleItems);
      final cookText = await widget.chefService.askChefHarris(
        userQuery: cookPrompt,
        profile: widget.profile,
        recipeTitle: parsed.title,
        forceJsonObject: true,
      );
      if (!mounted) return;
      final cookPayload = _parseCookModeRecipe(cookText);
      if (cookPayload == null) {
        debugPrint('WeeklyPlanner: discount cook-mode JSON invalid. Raw: $cookText');
        setState(() {
          _error = 'Could not prepare Cook Mode steps. Try again.';
          _loading = false;
        });
        return;
      }

      final matchedCurriculumKeys = widget.chefService.matchedCurriculumDrawerKeys(_buildCurriculumSearchText(cookPayload));

      final merged = <String>[];
      final seen = <String>{};
      for (final id in matchedCurriculumKeys) {
        if (seen.add(id)) merged.add(id);
      }
      for (final id in (cookPayload.curriculumLessonIds ?? const <String>[])) {
        if (seen.add(id)) merged.add(id);
      }
      final cookPayloadWithCurriculum = CookModeRecipePayload(
        title: cookPayload.title,
        ingredients: cookPayload.ingredients,
        steps: cookPayload.steps,
        kitchenGear: cookPayload.kitchenGear,
        description: cookPayload.description,
        structuredIngredients: cookPayload.structuredIngredients,
        basePortions: cookPayload.basePortions,
        curriculumLessonIds: merged,
      );
      debugPrint('CookModeRecipePayload constructed with curriculumLessonIds=${cookPayloadWithCurriculum.curriculumLessonIds}');

      setState(() {
        _meal = parsed.copyWith(recipe: cookPayloadWithCurriculum);
        _loading = false;
      });
    } catch (e) {
      debugPrint('WeeklyPlanner: discount meal failed: $e');
      if (!mounted) return;
      setState(() {
        _error = 'Could not generate a discount meal right now.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: EdgeInsets.only(left: 16, right: 16, top: 10, bottom: 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                height: 38,
                width: 38,
                decoration: BoxDecoration(
                  color: scheme.tertiary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: scheme.tertiary.withValues(alpha: 0.18)),
                ),
                child: Icon(Icons.local_offer_rounded, color: scheme.tertiary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text('Supermarket Discount Meal', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900))),
              IconButton(
                onPressed: () => WidgetsBinding.instance.addPostFrameCallback((_) => context.pop()),
                icon: Icon(Icons.close_rounded, color: scheme.onSurfaceVariant),
                style: const ButtonStyle(overlayColor: WidgetStatePropertyAll(Colors.transparent)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _deals.isEmpty ? 'Generating a budget meal (fallback to typical discounts)…' : 'Using live deals from Supabase (plus pantry staples).',
            style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant, height: 1.35),
          ),
          const SizedBox(height: 12),
          if (_loading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Row(
                children: [
                  SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2.4, color: scheme.tertiary)),
                  const SizedBox(width: 12),
                  Expanded(child: Text('Scanning deals…', style: theme.textTheme.bodyMedium)),
                ],
              ),
            )
          else if (_error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppDesignTokens.spaceSM),
              decoration: BoxDecoration(
                color: scheme.errorContainer.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: scheme.error.withValues(alpha: 0.25)),
              ),
              child: Text(_error!, style: AppDesignTokens.body.copyWith(color: scheme.onErrorContainer, fontWeight: FontWeight.w700)),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppDesignTokens.spaceSM),
              decoration: BoxDecoration(
                color: AppDesignTokens.surfaceCream,
                borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard),
                border: Border.all(color: scheme.outline.withValues(alpha: 0.12)),
                boxShadow: AppDesignTokens.cardShadow,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_meal!.title, style: AppDesignTokens.subheadline),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _meal!.aisleItems.take(10).map((e) {
                      final label = e.qty == null || e.qty!.trim().isEmpty ? e.item : '${e.item} · ${e.qty}';
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppDesignTokens.surfaceCream.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: scheme.outline.withValues(alpha: 0.10)),
                        ),
                        child: Text(label, style: AppDesignTokens.caption.copyWith(fontWeight: FontWeight.w800)),
                      );
                    }).toList(growable: false),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh_rounded, color: AppDesignTokens.ctaTerracotta),
                  label: const Text('Try another', style: TextStyle(color: AppDesignTokens.ctaTerracotta, fontWeight: FontWeight.w900)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: AppDesignTokens.ctaTerracotta.withValues(alpha: 0.45)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppDesignTokens.radiusButton)),
                    foregroundColor: AppDesignTokens.ctaTerracotta,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: (_meal == null || _loading) ? null : () => widget.onAddMeal(_meal!),
                  icon: const Icon(Icons.add_rounded, color: Colors.white),
                  label: const Text('Add meal', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppDesignTokens.ctaTerracotta,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppDesignTokens.radiusButton)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SheetOptionTile extends StatelessWidget {
  const _SheetOptionTile({required this.icon, required this.title, required this.subtitle, required this.accent, required this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: AppDesignTokens.surfaceCream,
      borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard),
      child: InkWell(
        onTap: onTap,
        splashFactory: NoSplash.splashFactory,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard),
        child: Container(
          padding: const EdgeInsets.all(AppDesignTokens.spaceSM),
          decoration: BoxDecoration(
            color: AppDesignTokens.surfaceCream,
            borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard),
            border: Border.all(color: scheme.outline.withValues(alpha: 0.10)),
            boxShadow: AppDesignTokens.cardShadow,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 42,
                width: 42,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppDesignTokens.radiusButton),
                  border: Border.all(color: accent.withValues(alpha: 0.18)),
                ),
                child: Icon(icon, color: accent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppDesignTokens.subheadline),
                    const SizedBox(height: 4),
                    Text(subtitle, style: AppDesignTokens.body.copyWith(color: AppDesignTokens.textCharcoal.withValues(alpha: 0.75), height: 1.3)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.arrow_forward_rounded, color: AppDesignTokens.textCharcoal.withValues(alpha: 0.70)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShoppingListSheet extends StatelessWidget {
  const _ShoppingListSheet({required this.byAisle, required this.hasAnyMeals});

  final Map<_Aisle, List<_AisleItem>> byAisle;
  final bool hasAnyMeals;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final prepController = context.watch<IngredientPrepController>();

    final aisleOrder = <_Aisle>[_Aisle.produce, _Aisle.dairy, _Aisle.meat, _Aisle.pantry];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                height: 38,
                width: 38,
                decoration: BoxDecoration(
                  color: scheme.secondary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: scheme.secondary.withValues(alpha: 0.18)),
                ),
                child: Icon(Icons.shopping_bag_rounded, color: scheme.secondary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Combined Shopping List', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
              ),
              IconButton(
                onPressed: () => WidgetsBinding.instance.addPostFrameCallback((_) => context.pop()),
                icon: Icon(Icons.close_rounded, color: scheme.onSurfaceVariant),
                style: const ButtonStyle(overlayColor: WidgetStatePropertyAll(Colors.transparent)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (!hasAnyMeals)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppDesignTokens.spaceSM),
              decoration: BoxDecoration(
                color: AppDesignTokens.surfaceCream,
                borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard),
                border: Border.all(color: scheme.outline.withValues(alpha: 0.10)),
                boxShadow: AppDesignTokens.cardShadow,
              ),
              child: Text(
                "Nothing here yet — pick a meal or two and I'll build this out.",
                style: AppDesignTokens.body.copyWith(color: AppDesignTokens.textCharcoal.withValues(alpha: 0.75)),
              ),
            )
          else
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final aisle in aisleOrder)
                    if ((byAisle[aisle] ?? const <_AisleItem>[]).isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(aisle.label, style: AppDesignTokens.subheadline),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: AppDesignTokens.surfaceCream,
                          borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard),
                          border: Border.all(color: scheme.outline.withValues(alpha: 0.10)),
                          boxShadow: AppDesignTokens.cardShadow,
                        ),
                        child: Column(
                          children: [
                            for (final item in byAisle[aisle]!)
                              ListTile(
                                dense: true,
                                leading: Icon(
                                   prepController.isPrepped(item.item) ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                                    color: prepController.isPrepped(item.item) ? AppDesignTokens.ctaTerracotta : AppDesignTokens.textCharcoal.withValues(alpha: 0.65),
                                 ),
                                title: Text(item.item, style: AppDesignTokens.body.copyWith(fontWeight: FontWeight.w800)),
                                subtitle: (item.qty == null || item.qty!.trim().isEmpty)
                                    ? null
                                    : Text(item.qty!, style: AppDesignTokens.caption.copyWith(color: AppDesignTokens.textCharcoal.withValues(alpha: 0.70))),
                                contentPadding: const EdgeInsets.symmetric(horizontal: AppDesignTokens.spaceSM, vertical: 2),
                              ),
                          ],
                        ),
                      ),
                    ],
                ],
              ),
            ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: () => WidgetsBinding.instance.addPostFrameCallback((_) => context.pop()),
            icon: const Icon(Icons.check_rounded, color: Colors.white),
            label: const Text('Back to planner', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
            style: FilledButton.styleFrom(
              backgroundColor: AppDesignTokens.ctaTerracotta,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppDesignTokens.radiusButton)),
              minimumSize: const Size.fromHeight(AppSizing.primaryButtonHeight),
            ),
          ),
        ],
      ),
    );
  }
}

enum _Aisle { produce, dairy, meat, pantry }

extension _AisleExt on _Aisle {
  String get label {
    switch (this) {
      case _Aisle.produce:
        return 'Produce';
      case _Aisle.dairy:
        return 'Dairy';
      case _Aisle.meat:
        return 'Meat';
      case _Aisle.pantry:
        return 'Pantry';
    }
  }

  static _Aisle? fromLabel(String raw) {
    final v = raw.trim().toLowerCase();
    if (v.contains('produce') || v.contains('veg') || v.contains('fruit')) return _Aisle.produce;
    if (v.contains('dairy') || v.contains('cheese') || v.contains('milk')) return _Aisle.dairy;
    if (v.contains('meat') || v.contains('protein') || v.contains('fish') || v.contains('poultry')) return _Aisle.meat;
    if (v.contains('pantry') || v.contains('dry') || v.contains('spice') || v.contains('oil')) return _Aisle.pantry;
    switch (v) {
      case 'produce':
        return _Aisle.produce;
      case 'dairy':
        return _Aisle.dairy;
      case 'meat':
        return _Aisle.meat;
      case 'pantry':
        return _Aisle.pantry;
    }
    return null;
  }
}

class _AisleItem {
  const _AisleItem({required this.aisle, required this.item, this.qty, this.amount, this.unit});

  final _Aisle aisle;
  final String item;

  /// Free-text quantity, used for legacy/unstructured ingredients or once
  /// merged across meals (see [_mergeAisleItems]).
  final String? qty;

  /// Structured quantity, when this item came from a recipe's
  /// [CookModeRecipePayload.structuredIngredients] — enables real summing
  /// across meals instead of listing the same ingredient twice.
  final double? amount;
  final String? unit;
}

class _PlannedMeal {
  const _PlannedMeal({required this.title, required this.source, required this.aisleItems, required this.recipe, this.cooked = false});

  final String title;
  final String source;
  final List<_AisleItem> aisleItems;

  /// Full Cook Mode payload so the user can cook this planned meal.
  final CookModeRecipePayload? recipe;

  /// True once a Cook Mode session for this planned meal has genuinely
  /// finished. The slot stays visible either way — this only adds a badge.
  final bool cooked;

  _PlannedMeal copyWith({String? title, String? source, List<_AisleItem>? aisleItems, CookModeRecipePayload? recipe, bool? cooked}) => _PlannedMeal(
    title: title ?? this.title,
    source: source ?? this.source,
    aisleItems: aisleItems ?? this.aisleItems,
    recipe: recipe ?? this.recipe,
    cooked: cooked ?? this.cooked,
  );
}