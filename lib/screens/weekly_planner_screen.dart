import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:optimeal/models/cook_mode_recipe_codec.dart';
import 'package:optimeal/models/planner_slot_ref.dart';
import 'package:optimeal/models/planner_week.dart';
import 'package:optimeal/nav.dart';
import 'package:optimeal/theme/app_design_tokens.dart';
import 'package:optimeal/widgets/app_bottom_sheet.dart';
import 'package:optimeal/widgets/custom_ai_recipe_creator_sheet.dart';
import 'package:optimeal/screens/one_pan_cooking_roadmap_screen.dart';
import 'package:optimeal/services/data_change_signal.dart';
import 'package:optimeal/services/saved_recipes_service.dart';
import 'package:optimeal/services/weekly_plan_service.dart';
import 'package:optimeal/services/weekly_planner_intent_service.dart';
import 'package:optimeal/widgets/recipe_provenance_badges.dart';

/// How the two visible weeks are addressed **inside this screen**.
///
/// These are view offsets into a 0–13 index space — this week's Mon–Sun are
/// 0–6, next week's are 7–13 — used for the day cards, the per-slot inline
/// error keys and the in-flight write set. They are **not** a storage
/// encoding. That distinction is new: until migration `20260822120000` the
/// same 0–13 integer WAS what went into `user_meal_plans.day_index`, because
/// the table had no week column and nothing anchored a week to a date, so
/// neither week ever rolled over.
///
/// Now every row carries `week_start` (the Monday of its week) and
/// `day_index` is 0–6 again on both weeks. The mapping between the two lives
/// in `_weekStartValueFor` / `_dayOfWeekFor` / `_absoluteIndexFor`, and both
/// Mondays are computed from the clock at read time — see
/// `lib/models/planner_week.dart` — so rollover happens by itself at midnight
/// on Sunday with nothing to advance and nothing stored.
const int kDaysPerWeek = 7;
const int kThisWeekOffset = 0;
const int kNextWeekOffset = 7;

/// The most meals one day can hold.
const int kMaxMealsPerDay = 2;

/// How one planned meal row renders. Derived, never stored.
enum PlannerMealState {
  /// A meal that is simply scheduled: cream row, chevron.
  planned,

  /// Today's uncooked meal — the only row that gets a terracotta button.
  cookable,

  /// Cooked, and the recipe's own provenance earned a Waste Ledger rescue.
  cookedCounted,

  /// Cooked, but not rescue-eligible. Not a failure — a neutral check.
  cookedNotCounted,
}

/// The single state table for a planned meal row.
///
/// Pure and top-level so the rules are testable without pumping a screen.
/// Two things decide everything:
///
/// - **Cooked** comes from the persisted `user_meal_plans.is_cooked` flag.
/// - **Counted** is NOT a ledger lookup. Whether a cook counts is a property
///   of the recipe (`RecipeOrigin.isRescueEligible`) — the same rule
///   `selectLedgerVerdict` applies — so it is derivable from the planned meal
///   alone, with no join to `waste_ledger_events` (which carries no recipe
///   reference at all: Cook Mode writes `recipe_id: null`).
///
/// Next week never shows a Cook button or a check: it is not today, and
/// nothing in it can have been cooked yet.
PlannerMealState plannerMealStateFor({
  required bool cooked,
  required bool rescueEligible,
  required bool isToday,
  required bool isThisWeek,
}) {
  if (!isThisWeek) return PlannerMealState.planned;
  if (cooked) {
    return rescueEligible
        ? PlannerMealState.cookedCounted
        : PlannerMealState.cookedNotCounted;
  }
  return isToday ? PlannerMealState.cookable : PlannerMealState.planned;
}

/// The Weekly Planner — all seven days of one week as a single vertical list.
///
/// Redesigned 2026-08-22. What died with the previous build: the day-chip
/// strip, the one-day-at-a-time detail body it drove, and the "Slot 1 / Slot
/// 2" cards. A day is now one card holding its 0–2 meals as rows, and the
/// whole week is on screen at once.
///
/// Day/row states are Empty, Planned, Today (the screen's only terracotta
/// button), Cooked-counted (gold check) and Cooked-didn't-count (gray check);
/// see [plannerMealStateFor], which is where the rules actually live. The
/// week toggle moves between this week and next week only — there is no way
/// back into the past, by design.
///
/// The three-source add sheet below is signed and unchanged by this redesign.
class WeeklyPlannerScreen extends StatefulWidget {
  const WeeklyPlannerScreen({
    super.key,
    this.savedRecipesService,
    this.backend,
    this.now,
  });

  /// Injectable for tests. Defaults to the shared singleton, which is what
  /// keeps My recipes consistent across surfaces.
  final SavedRecipesService? savedRecipesService;

  /// Injectable for tests. Defaults to the real `user_meal_plans` transport.
  final WeeklyPlanBackend? backend;

  /// Injectable "today" so the Today state can be tested on a fixed weekday
  /// instead of whichever day the suite happens to run on.
  final DateTime? now;

  @override
  State<WeeklyPlannerScreen> createState() => _WeeklyPlannerScreenState();
}

class _WeeklyPlannerScreenState extends State<WeeklyPlannerScreen> {
  static const _days = <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _daysLong = <String>[
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday'
  ];

  /// [kThisWeekOffset] or [kNextWeekOffset]. There is deliberately no third
  /// value: no past navigation.
  int _weekOffset = kThisWeekOffset;

  bool _planLoading = true;
  String? _planLoadError;

  /// The loader is a first-paint affordance only. Once the week has been on
  /// screen, a background re-read (a change signal, a stale-read retry) must
  /// not flash "Loading your saved week…" over a list the user is looking at.
  bool _hasLoadedOnce = false;

  /// Inline, per-slot error strings keyed by "dayIndex-slotIndex", where
  /// dayIndex is the ABSOLUTE 0–13 index, not the position in the visible
  /// week.
  final Map<String, String> _slotInlineErrors = <String, String>{};

  /// Tracks which slots currently have an in-flight optimistic write.
  final Set<String> _pendingSlotWrites = <String>{};

  /// Keyed by absolute day index (0–13) — see [kNextWeekOffset].
  final Map<int, List<_PlannedMeal>> _planned = <int, List<_PlannedMeal>>{};

  /// Bumped by every local mutation (add, remove). A load that started before
  /// the bump is stale by the time it returns and must not be applied — see
  /// [_loadPlanFromSupabase].
  int _writeEpoch = 0;

  /// Set when a load was discarded as stale. The next moment no slot write is
  /// in flight, the plan is re-read so the discarded snapshot is replaced by
  /// one that actually contains the new row.
  bool _reloadWhenWritesSettle = false;

  late final VoidCallback _intentListener;

  /// Write-driven invalidation, the same mechanism Home uses (see
  /// `lib/services/data_change_signal.dart`). This screen stays mounted
  /// underneath Cook Mode, and the old "await the pushed route's bool result"
  /// approach could not survive the post-cook `context.go('/')` — it completed
  /// that future with null. Data announces itself instead.
  StreamSubscription<void>? _ledgerSub;
  StreamSubscription<void>? _cookLogSub;

  /// `user_meal_plans` changed from outside this screen — today that means a
  /// finished cook marking the slot it was launched from as cooked
  /// (`PlannerCookAttributionService`). It is a third subscription rather than
  /// a third mechanism: it lands in the same [_onExternalDataChanged] handler
  /// as the other two, and the same re-read flips the row in place. It has to
  /// be its own signal because [AppDataChanges.cookLog] fires at the *top* of
  /// the post-cook sequence, before the plan row has been written.
  StreamSubscription<void>? _mealPlanSub;
  bool _signalReloadQueued = false;

  late final WeeklyPlanBackend _backend =
      widget.backend ?? SupabaseWeeklyPlanBackend();

  DateTime get _now => widget.now ?? DateTime.now();

  /// Monday-based index of today, 0–6.
  int get _todayIndex => _now.weekday - DateTime.monday;

  bool get _isThisWeek => _weekOffset == kThisWeekOffset;

  /// The two weeks this screen can show, recomputed from the clock every time
  /// they are asked for. Nothing here is stored or advanced: at midnight on
  /// Sunday, [_thisWeekStart] simply starts returning the next Monday, last
  /// week's rows stop being read at all, and what was "next week" becomes
  /// "this week" with no migration and no state change. Past weeks are not
  /// deleted — there is just no way to select one, by design.
  DateTime get _thisWeekStart => plannerWeekStartFor(_now);
  DateTime get _nextWeekStart => plannerWeekAfter(_thisWeekStart);

  /// The `week_start` value an absolute 0–13 index belongs to.
  String _weekStartValueFor(int absoluteDayIndex) => plannerWeekValue(
      absoluteDayIndex < kNextWeekOffset ? _thisWeekStart : _nextWeekStart);

  /// The stored 0–6 `day_index` for an absolute 0–13 index.
  int _dayOfWeekFor(int absoluteDayIndex) => absoluteDayIndex % kDaysPerWeek;

  /// The inverse: a stored row's `(week_start, day_index)` back to this
  /// screen's 0–13 index. Null for any other week — a row from a week that has
  /// rolled into the past is ignored rather than rendered somewhere wrong.
  int? _absoluteIndexFor(String weekStartValue, int dayIndex) {
    if (dayIndex < 0 || dayIndex >= kDaysPerWeek) return null;
    if (weekStartValue == plannerWeekValue(_thisWeekStart)) {
      return kThisWeekOffset + dayIndex;
    }
    if (weekStartValue == plannerWeekValue(_nextWeekStart)) {
      return kNextWeekOffset + dayIndex;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _intentListener = _consumePendingPlannerIntent;
    WeeklyPlannerIntentService.instance.pendingAddMeal.addListener(_intentListener);
    WidgetsBinding.instance.addPostFrameCallback((_) => _consumePendingPlannerIntent());

    _ledgerSub = AppDataChanges.ledger.listen(_onExternalDataChanged);
    _cookLogSub = AppDataChanges.cookLog.listen(_onExternalDataChanged);
    _mealPlanSub = AppDataChanges.mealPlan.listen(_onExternalDataChanged);

    // Hydrate the plan for the signed-in user.
    unawaited(_loadPlanFromSupabase());
  }

  @override
  void dispose() {
    _ledgerSub?.cancel();
    _cookLogSub?.cancel();
    _mealPlanSub?.cancel();
    WeeklyPlannerIntentService.instance.pendingAddMeal.removeListener(_intentListener);
    super.dispose();
  }

  /// A completed cook fires both signals; coalesce them into one re-read
  /// rather than hitting the network twice for one event. Signals raised in
  /// separate event-loop turns still cost two reads, which is fine — the
  /// point is correctness, and the read is idempotent.
  void _onExternalDataChanged() {
    if (!mounted || _signalReloadQueued) return;
    _signalReloadQueued = true;
    scheduleMicrotask(() {
      _signalReloadQueued = false;
      if (!mounted) return;
      unawaited(_loadPlanFromSupabase());
    });
  }

  void _consumePendingPlannerIntent() {
    if (!mounted) return;
    final intent = WeeklyPlannerIntentService.instance.consumePending();
    if (intent == null) return;
    _addMealToDayFromIntent(intent);
  }

  void _addMealToDayFromIntent(WeeklyPlannerAddMealIntent intent) {
    // Intents come from WeekdayPickerSheet, which offers Mon–Sun of THIS
    // week only — so the absolute index is the raw one. Snap the view back to
    // this week, or the meal would land somewhere the user cannot see.
    final dayIndex = intent.dayIndex.clamp(0, kDaysPerWeek - 1);
    setState(() => _weekOffset = kThisWeekOffset);

    if (!_dayHasRoom(dayIndex)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('${_days[dayIndex]} already has $kMaxMealsPerDay meals.'),
            behavior: SnackBarBehavior.floating),
      );
      return;
    }

    final meal = _PlannedMeal(
      title: intent.recipe.title,
      source: intent.source,
      recipe: intent.recipe,
    );
    _optimisticallyAddMeal(dayIndex: dayIndex, meal: meal);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Added to ${_daysLong[dayIndex]}!'), behavior: SnackBarBehavior.floating),
    );
  }

  List<_PlannedMeal> _mealsFor(int dayIndex) =>
      _planned[dayIndex] ?? const <_PlannedMeal>[];

  bool _dayHasRoom(int dayIndex) => _mealsFor(dayIndex).length < kMaxMealsPerDay;

  /// The single add sheet. Three sources, and My recipes is a **pane swap
  /// inside this same sheet** (back arrow returns to the source list) — never
  /// a second sheet on top. Sheets do not stack anywhere in this app.
  ///
  /// Signed and unchanged by the 2026-08-22 redesign: only what opens it
  /// moved (an empty day card, or the day-detail sheet's "add another").
  Future<void> _showAddMealSheet(int dayIndex) async {
    final picked = await AppBottomSheet.show<CookModeRecipePayload>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: AppDesignTokens.surfaceCream,
      builder: (ctx) => SafeArea(
        child: _AddMealSheet(
          dayLabel: _days[dayIndex % kDaysPerWeek],
          savedRecipesService: widget.savedRecipesService,
          onClearFridge: () => _postFrame(() async {
            context.pop();
            await _pickMealFromFridgeClearer(dayIndex);
          }),
          onCustomCraving: () => _postFrame(() async {
            context.pop();
            await _customAiCravingForDay(dayIndex);
          }),
        ),
      ),
    );

    if (picked == null || !mounted) return;
    _addSavedRecipeToDay(dayIndex, picked);
  }

  /// Places a recipe chosen from the My recipes pane into [dayIndex].
  ///
  /// The full [CookModeRecipePayload] goes in — including `origin` and
  /// `originEnteredIngredients` — so a Fridge Clearer recipe planned this way
  /// still counts as a rescue when it is cooked. The payload codec persists
  /// both fields into `user_meal_plans.recipe_payload`; nothing here derives
  /// provenance from the source label.
  void _addSavedRecipeToDay(int dayIndex, CookModeRecipePayload recipe) {
    if (!_dayHasRoom(dayIndex)) return;
    final meal = _PlannedMeal(
      title: recipe.title,
      source: kFromSavedMealSource,
      recipe: recipe,
    );
    _optimisticallyAddMeal(dayIndex: dayIndex, meal: meal);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text('Added “${meal.title}”.'),
          behavior: SnackBarBehavior.floating),
    );
  }

  void _postFrame(Future<void> Function() fn) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await fn();
    });
  }

  /// Launches Cook Mode for a planned meal.
  ///
  /// **Provenance travels in the payload, untouched.** A Fridge Clearer
  /// recipe cooked from here is still a rescue, because `origin` and
  /// `originEnteredIngredients` ride inside [CookModeRecipePayload] — the
  /// launch surface decides nothing (see `docs/DECISIONS.md`).
  ///
  /// **Slot identity travels beside it, stamped here and only here.** The
  /// `(dayIndex, slotIndex)` of the row whose Cook button was pressed goes out
  /// as a [PlannerSlotRef] on the launch request, and the completed cook marks
  /// exactly that row cooked (`PlannerCookAttributionService`). This is the
  /// same architectural move as `RecipeOrigin`: stamp the fact at the one
  /// moment it is known, carry it, never re-derive it later. It is what makes
  /// the two cooked states reachable at all — and why the same dish planned on
  /// two days flips only the day that was launched.
  ///
  /// Nothing is awaited: the post-cook sequence leaves via `context.go('/')`,
  /// which removes this page and would complete any awaited result with null.
  /// The row comes back cooked through [AppDataChanges.mealPlan] instead.
  void _cookPlannedMeal(int dayIndex, int slotIndex) {
    final meals = _mealsFor(dayIndex);
    if (slotIndex < 0 || slotIndex >= meals.length) return;
    final meal = meals[slotIndex];
    final recipe = meal.recipe;
    if (recipe == null) {
      debugPrint('WeeklyPlanner: planned meal missing Cook Mode payload: ${meal.title}');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This meal is missing Cook Mode steps.'), behavior: SnackBarBehavior.floating),
      );
      return;
    }

    context.push(
      AppRoutes.onePanCookingRoadmap,
      extra: CookModeLaunchRequest(
        recipe: recipe,
        surface: CookModeSurface.weeklyPlanner,
        plannerSlot: PlannerSlotRef(
          weekStart: _weekStartValueFor(dayIndex),
          dayIndex: _dayOfWeekFor(dayIndex),
          slotIndex: slotIndex,
        ),
      ),
    );
  }

  Future<void> _pickMealFromFridgeClearer(int dayIndex) async {
    if (!_dayHasRoom(dayIndex)) return;

    try {
      final result = await context.push<Object?>(AppRoutes.fridgeClearerPicker);
      if (!mounted) return;

      if (result is! CookModeRecipePayload) return;

      final meal = _PlannedMeal(
        title: result.title,
        source: 'Clear Fridge Leftovers',
        recipe: result,
      );
      _optimisticallyAddMeal(dayIndex: dayIndex, meal: meal);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added “${meal.title}”.'), behavior: SnackBarBehavior.floating),
      );
    } catch (e) {
      debugPrint('WeeklyPlanner: fridge picker failed: $e');
    }
  }

  Future<void> _customAiCravingForDay(int dayIndex) async {
    if (!_dayHasRoom(dayIndex)) return;

    try {
      final payload = await AppBottomSheet.show<CookModeRecipePayload>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        backgroundColor: AppDesignTokens.surfaceCream,
        builder: (ctx) => const SafeArea(child: CustomAiRecipeCreatorSheet()),
      );
      if (!mounted || payload == null) return;

      final meal = _PlannedMeal(
        title: payload.title,
        source: 'Custom AI Craving',
        recipe: payload,
      );
      _optimisticallyAddMeal(dayIndex: dayIndex, meal: meal);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added “${meal.title}”.'), behavior: SnackBarBehavior.floating),
      );
    } catch (e) {
      debugPrint('WeeklyPlanner: custom craving failed: $e');
    }
  }

  /// The day's detail — a sheet, not a screen. Reached by tapping a planned
  /// row, and the only place a day's SECOND meal is added or a meal removed,
  /// so a filled row stays clean (no inline "+", no inline "x").
  ///
  /// Every action closes this sheet first and then acts, which is how the
  /// add sheet's own Fridge Clearer / Custom Craving options already behave:
  /// sheets never stack in this app.
  Future<void> _showDayDetail(int dayIndex) async {
    await AppBottomSheet.show<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: AppDesignTokens.surfaceCream,
      builder: (ctx) => SafeArea(
        child: _DayDetailSheet(
          dayLabel: _daysLong[dayIndex % kDaysPerWeek],
          meals: _mealsFor(dayIndex),
          canAddAnother: _dayHasRoom(dayIndex),
          onOpenRecipe: (recipe) => _postFrame(() async {
            context.pop();
            if (!mounted) return;
            context.push(AppRoutes.recipe, extra: recipe);
          }),
          onRemove: (slotIndex) => _postFrame(() async {
            context.pop();
            if (!mounted) return;
            _optimisticallyRemoveMeal(dayIndex: dayIndex, slotIndex: slotIndex);
          }),
          onAddAnother: () => _postFrame(() async {
            context.pop();
            await _showAddMealSheet(dayIndex);
          }),
        ),
      ),
    );
  }

  String _slotKey(int dayIndex, int slotIndex) => '$dayIndex-$slotIndex';

  /// Null when there is no signed-in user — and also when Supabase was never
  /// initialized at all. Every caller here treats null as "keep the local,
  /// in-memory plan and stop showing the loader", which is exactly the right
  /// behaviour in that case too. See [WeeklyPlanBackend.currentUserId].
  String? _userId() => _backend.currentUserId;

  /// [dayIndex] is this screen's absolute 0–13 index; the row it builds carries
  /// the anchored `(week_start, day_index 0–6)` pair the table actually stores.
  Map<String, dynamic> _plannedMealToPlanRow({required String userId, required int dayIndex, required int slotIndex, required _PlannedMeal meal}) => {
    'user_id': userId,
    'week_start': _weekStartValueFor(dayIndex),
    'day_index': _dayOfWeekFor(dayIndex),
    'slot_index': slotIndex,
    'title': meal.title,
    'source': meal.source,
    'recipe_payload': meal.recipe == null ? null : cookModeRecipeToJson(meal.recipe!),
    'is_cooked': meal.cooked,
    'updated_at': DateTime.now().toUtc().toIso8601String(),
    // `aisle_items` is deliberately not written any more: the ingredient
    // pills it fed were cut with the slot cards, and the shopping list that
    // originally needed aisles was cut in August. Existing rows keep theirs —
    // an upsert only sets the columns it sends.
  };

  _PlannedMeal? _plannedMealFromPlanRow(Map row) {
    try {
      final title = (row['title'] ?? '').toString().trim();
      final source = (row['source'] ?? '').toString().trim();
      if (title.isEmpty) return null;

      final recipe = cookModeRecipeFromJson(row['recipe_payload'] ?? row['recipePayload']);
      final cooked = (row['is_cooked'] ?? row['isCooked']) == true;
      return _PlannedMeal(
        title: title,
        source: source.isEmpty ? 'Planned meal' : source,
        recipe: recipe,
        cooked: cooked,
      );
    } catch (e) {
      debugPrint('WeeklyPlanner: failed to parse plan row: $e');
      return null;
    }
  }

  /// Reads the whole plan back and replaces local state with it.
  ///
  /// **The replacement is conditional, and that is the point.** This is a
  /// one-shot read of data this screen also writes, so it can lose a race:
  /// the classic case is arriving here with a queued
  /// [WeeklyPlannerAddMealIntent] (from Fridge Clearer, My recipes, or a
  /// generation sheet). `initState` starts this read, the intent is consumed
  /// on the first frame and places the meal optimistically, its upsert lands —
  /// and then this read, issued *before* that upsert, returns a snapshot with
  /// no such row and wipes the meal off the screen. The row is in the
  /// database the whole time, which is why it reappeared "after a restart"
  /// (device report, 2026-08-22, symptom B).
  ///
  /// So: capture [_writeEpoch] before the read, and if any local mutation
  /// happened while it was in flight, discard the snapshot instead of applying
  /// it, and re-read once the writes it missed have settled.
  Future<void> _loadPlanFromSupabase() async {
    final userId = _userId();
    if (userId == null) {
      // No auth: keep existing local behavior, but stop showing loader.
      if (!mounted) return;
      setState(() {
        _planLoading = false;
        _planLoadError = null;
      });
      return;
    }

    if (!mounted) return;
    if (!_hasLoadedOnce) {
      setState(() {
        _planLoading = true;
        _planLoadError = null;
      });
    }

    final epochAtReadStart = _writeEpoch;

    try {
      // Week-scoped: only the two weeks this screen can show are asked for, so
      // rows from a week that has rolled into the past never arrive.
      final rows = await _backend.listForWeeks(userId, weekStarts: [
        plannerWeekValue(_thisWeekStart),
        plannerWeekValue(_nextWeekStart),
      ]);

      final next = <int, List<_PlannedMeal>>{};
      for (final r in rows) {
        final storedDay = int.tryParse('${r['day_index'] ?? r['dayIndex'] ?? ''}'.trim());
        final slotIndex = int.tryParse('${r['slot_index'] ?? r['slotIndex'] ?? ''}'.trim());
        final weekStart = '${r['week_start'] ?? r['weekStart'] ?? ''}'.trim();
        if (storedDay == null || slotIndex == null) continue;
        if (slotIndex < 0 || slotIndex >= kMaxMealsPerDay) continue;

        // A `date` column can come back as a bare `yyyy-MM-dd` or with a time
        // component depending on the transport; take the date part either way.
        final dayIndex =
            _absoluteIndexFor(weekStart.split('T').first, storedDay);
        // Belt and braces: the query already filtered to these two weeks.
        if (dayIndex == null) continue;

        final meal = _plannedMealFromPlanRow(r);
        if (meal == null) continue;

        final list = next[dayIndex] ??= <_PlannedMeal>[];
        // Keep slots ordered by slot_index.
        while (list.length <= slotIndex) {
          list.add(const _PlannedMeal(title: '', source: '', recipe: null));
        }
        list[slotIndex] = meal;
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

      if (_writeEpoch != epochAtReadStart) {
        // Stale snapshot: something was placed or removed while this read was
        // in flight. Local state is newer — keep it, and re-read once the
        // writes that this snapshot missed have landed.
        debugPrint(
            'WeeklyPlanner: discarding a plan read that a local write raced past.');
        setState(() {
          _planLoading = false;
          _hasLoadedOnce = true;
          _planLoadError = null;
        });
        _reloadWhenWritesSettle = true;
        _reloadIfWritesSettled();
        return;
      }

      setState(() {
        _planned
          ..clear()
          ..addAll(next);
        _planLoading = false;
        _hasLoadedOnce = true;
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

  /// Runs the re-read a stale load asked for, but only once every slot write
  /// is done — otherwise the re-read would race exactly the same way the
  /// discarded one did. Called from the `finally` of both write paths.
  void _reloadIfWritesSettled() {
    if (!_reloadWhenWritesSettle) return;
    if (_pendingSlotWrites.isNotEmpty) return;
    _reloadWhenWritesSettle = false;
    unawaited(_loadPlanFromSupabase());
  }

  Future<void> _persistMealSlot({required int dayIndex, required int slotIndex, required _PlannedMeal meal}) async {
    final key = _slotKey(dayIndex, slotIndex);
    final userId = _userId();
    if (userId == null) {
      if (!mounted) return;
      setState(() => _pendingSlotWrites.remove(key));
      return;
    }

    try {
      final row = _plannedMealToPlanRow(userId: userId, dayIndex: dayIndex, slotIndex: slotIndex, meal: meal);
      await _backend.upsertSlot(row);
    } catch (e) {
      debugPrint('WeeklyPlanner: persistMealSlot failed: $e');
      rethrow;
    } finally {
      if (mounted) {
        setState(() => _pendingSlotWrites.remove(key));
        _reloadIfWritesSettled();
      }
    }
  }

  Future<void> _deleteMealSlot({required int dayIndex, required int slotIndex}) async {
    final key = _slotKey(dayIndex, slotIndex);
    final userId = _userId();
    if (userId == null) {
      if (!mounted) return;
      setState(() => _pendingSlotWrites.remove(key));
      return;
    }

    try {
      await _backend.deleteSlot(
          userId: userId,
          weekStart: _weekStartValueFor(dayIndex),
          dayIndex: _dayOfWeekFor(dayIndex),
          slotIndex: slotIndex);
    } catch (e) {
      debugPrint('WeeklyPlanner: deleteMealSlot failed: $e');
      rethrow;
    } finally {
      if (mounted) {
        setState(() => _pendingSlotWrites.remove(key));
        _reloadIfWritesSettled();
      }
    }
  }

  void _optimisticallyAddMeal({required int dayIndex, required _PlannedMeal meal}) {
    final meals = _planned[dayIndex] ??= <_PlannedMeal>[];
    if (meals.length >= kMaxMealsPerDay) return;
    final slotIndex = meals.length;
    final key = _slotKey(dayIndex, slotIndex);

    setState(() {
      _writeEpoch++;
      _slotInlineErrors.remove(key);
      _pendingSlotWrites.add(key);
      meals.add(meal);
    });

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
      }
    }());
  }

  void _optimisticallyRemoveMeal({required int dayIndex, required int slotIndex}) {
    final meals = _planned[dayIndex] ??= <_PlannedMeal>[];
    if (slotIndex < 0 || slotIndex >= meals.length) return;

    final removed = meals[slotIndex];
    final key = _slotKey(dayIndex, slotIndex);

    setState(() {
      _writeEpoch++;
      _slotInlineErrors.remove(key);
      _pendingSlotWrites.add(key);
      meals.removeAt(slotIndex);
    });

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
        }
      }());
    } else {
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
        }
      }());
    }
  }

  /// The first inline error anywhere in [dayIndex]'s slots, with the slot it
  /// belongs to — the day card shows one line, not one per slot.
  MapEntry<int, String>? _dayInlineError(int dayIndex) {
    for (var slot = 0; slot < kMaxMealsPerDay; slot++) {
      final message = _slotInlineErrors[_slotKey(dayIndex, slot)];
      if (message != null) return MapEntry(slot, message);
    }
    return null;
  }

  bool _dayIsSaving(int dayIndex) {
    for (var slot = 0; slot < kMaxMealsPerDay; slot++) {
      if (_pendingSlotWrites.contains(_slotKey(dayIndex, slot))) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: AppDesignTokens.backgroundSage,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        // Depth-1: back button only, and back lands on Home.
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
        // SIGNED-CONTENT PLACEHOLDER
        title: const Text('Weekly Planner', style: AppDesignTokens.headline),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppDesignTokens.spaceSM, 4, AppDesignTokens.spaceSM, 12),
            child: _WeekToggle(
              isThisWeek: _isThisWeek,
              onChanged: (thisWeek) => setState(() =>
                  _weekOffset = thisWeek ? kThisWeekOffset : kNextWeekOffset),
            ),
          ),
          if (_planLoading)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppDesignTokens.spaceSM, 0, AppDesignTokens.spaceSM, 10),
              child: Row(
                children: [
                  const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2.4, color: AppDesignTokens.ctaTerracotta)),
                  const SizedBox(width: 12),
                  Expanded(child: Text('Loading your saved week…', style: AppDesignTokens.body.copyWith(fontWeight: FontWeight.w700))),
                ],
              ),
            )
          else if (_planLoadError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppDesignTokens.spaceSM, 0, AppDesignTokens.spaceSM, 10),
              child: Container(
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
            ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(AppDesignTokens.spaceSM, 0, AppDesignTokens.spaceSM, AppDesignTokens.spaceMD),
              itemCount: kDaysPerWeek,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final absoluteIndex = _weekOffset + i;
                final inlineError = _dayInlineError(absoluteIndex);
                return _DayCard(
                  dayLabel: _days[i],
                  meals: _mealsFor(absoluteIndex),
                  isToday: _isThisWeek && i == _todayIndex,
                  isThisWeek: _isThisWeek,
                  isSaving: _dayIsSaving(absoluteIndex),
                  inlineError: inlineError?.value,
                  onRetry: inlineError == null
                      ? null
                      : () => _retrySlot(absoluteIndex, inlineError.key),
                  onAdd: () => _showAddMealSheet(absoluteIndex),
                  onOpenDay: () => _showDayDetail(absoluteIndex),
                  onCook: (slotIndex) =>
                      _cookPlannedMeal(absoluteIndex, slotIndex),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// This week ↔ next week. Two states, no third: there is deliberately no way
/// to navigate into the past.
class _WeekToggle extends StatelessWidget {
  const _WeekToggle({required this.isThisWeek, required this.onChanged});

  final bool isThisWeek;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppDesignTokens.deepForest.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppDesignTokens.deepForest.withValues(alpha: 0.14)),
      ),
      child: Row(
        children: [
          // SIGNED-CONTENT PLACEHOLDER
          Expanded(child: _WeekTogglePill(label: 'This week', selected: isThisWeek, onTap: () => onChanged(true))),
          // SIGNED-CONTENT PLACEHOLDER
          Expanded(child: _WeekTogglePill(label: 'Next week', selected: !isThisWeek, onTap: () => onChanged(false))),
        ],
      ),
    );
  }
}

class _WeekTogglePill extends StatelessWidget {
  const _WeekTogglePill({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppDesignTokens.surfaceCream : Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        splashFactory: NoSplash.splashFactory,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppDesignTokens.body.copyWith(
              fontWeight: FontWeight.w900,
              color: selected
                  ? AppDesignTokens.deepForest
                  : AppDesignTokens.deepForest.withValues(alpha: 0.62),
            ),
          ),
        ),
      ),
    );
  }
}

/// One day of the week: empty, or a card holding its 1–2 meal rows.
class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.dayLabel,
    required this.meals,
    required this.isToday,
    required this.isThisWeek,
    required this.isSaving,
    required this.inlineError,
    required this.onRetry,
    required this.onAdd,
    required this.onOpenDay,
    required this.onCook,
  });

  final String dayLabel;
  final List<_PlannedMeal> meals;
  final bool isToday;
  final bool isThisWeek;
  final bool isSaving;
  final String? inlineError;
  final VoidCallback? onRetry;
  final VoidCallback onAdd;
  final VoidCallback onOpenDay;

  /// Takes the meal's slot index within the day, not the meal — the slot is
  /// the identity the completed cook needs to write back (see
  /// [PlannerSlotRef]), and a `_PlannedMeal` carries no identity of its own.
  final ValueChanged<int> onCook;

  @override
  Widget build(BuildContext context) {
    if (meals.isEmpty) {
      return _EmptyDayCard(dayLabel: dayLabel, isToday: isToday, onTap: onAdd);
    }

    // Today gets the champagne tint — the one warm card on the screen. A day
    // whose meals are all cooked steps back down to a faded cream, since
    // there is nothing left to do in it.
    final allCooked = meals.every((m) => m.cooked);
    final Color fill = isToday && !allCooked
        ? AppDesignTokens.champagneTint
        : AppDesignTokens.surfaceCream;

    return Material(
      color: fill,
      borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard),
      child: InkWell(
        onTap: onOpenDay,
        borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard),
        splashFactory: NoSplash.splashFactory,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard),
            border: Border.all(
              color: isToday && !allCooked
                  ? AppDesignTokens.ctaTerracotta.withValues(alpha: 0.30)
                  : AppDesignTokens.textCharcoal.withValues(alpha: 0.10),
            ),
            boxShadow: AppDesignTokens.cardShadow,
          ),
          padding: const EdgeInsets.fromLTRB(AppDesignTokens.spaceSM, 12, AppDesignTokens.spaceSM, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                dayLabel,
                style: AppDesignTokens.caption.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.6,
                  color: isToday
                      ? AppDesignTokens.ctaTerracotta
                      : AppDesignTokens.textCharcoal.withValues(alpha: 0.62),
                ),
              ),
              const SizedBox(height: 8),
              for (var i = 0; i < meals.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 20,
                    thickness: 1,
                    color: AppDesignTokens.textCharcoal.withValues(alpha: 0.10),
                  ),
                _PlannedMealRow(
                  meal: meals[i],
                  state: plannerMealStateFor(
                    cooked: meals[i].cooked,
                    rescueEligible:
                        meals[i].recipe?.origin?.isRescueEligible ?? false,
                    isToday: isToday,
                    isThisWeek: isThisWeek,
                  ),
                  onCook: () => onCook(i),
                ),
              ],
              if (isSaving) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    const SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2.2, color: AppDesignTokens.ctaTerracotta)),
                    const SizedBox(width: 10),
                    Expanded(child: Text('Saving…', style: AppDesignTokens.caption.copyWith(fontWeight: FontWeight.w800))),
                  ],
                ),
              ],
              if (!isSaving && inlineError != null) ...[
                const SizedBox(height: 10),
                _InlineSlotError(message: inlineError!, onRetry: onRetry),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A day with nothing planned: dashed sage outline, one quiet line, and a
/// terracotta-TEXT plus — text, not a button, so the only terracotta button
/// on this screen stays "Cook".
class _EmptyDayCard extends StatelessWidget {
  const _EmptyDayCard({required this.dayLabel, required this.isToday, required this.onTap});

  final String dayLabel;
  final bool isToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard),
        splashFactory: NoSplash.splashFactory,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        child: CustomPaint(
          painter: _DashedRoundedBorderPainter(
            color: AppDesignTokens.deepForest.withValues(alpha: 0.34),
            radius: AppDesignTokens.radiusCard,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppDesignTokens.spaceSM, 14, AppDesignTokens.spaceSM, 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dayLabel,
                        style: AppDesignTokens.caption.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.6,
                          color: isToday
                              ? AppDesignTokens.ctaTerracotta
                              : AppDesignTokens.deepForest.withValues(alpha: 0.62),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        // SIGNED-CONTENT PLACEHOLDER
                        'Nothing planned',
                        style: AppDesignTokens.body.copyWith(
                          color: AppDesignTokens.deepForest.withValues(alpha: 0.72),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '+',
                  style: AppDesignTokens.headline.copyWith(
                    color: AppDesignTokens.ctaTerracotta,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One meal inside a day card. Everything that differs between states lives
/// in the trailing slot: a chevron, a Cook button, or a check.
class _PlannedMealRow extends StatelessWidget {
  const _PlannedMealRow({required this.meal, required this.state, required this.onCook});

  final _PlannedMeal meal;
  final PlannerMealState state;
  final VoidCallback onCook;

  bool get _isCooked =>
      state == PlannerMealState.cookedCounted ||
      state == PlannerMealState.cookedNotCounted;

  /// Provenance carried by the placed recipe itself. Survives the
  /// `recipe_payload` jsonb round trip, so a planner-cooked Fridge Clearer
  /// recipe still counts as a rescue — and this badge still shows — after a
  /// reload.
  bool get _isFridgeRescue => meal.recipe?.origin?.isRescueEligible ?? false;

  @override
  Widget build(BuildContext context) {
    final title = Text(
      meal.title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: AppDesignTokens.subheadline.copyWith(
        height: 1.15,
        color: _isCooked
            ? AppDesignTokens.textCharcoal.withValues(alpha: 0.58)
            : AppDesignTokens.textCharcoal,
      ),
    );

    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              Flexible(child: title),
              if (_isFridgeRescue) ...[
                const SizedBox(width: 8),
                Opacity(
                  opacity: _isCooked ? 0.6 : 1,
                  child: const ProvenanceLeafBadge(compact: true),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 10),
        _MealRowTrailing(state: state, onCook: onCook),
      ],
    );
  }
}

class _MealRowTrailing extends StatelessWidget {
  const _MealRowTrailing({required this.state, required this.onCook});

  final PlannerMealState state;
  final VoidCallback onCook;

  @override
  Widget build(BuildContext context) {
    switch (state) {
      case PlannerMealState.planned:
        return Icon(Icons.chevron_right_rounded,
            color: AppDesignTokens.textCharcoal.withValues(alpha: 0.55));
      case PlannerMealState.cookable:
        return FilledButton(
          onPressed: onCook,
          style: FilledButton.styleFrom(
            backgroundColor: AppDesignTokens.ctaTerracotta,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppDesignTokens.radiusButton)),
          ),
          // SIGNED-CONTENT PLACEHOLDER
          child: const Text('Cook',
              style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white)),
        );
      case PlannerMealState.cookedCounted:
        return const Icon(Icons.check_circle_rounded,
            color: AppDesignTokens.cookedCountedGold);
      case PlannerMealState.cookedNotCounted:
        return const Icon(Icons.check_circle_rounded,
            color: AppDesignTokens.cookedNeutralGray);
    }
  }
}

class _InlineSlotError extends StatelessWidget {
  const _InlineSlotError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onRetry,
        splashFactory: NoSplash.splashFactory,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded, size: 18, color: scheme.error.withValues(alpha: 0.9)),
            const SizedBox(width: 8),
            Expanded(child: Text(message, style: AppDesignTokens.caption.copyWith(color: scheme.error, fontWeight: FontWeight.w900))),
            const SizedBox(width: 8),
            const Text('Retry', style: TextStyle(color: AppDesignTokens.ctaTerracotta, fontWeight: FontWeight.w900)),
          ],
        ),
      ),
    );
  }
}

/// Dashed rounded outline for the empty-day card. Flutter has no dashed
/// border, and pulling in a package for one outline is not worth it.
class _DashedRoundedBorderPainter extends CustomPainter {
  const _DashedRoundedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  static const double _dash = 6;
  static const double _gap = 5;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
          Offset.zero & size, Radius.circular(radius)));

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + _dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRoundedBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}

/// The day's detail — one sheet, reached by tapping a day card that has
/// meals in it.
///
/// This is where a day's second meal is added and where a meal is removed,
/// which is why neither affordance clutters the week list. Every action pops
/// this sheet first and then acts: sheets never stack in this app.
class _DayDetailSheet extends StatelessWidget {
  const _DayDetailSheet({
    required this.dayLabel,
    required this.meals,
    required this.canAddAnother,
    required this.onOpenRecipe,
    required this.onRemove,
    required this.onAddAnother,
  });

  final String dayLabel;
  final List<_PlannedMeal> meals;
  final bool canAddAnother;
  final ValueChanged<CookModeRecipePayload> onOpenRecipe;
  final ValueChanged<int> onRemove;
  final VoidCallback onAddAnother;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppDesignTokens.spaceSM, AppDesignTokens.spaceXS, AppDesignTokens.spaceSM, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(dayLabel, style: AppDesignTokens.headline)),
              // Sheet rule: drag-down, barrier tap, AND an explicit X.
              IconButton(
                onPressed: () => context.pop(),
                tooltip: 'Close',
                icon: Icon(Icons.close_rounded, color: AppDesignTokens.textCharcoal.withValues(alpha: 0.75)),
                style: const ButtonStyle(overlayColor: WidgetStatePropertyAll(Colors.transparent)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < meals.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _DayDetailMealRow(
              meal: meals[i],
              onOpen: () {
                final recipe = meals[i].recipe;
                if (recipe != null) onOpenRecipe(recipe);
              },
              onRemove: () => onRemove(i),
            ),
          ],
          if (canAddAnother) ...[
            const SizedBox(height: 12),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onAddAnother,
                borderRadius: BorderRadius.circular(AppDesignTokens.radiusChip),
                splashFactory: NoSplash.splashFactory,
                splashColor: Colors.transparent,
                highlightColor: Colors.transparent,
                hoverColor: Colors.transparent,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.add_rounded, color: AppDesignTokens.ctaTerracotta),
                      const SizedBox(width: 10),
                      Text(
                        // SIGNED-CONTENT PLACEHOLDER
                        'Add another meal',
                        style: AppDesignTokens.body.copyWith(
                            color: AppDesignTokens.ctaTerracotta, fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DayDetailMealRow extends StatelessWidget {
  const _DayDetailMealRow({required this.meal, required this.onOpen, required this.onRemove});

  final _PlannedMeal meal;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final isFridgeRescue = meal.recipe?.origin?.isRescueEligible ?? false;

    return Container(
      decoration: BoxDecoration(
        color: AppDesignTokens.surfaceCream,
        borderRadius: BorderRadius.circular(AppDesignTokens.radiusChip),
        border: Border.all(color: AppDesignTokens.textCharcoal.withValues(alpha: 0.10)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onOpen,
                splashFactory: NoSplash.splashFactory,
                splashColor: Colors.transparent,
                highlightColor: Colors.transparent,
                hoverColor: Colors.transparent,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          meal.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppDesignTokens.subheadline,
                        ),
                      ),
                      if (isFridgeRescue) ...[
                        const SizedBox(width: 8),
                        const ProvenanceLeafBadge(compact: true),
                      ],
                      if (meal.source == kFromSavedMealSource) ...[
                        const SizedBox(width: 8),
                        const FromSavedChip(),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Sibling of the InkWell above, never nested inside it: an
          // IconButton inside an ancestor InkWell loses the gesture arena and
          // its onPressed silently never fires (fixed once already, in the
          // slot cards this screen replaced — do not re-nest it).
          IconButton(
            onPressed: onRemove,
            tooltip: 'Remove meal',
            icon: Icon(Icons.close_rounded, color: AppDesignTokens.textCharcoal.withValues(alpha: 0.75)),
            style: const ButtonStyle(overlayColor: WidgetStatePropertyAll(Colors.transparent)),
          ),
        ],
      ),
    );
  }
}

/// The add-meal sheet. Two panes, one sheet.
///
/// Pane 1 lists the three sources. Pane 2 is the My recipes picker, reached
/// by swapping the body in place — the sheet itself never closes and a second
/// sheet is never pushed on top, because sheets do not stack anywhere in this
/// app. The back arrow in pane 2 returns to pane 1.
///
/// Fridge Clearer and Custom recipe keep their existing behaviour exactly:
/// both close this sheet first and then run the flow the planner already had
/// (the depth-2 fridge picker that pops a payload back, and the custom
/// creator sheet). Only the My recipes source resolves inside this sheet, by
/// popping the chosen payload.
class _AddMealSheet extends StatefulWidget {
  const _AddMealSheet({
    required this.dayLabel,
    required this.onClearFridge,
    required this.onCustomCraving,
    this.savedRecipesService,
  });

  final String dayLabel;
  final VoidCallback onClearFridge;
  final VoidCallback onCustomCraving;
  final SavedRecipesService? savedRecipesService;

  @override
  State<_AddMealSheet> createState() => _AddMealSheetState();
}

class _AddMealSheetState extends State<_AddMealSheet> {
  bool _showingSavedPane = false;

  SavedRecipesService get _service =>
      widget.savedRecipesService ?? SavedRecipesService.instance;

  /// Held here, not created in `build`: watchSavedRecipes() returns a NEW
  /// stream per call, so subscribing from `build` would resubscribe on every
  /// emission and spin forever.
  late final Stream<List<SavedRecipe>> _savedStream =
      _service.watchSavedRecipes();

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: _showingSavedPane
          ? _SavedRecipesPickerPane(
              savedStream: _savedStream,
              onBack: () => setState(() => _showingSavedPane = false),
              onPick: (recipe) => context.pop(recipe),
            )
          : _AddMealSourcesPane(
              dayLabel: widget.dayLabel,
              onClearFridge: widget.onClearFridge,
              onCustomCraving: widget.onCustomCraving,
              onMyRecipes: () => setState(() => _showingSavedPane = true),
            ),
    );
  }
}

/// Pane 1 — the three sources.
class _AddMealSourcesPane extends StatelessWidget {
  const _AddMealSourcesPane({
    required this.dayLabel,
    required this.onClearFridge,
    required this.onCustomCraving,
    required this.onMyRecipes,
  });

  final String dayLabel;
  final VoidCallback onClearFridge;
  final VoidCallback onCustomCraving;
  final VoidCallback onMyRecipes;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppDesignTokens.spaceSM, AppDesignTokens.spaceXS, AppDesignTokens.spaceSM, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Add meal for $dayLabel', style: AppDesignTokens.headline)),
              // Sheet rule: drag-down, barrier tap, AND an explicit X.
              IconButton(
                onPressed: () => context.pop(),
                tooltip: 'Close',
                icon: Icon(Icons.close_rounded, color: AppDesignTokens.textCharcoal.withValues(alpha: 0.75)),
                style: const ButtonStyle(overlayColor: WidgetStatePropertyAll(Colors.transparent)),
              ),
            ],
          ),
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
            icon: Icons.bookmark_rounded,
            // SIGNED-CONTENT PLACEHOLDER (title + subtitle)
            title: 'My recipes',
            subtitle: 'Pick something you already saved.',
            accent: AppDesignTokens.ctaTerracotta,
            onTap: onMyRecipes,
          ),
        ],
      ),
    );
  }
}

/// Pane 2 — the My recipes picker, in the same sheet.
///
/// Rows come straight from the service in recency order (`last_touched_at`
/// desc); never re-sorted here. Tap to place — no drag.
class _SavedRecipesPickerPane extends StatelessWidget {
  const _SavedRecipesPickerPane({required this.savedStream, required this.onBack, required this.onPick});

  /// Owned by [_AddMealSheetState] — see the note there on why this is not
  /// created here.
  final Stream<List<SavedRecipe>> savedStream;
  final VoidCallback onBack;
  final ValueChanged<CookModeRecipePayload> onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppDesignTokens.spaceSM, AppDesignTokens.spaceXS, AppDesignTokens.spaceSM, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: onBack,
                tooltip: 'Back',
                icon: const Icon(Icons.arrow_back, color: AppDesignTokens.textCharcoal),
                style: const ButtonStyle(overlayColor: WidgetStatePropertyAll(Colors.transparent)),
              ),
              // SIGNED-CONTENT PLACEHOLDER
              const Expanded(child: Text('My recipes', style: AppDesignTokens.headline)),
              IconButton(
                onPressed: () => context.pop(),
                tooltip: 'Close',
                icon: Icon(Icons.close_rounded, color: AppDesignTokens.textCharcoal.withValues(alpha: 0.75)),
                style: const ButtonStyle(overlayColor: WidgetStatePropertyAll(Colors.transparent)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          StreamBuilder<List<SavedRecipe>>(
            stream: savedStream,
            builder: (context, snapshot) {
              final saved = snapshot.data ?? const <SavedRecipe>[];
              if (saved.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(4, 12, 4, 16),
                  child: Text(
                    // SIGNED-CONTENT PLACEHOLDER
                    'Nothing saved yet — bookmark a recipe and it will show up here.',
                    style: AppDesignTokens.body.copyWith(color: AppDesignTokens.textCharcoal.withValues(alpha: 0.72), height: 1.4),
                  ),
                );
              }
              return ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: saved.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final item = saved[i];
                    return Material(
                      color: AppDesignTokens.surfaceCream,
                      borderRadius: BorderRadius.circular(AppDesignTokens.radiusChip),
                      child: InkWell(
                        onTap: () => onPick(item.recipe),
                        borderRadius: BorderRadius.circular(AppDesignTokens.radiusChip),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  item.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: AppDesignTokens.deepForest),
                                ),
                              ),
                              if (item.isFridgeRescue) ...[
                                const SizedBox(width: 8),
                                const ProvenanceLeafBadge(compact: true),
                              ],
                              const SizedBox(width: 8),
                              Icon(Icons.chevron_right_rounded, color: AppDesignTokens.textCharcoal.withValues(alpha: 0.55)),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              );
            },
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

class _PlannedMeal {
  const _PlannedMeal({
    required this.title,
    required this.source,
    required this.recipe,
    this.cooked = false,
  });

  final String title;

  /// How the meal got into this day (Fridge Clearer / Custom AI Craving /
  /// [kFromSavedMealSource]). A routing marker only — NOT provenance. Whether
  /// cooking it counts as a rescue is decided by [recipe]'s own
  /// `RecipeOrigin`, never by this string.
  final String source;

  /// Full Cook Mode payload so the user can cook this planned meal, with
  /// `origin` and `originEnteredIngredients` intact.
  final CookModeRecipePayload? recipe;

  /// Mirrors the persisted `user_meal_plans.is_cooked` column.
  ///
  /// Written by `PlannerCookAttributionService` when a cook that was launched
  /// from a planner row finishes (CLAUDE.md roadmap item 27, closed
  /// 2026-08-22). The cook carries the row's identity out with it as a
  /// [PlannerSlotRef] — the old writer, this screen awaiting `push<bool>` from
  /// Cook Mode, could not work, because the post-cook `context.go('/')`
  /// completes that future with null. Nothing here is inferred from the cook
  /// log: it stores `{recipe, cookedAt}` deduplicated by title, which is
  /// ambiguous the moment the same dish is planned on two days.
  ///
  /// Whether a cooked meal reads as counted or not-counted is NOT stored — it
  /// stays derived from the recipe's own `RecipeOrigin`. See
  /// [plannerMealStateFor].
  final bool cooked;

  _PlannedMeal copyWith({String? title, String? source, CookModeRecipePayload? recipe, bool? cooked}) => _PlannedMeal(
    title: title ?? this.title,
    source: source ?? this.source,
    recipe: recipe ?? this.recipe,
    cooked: cooked ?? this.cooked,
  );
}
