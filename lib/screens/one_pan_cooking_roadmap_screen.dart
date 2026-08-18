import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:optimeal/data/diagram_keys.dart';
import 'package:optimeal/data/sensory_cue_vocabulary.dart';
import 'package:optimeal/models/recipe_model.dart';
import 'package:optimeal/nav.dart';
import 'package:optimeal/services/chef_service.dart';
import 'package:optimeal/services/confidence_climb_service.dart';
import 'package:optimeal/services/entitlement_service.dart';
import 'package:optimeal/services/fridge_nudge_service.dart';
import 'package:optimeal/services/fridge_clearer_entry_service.dart';
import 'package:optimeal/services/ledger_service.dart';
import 'package:optimeal/services/ledger_verdict.dart';
import 'package:optimeal/state/ingredient_prep_controller.dart';
import 'package:optimeal/state/user_profile_controller.dart';
import 'package:optimeal/theme.dart';
import 'package:optimeal/theme/app_design_tokens.dart';
import 'package:optimeal/widgets/app_bottom_sheet.dart';
import 'package:optimeal/widgets/confidence_tier_up_sheet.dart';
import 'package:optimeal/widgets/curriculum_drawer_content.dart';
import 'package:optimeal/widgets/diagram_sheet.dart';
import 'package:optimeal/widgets/post_cook_share_card.dart';
import 'package:optimeal/widgets/upgrade_prompt_sheet.dart';
import 'package:optimeal/widgets/waste_ledger_celebration_sheet.dart';
import 'package:optimeal/widgets/what_you_learned_sheet.dart';
import 'package:optimeal/models/technique_lesson.dart' as models;
import 'package:optimeal/widgets/culinary_matrix_card.dart' as matrix_widgets;
import 'package:optimeal/services/cook_session_storage_service.dart';

// Kept for backwards compatibility with existing (currently unused) roadmap UI
// primitives below. These can be safely deleted later once the old UI is fully
// removed.
enum RoadmapTechnique { bakeTrayRoast, sautePanFry, stirFry }

/// The surface a Cook Mode launch originated from. Drives whether a
/// completed cook is eligible to log to the Waste Ledger — see
/// [isRescueEligible] — and, for eligible surfaces, what
/// `waste_ledger_events.source` value to record. See CLAUDE.md Roadmap
/// item 28.
///
/// `fridgeCountdown` was removed as a member (housekeeping session,
/// follow-up to commit 8f23fcc) — `FridgeCountdownSheet`, the only code
/// that could ever construct it, was deleted; nothing else in the app
/// ever constructs it, and the one place that deserializes a stored
/// surface name (`CookSessionStorageService.loadActiveSession`, via
/// `CookModeSurface.values.byName`) already falls back to null on any
/// unrecognized name, which is exactly how a historical
/// `source='fridge_countdown'` waste_ledger_events row (never read back
/// into the app anyway) or a long-expired active-session record would be
/// handled. The `fridge_items` table and its DB CHECK constraint covering
/// that historical value were left untouched — database changes are a
/// separate, later decision.
enum CookModeSurface {
  fridgeClearer,
  customAiRecipeCreator,
  weeklyPlanner;

  /// Whether a genuine (non-re-cook) completion from this surface counts as
  /// a real ingredient rescue. Only Fridge Clearer generates a recipe
  /// directly from what's actually in the user's fridge — Custom AI
  /// Recipe Creator and Weekly Planner don't, by design decision.
  bool get isRescueEligible => this == CookModeSurface.fridgeClearer;

  /// The `waste_ledger_events.source` value for this surface. Null for
  /// non-rescue-eligible surfaces — `logCompletion` is never called for
  /// those, so no value is ever needed or written.
  String? get ledgerSourceValue => switch (this) {
        CookModeSurface.fridgeClearer => 'fridge_clearer',
        CookModeSurface.customAiRecipeCreator ||
        CookModeSurface.weeklyPlanner =>
          null,
      };
}

/// Envelope for a fresh (non-resume) Cook Mode launch, passed as go_router's
/// `extra`. Carries the recipe plus enough context for the Waste Ledger
/// gating logic in `_logCookSessionCompletion` to apply correctly: which
/// surface originated this cook ([surface]), and whether this is a re-cook
/// of an already-cooked recipe via Home's Recently Cooked rather than a
/// fresh generation ([isReCook]) — a re-cook never logs, regardless of
/// surface. [surface] is null for the Recently Cooked re-entry path, where
/// original provenance isn't tracked and doesn't matter: [isReCook] alone
/// already excludes it from logging.
class CookModeLaunchRequest {
  const CookModeLaunchRequest({
    required this.recipe,
    required this.surface,
    this.isReCook = false,
  });

  final CookModeRecipePayload recipe;
  final CookModeSurface? surface;
  final bool isReCook;
}

/// Payload for launching Cook Mode with a dynamic, generated recipe.
///
/// Passed through `go_router` wrapped in a [CookModeLaunchRequest] via
/// `context.push(AppRoutes.onePanCookingRoadmap, extra: CookModeLaunchRequest(...))`.
class CookModeRecipePayload {
  const CookModeRecipePayload({
    required this.title,
    required this.ingredients,
    required this.steps,
    this.kitchenGear,
    this.description,
    this.structuredIngredients,
    this.basePortions,
    this.curriculumLessonIds,
  });

  final String title;
  final List<String> ingredients;
  final List<CookModeStepPayload> steps;
  final List<String>? kitchenGear;
  final String? description;

  /// New, optional structured ingredient data (name/amount/unit). Null for
  /// older or demo recipes. [ingredients] (the display string list) is always
  /// populated regardless, so all existing screens/logic keep working
  /// unchanged. This will be used for live portion scaling in a later step.
  final List<RecipeIngredient>? structuredIngredients;

  /// The portion count [ingredients]/[structuredIngredients] were generated
  /// for (e.g. what the user picked in Fridge Clearer, or their profile
  /// default). Null for older recipes that predate this field — Cook Mode
  /// falls back to a neutral default in that case.
  final int? basePortions;

  /// Optional curriculum lesson IDs associated with this recipe.
  ///
  /// This is expected to come from AI JSON as `curriculum_lesson_ids`, but is
  /// defensively treated as optional throughout the app.
  final List<String>? curriculumLessonIds;
}

/// One step in Cook Mode.
///
/// - [heat] values should be one of: "low", "medium", "medium_high", "off_heat".
class CookModeStepPayload {
  const CookModeStepPayload(
      {required this.title,
      required this.heat,
      required this.durationMinutes,
      required this.bullets,
      this.ingredientsAdded,
      this.sensoryCue = SensoryCueVocabulary.noCueKey,
      this.techniqueDiagramId = noTechniqueDiagramKey});

  final String title;
  final String heat;
  final int durationMinutes;
  final List<String> bullets;

  /// Names of ingredients this step adds to the pan/pot — matches the
  /// `name` values in the recipe's top-level ingredients. Optional on
  /// read: recipes saved before this field existed parse with this null,
  /// same as a missing/older [RecipeIngredient.cut].
  final List<String>? ingredientsAdded;

  /// Declared key from [SensoryCueVocabulary.allKeys], or
  /// [SensoryCueVocabulary.noCueKey] when the model declared nothing valid
  /// — never null, so "does this step have a real cue" is always a plain
  /// equality check against [SensoryCueVocabulary.noCueKey]. Defaults to
  /// that same sentinel for recipes saved before this field existed.
  final String sensoryCue;

  /// Declared key from [techniqueDiagramKeys], or [noTechniqueDiagramKey]
  /// when absent or not a valid key — this field is optional on the
  /// model's side (most steps have no value here), so absence is the
  /// expected common case, not a rejection. Never null, same reasoning as
  /// [sensoryCue].
  final String techniqueDiagramId;
}

class OnePanCookingRoadmapScreen extends StatefulWidget {
  const OnePanCookingRoadmapScreen(
      {super.key,
      this.recipe,
      this.resumeSession,
      this.surface,
      this.isReCook = false});

  /// Optional dynamic recipe passed from other screens (e.g. Fridge Clearer).
  /// When null, Cook Mode falls back to the built-in demo recipe.
  /// Ignored (superseded by [resumeSession]'s own recipe) if [resumeSession]
  /// is provided.
  final CookModeRecipePayload? recipe;

  /// When provided (e.g. from a "Resume cooking?" prompt on Home), Cook Mode
  /// launches directly into this saved in-progress session instead of a
  /// fresh start — restoring the recipe, active step, completed steps,
  /// timer remaining, and portion count. The player always resumes in a
  /// paused state so the timer never starts ticking without the user
  /// explicitly tapping Resume.
  final ActiveCookSession? resumeSession;

  /// Which surface this fresh launch originated from — see
  /// [CookModeSurface]. Ignored (superseded by [resumeSession]'s own
  /// surface) if [resumeSession] is provided. Null for the demo recipe.
  /// See CLAUDE.md Roadmap item 28.
  final CookModeSurface? surface;

  /// Whether this is a re-cook of an already-cooked recipe (Home's
  /// Recently Cooked) rather than a fresh generation. Ignored (superseded
  /// by [resumeSession]'s own value) if [resumeSession] is provided.
  final bool isReCook;

  @override
  State<OnePanCookingRoadmapScreen> createState() =>
      _OnePanCookingRoadmapScreenState();
}

class _OnePanCookingRoadmapScreenState extends State<OnePanCookingRoadmapScreen>
    with WidgetsBindingObserver {
  bool _isSosOpen = false;

  /// True once the post-cook completion sequence has started (either via
  /// the last step completing, or Finish & Plate). Guards against
  /// double-firing and signals "a genuine completion happened" to callers
  /// (the back button, Weekly Planner's `completed` check) — deliberately
  /// independent of whether the Waste Ledger write itself was attempted or
  /// succeeded, since not every cook is rescue-eligible (see CLAUDE.md
  /// Roadmap item 28). Named for what it tracks now; was `_ledgerSessionLogged`
  /// before that item decoupled the sequence from the ledger result.
  bool _cookSequenceStarted = false;
  final _ledgerService = LedgerService();
  final _fridgeClearerEntryService = FridgeClearerEntryService();
  final _sessionStorage = CookSessionStorageService();
  final _confidenceClimbService = ConfidenceClimbService();

  /// The resolved recipe payload backing this screen (either the fresh
  /// [OnePanCookingRoadmapScreen.recipe] or the one inside
  /// [OnePanCookingRoadmapScreen.resumeSession]). Null only for the built-in
  /// demo recipe, which is never persisted.
  late final CookModeRecipePayload? _payload;

  /// Resolved surface/re-cook status for this session — from
  /// [OnePanCookingRoadmapScreen.resumeSession] if resuming, otherwise from
  /// the widget's own [OnePanCookingRoadmapScreen.surface]/[OnePanCookingRoadmapScreen.isReCook].
  /// Null [_surface] (demo recipe, or a pre-Roadmap-28 resumed session) is
  /// never rescue-eligible. See CLAUDE.md Roadmap item 28.
  late final CookModeSurface? _surface;
  late final bool _isReCook;

  // Cook session state (single source of truth)
  bool _cookStarted = false;
  bool _cookPaused = false;
  int? _activeStepIndex;

  bool get _recipeFinished => _cookStarted && _activeStepIndex == null;

  // Nullable for extra safety on web hot-restart/reassemble edge cases.
  // Always initialized in initState so `.contains(...)` is never called on null.
  Set<int>? _completedSteps;
  Timer? _activeTicker;
  Duration _activeRemaining = Duration.zero;

  // Resolved recipe data (either demo or dynamic payload).
  late final String _recipeTitle;
  late final Duration _estimatedCookTime;
  late final List<String> _kitchenGear;

  /// Base structured ingredients at [_basePortions], if this recipe has them.
  /// Null for the demo recipe or older recipes without structured data —
  /// in that case the portion stepper is hidden and [_ingredients] (the
  /// original plain-string list) is used as-is, unchanged from before.
  List<RecipeIngredient>? _baseStructuredIngredients;
  late int _basePortions;
  int? _currentPortions;

  /// The original plain-string ingredient list from the payload (or demo
  /// recipe). Used directly when there's no structured data; otherwise kept
  /// only as the pre-scaling fallback.
  late final List<String> _staticIngredients;

  /// The plain-string ingredient list actually shown in the checklist.
  /// For structured recipes this is recomputed live from
  /// [_baseStructuredIngredients] scaled to [_currentPortions]; otherwise
  /// it's the original static list from the payload.
  List<String> get _ingredients {
    final structured = _baseStructuredIngredients;
    if (structured == null) return _staticIngredients;
    final portions = _currentPortions ?? _basePortions;
    final factor = portions / _basePortions;
    return structured.map((ing) {
      final scaled = _roundScaledAmount(ing.amount * factor, ing.unit);
      final amountText = scaled == scaled.roundToDouble()
          ? scaled.toInt().toString()
          : scaled.toStringAsFixed(1);
      return '$amountText ${ing.unit} ${ing.name}'.trim();
    }).toList(growable: false);
  }

  /// Stable per-ingredient identity for prepped-state tracking: the
  /// ingredient's name when structured (so checking it off survives a
  /// portion change, which rewrites [_ingredients]'s scaled display
  /// strings), or the static display string itself otherwise (which never
  /// changes, since the portion stepper is hidden without structured data).
  List<String> get _ingredientKeys {
    final structured = _baseStructuredIngredients;
    if (structured == null) return _staticIngredients;
    return structured.map((ing) => ing.name).toList(growable: false);
  }

  /// Per-ingredient cut, index-aligned with [_ingredients] (both are built
  /// from the same [_baseStructuredIngredients] list, in the same order —
  /// portion scaling changes amounts, never order or count). Null for
  /// every entry when there's no structured data at all (demo recipe,
  /// older cached recipes) — same "render with no label" outcome as an
  /// individual null cut.
  List<String?> get _ingredientCuts {
    final structured = _baseStructuredIngredients;
    if (structured == null) {
      return List<String?>.filled(_ingredients.length, null);
    }
    return structured.map((ing) => ing.cut).toList(growable: false);
  }

  /// Ingredient indices the user has checked off while prepping.
  ///
  /// This is derived from the shared [IngredientPrepController] so it syncs
  /// across Cook Mode + Weekly Planner.
  Set<int> _checkedIngredientIndices(IngredientPrepController controller) {
    final out = <int>{};
    final keys = _ingredientKeys;
    for (var i = 0; i < keys.length; i++) {
      if (controller.isPrepped(keys[i])) out.add(i);
    }
    return out;
  }

  late final List<_CookStep> _steps;

  /// One key per step card, used to scroll the active step into view as
  /// cooking advances (Cook Mode previously required a manual scroll after
  /// every "Next").
  late final List<GlobalKey> _stepKeys;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _completedSteps = <int>{};

    final payload = widget.resumeSession?.recipe ?? widget.recipe;
    _payload = payload;
    if (payload == null) {
      // Demo recipe data (local-only). Later we can hydrate this from Supabase.
      _recipeTitle = 'Mushroom Risotto';
      _kitchenGear = const ['1 Skillet', 'Cutting Board', 'Wooden Spoon'];
      _staticIngredients = const [
        'Onion',
        'Mushrooms',
        'Arborio rice',
        'Stock',
        'Butter',
        'Parmesan'
      ];
      _baseStructuredIngredients = null;
      _basePortions = 1;
      const rawSteps = [
        _CookStep(
          actionTitle: 'The Caramelization Base',
          heat: _HeatLevel.mediumHigh,
          duration: Duration(minutes: 6),
          bullets: [
            'Butter + olive oil, then add onion (don\'t rush browning).',
            'Cook until translucent; edges barely golden.',
            'Add mushrooms; wait for moisture to evaporate before browning.',
          ],
        ),
        _CookStep(
          actionTitle: 'Toast the Rice (\"Glass\" Stage)',
          heat: _HeatLevel.medium,
          duration: Duration(minutes: 2),
          bullets: [
            'Stir in arborio; coat each grain in fat.',
            'Stop when the edges turn slightly translucent.',
          ],
        ),
        _CookStep(
          actionTitle: 'Deglaze + Build the Ladle Rhythm',
          heat: _HeatLevel.medium,
          duration: Duration(minutes: 18),
          bullets: [
            'Deglaze with white wine (or stock + a squeeze of lemon).',
            'Add hot stock 1 ladle at a time.',
            'Stir → absorb → repeat. Taste at ~16 min.',
          ],
        ),
        _CookStep(
          actionTitle: 'Off-Heat Emulsion (Mantecatura)',
          heat: _HeatLevel.offHeat,
          duration: Duration(minutes: 2),
          bullets: [
            'Turn heat off completely.',
            'Fold in cold butter + parmesan to emulsify to gloss.',
            'Rest 60 seconds. Loosen with 1–2 tbsp hot stock if tight.',
          ],
        ),
      ];
      _steps = [_buildPrepStep(), ...rawSteps];
    } else {
      _recipeTitle =
          payload.title.trim().isEmpty ? 'Cook Mode' : payload.title.trim();
      _staticIngredients = payload.ingredients;
      _kitchenGear =
          (payload.kitchenGear == null || payload.kitchenGear!.isEmpty)
              ? const ['1 Pan or Pot', 'Knife', 'Spoon/Spatula']
              : payload.kitchenGear!;
      _baseStructuredIngredients = payload.structuredIngredients;
      // Uses the actual portion count the recipe was generated for. Falls
      // back to 2 only for older/cached recipes that predate this field.
      _basePortions = payload.basePortions ?? 2;
      final resolvedSteps = payload.steps
          .where((s) => s.title.trim().isNotEmpty)
          .map(
            (s) => _CookStep(
              actionTitle: s.title.trim(),
              heat: _parseHeat(s.heat),
              duration: Duration(
                  minutes: s.durationMinutes <= 0 ? 4 : s.durationMinutes),
              bullets: s.bullets
                  .where((b) => b.trim().isNotEmpty)
                  .map((b) => b.trim())
                  .toList(growable: false),
              sensoryCue: s.sensoryCue,
              techniqueDiagramId: s.techniqueDiagramId,
              cutDiagramKey: _resolveCutDiagramKey(
                  s.ingredientsAdded, payload.structuredIngredients),
            ),
          )
          .toList(growable: false);
      final rawSteps = resolvedSteps.isEmpty
          ? const [
              _CookStep(
                actionTitle: 'Cook',
                heat: _HeatLevel.medium,
                duration: Duration(minutes: 10),
                bullets: ['Follow your instincts and taste as you go.'],
              ),
            ]
          : resolvedSteps;
      _steps = [_buildPrepStep(), ...rawSteps];
    }

    _estimatedCookTime =
        _steps.fold(Duration.zero, (sum, s) => sum + s.duration);

    final resume = widget.resumeSession;
    if (resume != null) {
      _cookStarted = resume.cookStarted;
      // Always resume paused — never auto-start the timer on the user's
      // behalf just because a session was saved as "in progress".
      _cookPaused = true;
      _activeStepIndex = resume.activeStepIndex;
      _completedSteps = Set<int>.from(resume.completedSteps);
      _activeRemaining = resume.activeRemaining;
      _currentPortions = resume.currentPortions;
      _surface = resume.surface;
      _isReCook = resume.isReCook;
    } else {
      _surface = widget.surface;
      _isReCook = widget.isReCook;
    }
    if (resume == null && payload != null) {
      // A genuine fresh open of Cook Mode with a real recipe (not the demo,
      // not a resume) — this is what counts toward Recently Cooked.
      unawaited(_recordRecentlyCooked(payload));
    }

    _stepKeys = List.generate(_steps.length, (_) => GlobalKey());
    // Covers resuming straight into an already-active step.
    _postFrame(_scrollToActiveStep);
  }

  /// Synthesizes a timerless "prepare ingredients" step, client-side only —
  /// no generation prompt change, never AI-generated. Prepended to every
  /// fresh, saved, and resumed session alike (built here in [initState],
  /// which resume also goes through). Testers found a timer on the very
  /// first step stressful, and rushing knife work during prep is a real cut
  /// risk — see CLAUDE.md.
  ///
  /// Each ingredient's cut now rides alongside it (device-test round F5) —
  /// the same tappable cut pill the pre-cook checklist already shows below
  /// it, so prep instructions and the checklist agree on what to actually
  /// do to each ingredient. Reads [_ingredients]/[_ingredientCuts] directly
  /// (an instance method, not static) so it automatically reflects the
  /// portion-scaled amounts, same as the checklist — both getters are
  /// built from [_baseStructuredIngredients] in the same order, so they
  /// stay index-aligned by construction.
  _CookStep _buildPrepStep() {
    final names = _ingredients;
    final cuts = _ingredientCuts;
    final entries = <({String name, String? cut})>[];
    for (var i = 0; i < names.length; i++) {
      final name = names[i].trim();
      if (name.isEmpty) continue;
      entries.add((name: name, cut: i < cuts.length ? cuts[i] : null));
    }
    if (entries.isEmpty) {
      return const _CookStep(
        actionTitle: 'Prepare Your Ingredients',
        heat: _HeatLevel.offHeat,
        duration: Duration.zero,
        hasTimer: false,
        bullets: [
          'Get your ingredients and tools ready before you start cooking.'
        ],
      );
    }
    return _CookStep(
      actionTitle: 'Prepare Your Ingredients',
      heat: _HeatLevel.offHeat,
      duration: Duration.zero,
      hasTimer: false,
      bullets: entries.map((e) => e.name).toList(growable: false),
      bulletCuts: entries.map((e) => e.cut).toList(growable: false),
    );
  }

  /// Resolves the cut-diagram pill for a step, per Package C3: the cut
  /// value of the first ingredient this step adds (matched by name,
  /// case-insensitive) against [structuredIngredients] that has a real
  /// built diagram asset (see [diagramFor]). Null if the step adds no
  /// ingredients, none match, or the matched ingredient's cut has no
  /// built asset — callers render nothing in all of those cases, no
  /// placeholder.
  static String? _resolveCutDiagramKey(
    List<String>? ingredientsAdded,
    List<RecipeIngredient>? structuredIngredients,
  ) {
    if (ingredientsAdded == null ||
        ingredientsAdded.isEmpty ||
        structuredIngredients == null ||
        structuredIngredients.isEmpty) {
      return null;
    }
    for (final addedName in ingredientsAdded) {
      final normalizedAdded = addedName.trim().toLowerCase();
      if (normalizedAdded.isEmpty) continue;
      for (final ingredient in structuredIngredients) {
        final cut = ingredient.cut;
        if (cut == null) continue;
        if (ingredient.name.trim().toLowerCase() == normalizedAdded &&
            diagramFor(cut) != null) {
          return cut;
        }
      }
    }
    return null;
  }

  static _HeatLevel _parseHeat(String raw) {
    final v =
        raw.trim().toLowerCase().replaceAll('-', '_').replaceAll(' ', '_');
    return switch (v) {
      'low' => _HeatLevel.low,
      'medium_high' || 'high' => _HeatLevel.mediumHigh,
      'off_heat' || 'off' => _HeatLevel.offHeat,
      _ => _HeatLevel.medium,
    };
  }

  /// Rounds a scaled ingredient amount to a sensible kitchen increment
  /// instead of showing raw math (e.g. "37.5 g").
  ///
  /// Deliberate choice, not a bug: exact scaling produces awkward numbers
  /// that are annoying to measure. Weight/volume rounds to the nearest 5;
  /// spoon units round to the nearest 0.5; countable items (piece/clove/
  /// slice) always round UP to a whole number, since you can't use half an
  /// egg and rounding up avoids coming up short mid-recipe.
  static double _roundScaledAmount(double amount, String unit) {
    final u = unit.trim().toLowerCase();
    if (u == 'piece' || u == 'clove' || u == 'slice') {
      return amount.ceilToDouble();
    }
    if (u == 'tbsp' || u == 'tsp') {
      return (amount * 2).round() / 2;
    }
    // Default: grams, ml, or anything else — round to nearest 5.
    return (amount / 5).round() * 5;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _activeTicker?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Save progress the moment the app leaves the foreground (backgrounded,
    // phone call, app switch) — this is the point where an OS-level kill
    // could happen without further warning, so we can't wait for a "nicer"
    // moment to persist.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      unawaited(_persistActiveSession());
    }
  }

  void _postFrame(VoidCallback fn) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      fn();
    });
  }

  /// Scrolls the active step's card into view — called after Start Cooking
  /// (both entry points) and after resuming an in-progress cook (see
  /// [initState]), so the user lands on the action instead of staying
  /// parked at the top above the header/checklist cards (device-test
  /// round F6). [retriesLeft] covers the case where this runs on the same
  /// frame the step list first becomes scrollable and the target's
  /// [GlobalKey] hasn't attached its context yet — rare, but silently
  /// doing nothing in that case is exactly the bug being fixed here, so a
  /// couple of retries one frame apart is cheap insurance.
  void _scrollToActiveStep({int retriesLeft = 3}) {
    final idx = _activeStepIndex;
    if (idx == null || idx < 0 || idx >= _stepKeys.length) return;
    final stepContext = _stepKeys[idx].currentContext;
    if (stepContext == null) {
      if (retriesLeft > 0) {
        _postFrame(() => _scrollToActiveStep(retriesLeft: retriesLeft - 1));
      }
      return;
    }
    unawaited(
      Scrollable.ensureVisible(
        stepContext,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        alignment: 0.1,
      ),
    );
  }

  /// Persists the in-progress session so it can survive the app being
  /// backgrounded, killed, or the user accidentally navigating away. A
  /// no-op for the demo recipe (nothing meaningful to resume) or before the
  /// user has actually pressed Start.
  Future<void> _persistActiveSession() async {
    final payload = _payload;
    if (payload == null || !_cookStarted || _cookSequenceStarted) return;
    try {
      await _sessionStorage.saveActiveSession(
        recipe: payload,
        cookStarted: _cookStarted,
        cookPaused: _cookPaused,
        activeStepIndex: _activeStepIndex,
        completedSteps: _completedSteps ?? <int>{},
        activeRemaining: _activeRemaining,
        currentPortions: _currentPortions,
        surface: _surface,
        isReCook: _isReCook,
      );
    } catch (e) {
      debugPrint('Failed to persist Cook Mode session: $e');
    }
  }

  Future<void> _recordRecentlyCooked(CookModeRecipePayload payload) async {
    try {
      await _sessionStorage.addRecentlyCooked(payload);
    } catch (e) {
      debugPrint('Failed to record Recently Cooked: $e');
    }
  }

  Future<void> _logCookSessionCompletion() async {
    if (_cookSequenceStarted) return;
    _cookSequenceStarted = true;
    unawaited(_sessionStorage.clearActiveSession());
    try {
      // Waste Ledger logging — gated on both conditions from CLAUDE.md
      // Roadmap item 28: the surface must be rescue-eligible (Fridge
      // Clearer only — Weekly Planner and Custom AI Recipe Creator never
      // log), AND this must not be a re-cook (Home's Recently Cooked never
      // logs, regardless of the recipe's original surface). A failed write
      // also falls through rather than aborting — the rest of this
      // sequence must never depend on a ledger result existing, only on
      // whether it was a [LedgerCompletionSuccess].
      final surface = _surface;
      final shouldLog =
          surface != null && surface.isRescueEligible && !_isReCook;
      final isGenuineFridgeClearerCompletion =
          surface == CookModeSurface.fridgeClearer && !_isReCook;

      // What the user actually entered into Fridge Clearer for this
      // recipe (device-test round F12/F13) — read once here, since both
      // the leftover-nudge check below and the Waste Ledger provenance
      // rule need exactly the same list. Empty for any surface other than
      // Fridge Clearer, or if nothing was ever recorded.
      final enteredIngredients = isGenuineFridgeClearerCompletion
          ? await _fridgeClearerEntryService.peekEnteredIngredients()
          : const <String>[];

      // Fridge nudge cancellation + leftover check (docs/decisions_2026-08-17.md
      // item 5; two-case spec is Harris's 18 Aug decision): a genuine
      // Fridge Clearer completion cancels any pending case-1/case-2 nudge,
      // then checks whether any entered ingredient never made it into this
      // recipe and schedules a case-2 leftover nudge if so. Awaited (not
      // unawaited) and in this order so the cancellation can never race
      // ahead of — and wipe out — the case-2 nudge the second call just
      // scheduled.
      if (isGenuineFridgeClearerCompletion) {
        await FridgeNudgeService.instance.onRelevantCookCompleted();
        await FridgeNudgeService.instance.onFridgeClearerCookCompleted(
          enteredIngredients: enteredIngredients,
          cookedIngredients: _ingredients,
        );
        // Consumed — enteredIngredients above already captured what's
        // needed for both the nudge check and the ledger/share-card
        // provenance rule below, so a later, unrelated completion can't
        // accidentally reuse this generation's entered list.
        unawaited(_fridgeClearerEntryService.clear());
      }

      LedgerCompletionSuccess? ledgerSuccess;
      if (shouldLog) {
        final result = await _ledgerService.logCompletion(
          source: surface.ledgerSourceValue!,
          recipeId: null,
          enteredIngredients: enteredIngredients,
          cookedIngredients: _ingredients,
        );
        if (result is LedgerCompletionSuccess) {
          ledgerSuccess = result;
          final credited = result.ingredientsRescuedList;
          final excluded = _ingredients
              .where((i) => !credited.contains(i.trim()))
              .toList(growable: false);
          debugPrint(
            'LedgerService.logCompletion success: recipe="${_payload?.title ?? ''}" '
            'credited=$credited excluded=$excluded',
          );
        } else if (result is LedgerCompletionWriteFailed) {
          debugPrint('Failed to log waste ledger completion: ${result.error}');
        }
      } else {
        debugPrint(
          'Cook Mode: not rescue-eligible, skipping Waste Ledger write — surface=$surface isReCook=$_isReCook',
        );
      }

      // Verdict selection — see docs/DECISIONS.md "Waste Ledger legibility —
      // option B". Pure, display-only classification over state already
      // computed above; does not touch LedgerService or CookModeSurface.
      final verdict = selectLedgerVerdict(
        hasPayload: _payload != null,
        isReCook: _isReCook,
        surface: surface,
        result: shouldLog
            ? (ledgerSuccess ??
                const LedgerCompletionWriteFailed(
                    payload: {}, error: 'unknown'))
            : null,
      );
      final successResult = ledgerSuccess;

      // Verdict sheet display is DEFERRED to the very end of this sequence
      // (device-test round F3) — it's now the single, definitive last
      // screen shown, with the one CTA that actually leaves Cook Mode and
      // lands on Home. Showing it here, first, meant its old "Well
      // done"/"Got it" button only popped back into a still-visible,
      // already-finished Cook Mode screen while more sheets queued up
      // behind it — the "leads nowhere" bug Harris hit on device. What You
      // Learned, Confidence Climb, the tier-up offer, the share card, and
      // the upgrade nudge all still run unconditionally for a cook that
      // didn't log (wrong surface, a re-cook, or a failed write) — see
      // CLAUDE.md Roadmap item 28 — they just now run BEFORE the verdict
      // sheet rather than after it.
      if (!mounted) return;
      final payload = _payload;
      // Populated only from the model's own declared "curriculum_lesson_id"
      // (validated against ChefService.curriculumDrawerKeys by the parser)
      // — never from keyword-matching the recipe's generated text anymore.
      // A missing or unrecognized declared key means this list is empty,
      // and both consumers below (What You Learned, Confidence Climb) must
      // treat that as "nothing to show/count," not fall back to a guess —
      // a wrong card is worse than no card, a fictional rep is worse than
      // a missing one.
      final ids = payload?.curriculumLessonIds ?? const <String>[];

      final currentConfidence =
          context.read<UserProfileController>().profile.kitchenConfidence;
      // ConfidenceClimbService.evaluate already returns an empty evaluation
      // (no celebration line, no tier-up target) when ids is empty — see
      // its own isEmpty guard — so no change needed there, only here.
      final confidenceEvaluation = await _confidenceClimbService.evaluate(
        justCookedTechniqueIds: ids,
        currentConfidence: currentConfidence,
      );

      // Techniques already marked comfortable (docs/decisions_2026-08-17.md
      // item 7 / CLAUDE.md Package E) never surface in What You Learned
      // again, even to ask the confidence question a second time.
      final visibleIds = ids
          .where((id) =>
              !confidenceEvaluation.comfortableTechniqueIds.contains(id))
          .toList(growable: false);
      if (visibleIds.isNotEmpty) {
        if (!mounted) return;
        await AppBottomSheet.show<void>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          backgroundColor: AppDesignTokens.surfaceCream,
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          builder: (ctx) => SafeArea(
            child: WhatYouLearnedSheet(
                curriculumLessonIds: visibleIds,
                confidenceLine: confidenceEvaluation.celebrationLine,
                repeatTechniqueIds: confidenceEvaluation.repeatTechniqueIds),
          ),
        );
      }

      // Confidence Climb tier-up offer — one-time per tier transition (see
      // ConfidenceClimbService), shown as its own step so it never crowds
      // the What You Learned sheet itself.
      final tierUpTarget = confidenceEvaluation.tierUpTarget;
      if (tierUpTarget != null && mounted) {
        final accepted =
            await ConfidenceTierUpSheet.show(context, targetTier: tierUpTarget);
        unawaited(_confidenceClimbService.markPrompted(currentConfidence));
        if (accepted == true && mounted) {
          final profileController = context.read<UserProfileController>();
          await profileController.updateProfile(profileController.profile
              .copyWith(kitchenConfidence: tierUpTarget));
        }
      }

      // Post-cook shareable recap card (CLAUDE.md roadmap item 7) — a
      // growth/acquisition feature, shown right after the two celebration
      // sheets close. Uses the same provenance rule logCompletion applies
      // internally (LedgerService.computeRescuedIngredients) — rather than
      // the ledger result — so it renders identically whether or not this
      // cook actually logged (CLAUDE.md Roadmap item 28). enteredIngredients
      // is empty for any non-Fridge-Clearer surface, so this now correctly
      // shows nothing for a cook with no real "entered ingredient"
      // provenance at all, rather than crediting the recipe's own choices.
      if (!mounted) return;
      final techniqueTitles =
          resolveDrawerEntries(ids).map((e) => e.title).toList(growable: false);
      await AppBottomSheet.show<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        backgroundColor: AppDesignTokens.surfaceCream,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (ctx) => SafeArea(
          child: PostCookShareCardSheet(
            ingredientsRescued: LedgerService.computeRescuedIngredients(
              enteredIngredients: enteredIngredients,
              cookedIngredients: _ingredients,
            ),
            techniqueTitles: techniqueTitles,
          ),
        ),
      );

      // Post-cook upgrade nudge — one of the three sanctioned upgrade
      // moments (see CLAUDE.md "Monetization / paywall tier structure").
      // Shown after both celebration sheets close, never inserted into
      // them, so Cook Mode + Waste Ledger stay untouched by monetization.
      if (!mounted) return;
      final isPro = await EntitlementService.instance.isPro();
      if (mounted && !isPro) {
        await UpgradePromptSheet.show(
          context,
          title: 'Nice cooking!',
          message:
              'Upgrade to Pro for unlimited AI recipes, Custom AI Recipe Creator, and more — right when you\'re on a roll.',
        );
      }

      // Verdict sheet — the definitive last screen (device-test round F3).
      // Shown only now, after every other post-cook sheet has already run,
      // so its one CTA can be a real, working exit: leave Cook Mode and
      // land on Home, where the ledger totals are actually visible. A demo
      // recipe (verdict == .demo) shows no verdict sheet at all, matching
      // the prior behavior — context.go still runs directly for that case,
      // via the shared _goHome helper below.
      if (!mounted) return;
      if (verdict == LedgerVerdict.counted && successResult != null) {
        await AppBottomSheet.show<void>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          backgroundColor: AppDesignTokens.surfaceCream,
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          builder: (ctx) => SafeArea(
            child: WasteLedgerCelebrationSheet(
              ingredientsRescued: successResult.ingredientsRescuedList,
              lifetimeIngredientsRescued:
                  successResult.lifetimeIngredientsRescued ?? 0,
            ),
          ),
        );
      } else {
        final line = ledgerVerdictCopy[verdict];
        // No entry for LedgerVerdict.demo (and none needed for .counted,
        // handled above) — demo shows no verdict at all, see
        // lib/services/ledger_verdict.dart.
        if (line != null) {
          await AppBottomSheet.show<void>(
            context: context,
            isScrollControlled: true,
            showDragHandle: true,
            backgroundColor: AppDesignTokens.surfaceCream,
            shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
            builder: (ctx) => SafeArea(child: _LedgerVerdictSheet(line: line)),
          );
        }
      }

      // Both verdict sheet variants above already navigate home themselves
      // when their CTA is tapped (see WasteLedgerCelebrationSheet /
      // _LedgerVerdictSheet). This covers only the case where no sheet was
      // shown at all — a demo recipe — which otherwise has no other way
      // home. context.go (not push) matches the pattern used by every
      // other explicit "back to Home" action in this app, and works
      // regardless of which screen launched Cook Mode.
      if (verdict == LedgerVerdict.demo) {
        if (!mounted) return;
        context.go(AppRoutes.home);
      }
    } catch (e) {
      debugPrint('Failed to log waste ledger completion: $e');
      // Fail silently to the user — do not block their cook flow on a ledger error.
    }
  }

  /// Shared entry point for Finish & Plate, whether pressed mid-cook (the
  /// skip-ahead control on [_CookPlayerBar]) or at the finished state (the
  /// existing button on [_CookModeBottomBar], not-yet-started branch only —
  /// see CLAUDE.md Roadmap item 28). Confirms first (a permanent ledger
  /// write, subject to the same logging rules as the last-step tick — an
  /// accidental tap would otherwise end the session early), then stops any
  /// running timer and runs the exact same completion sequence
  /// [_advanceToNextStep]'s last-step branch runs.
  Future<void> _confirmAndFinish() async {
    final confirmed = await AppBottomSheet.show<bool>(
      context: context,
      isScrollControlled: false,
      showDragHandle: true,
      backgroundColor: AppDesignTokens.surfaceCream,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => const SafeArea(child: _FinishAndPlateConfirmSheet()),
    );
    if (confirmed != true) return;
    if (!mounted) return;

    _activeTicker?.cancel();
    setState(() {
      _activeStepIndex = null;
      _cookPaused = true;
      _activeRemaining = Duration.zero;
    });
    _postFrame(_logCookSessionCompletion);
  }

  void _startCooking() {
    if (!mounted) return;
    if (_cookStarted && _activeStepIndex != null) return;

    setState(() {
      _cookStarted = true;
      _cookPaused = false;
      _activeStepIndex = 0;
      _activeRemaining = _steps.first.duration;
    });
    _resumeTimer();
    _postFrame(_scrollToActiveStep);
  }

  void _resumeTimer() {
    if (!mounted) return;
    if (_activeStepIndex == null) return;
    if (_completedSteps?.contains(_activeStepIndex!) ?? false) return;

    _activeTicker?.cancel();

    // Timerless step (currently only the synthesized prep step, see
    // _buildPrepStep) — mark active/unpaused so the UI reads correctly, but
    // never start a countdown. The only way forward is the manual
    // mark-complete action, which already calls _advanceToNextStep()
    // directly regardless of whether a timer was ever running.
    if (!_steps[_activeStepIndex!].hasTimer) {
      _activeRemaining = Duration.zero;
      if (mounted) setState(() => _cookPaused = false);
      unawaited(_persistActiveSession());
      return;
    }

    if (_activeRemaining <= Duration.zero) {
      _activeRemaining = _steps[_activeStepIndex!].duration;
    }

    if (mounted) setState(() => _cookPaused = false);
    unawaited(_persistActiveSession());
    _activeTicker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_activeStepIndex == null) {
        t.cancel();
        return;
      }

      if (_activeRemaining <= const Duration(seconds: 1)) {
        t.cancel();
        _activeRemaining = Duration.zero;
        if (!mounted) return;
        _onActiveTimerDone();
      } else {
        if (!mounted) return;
        setState(() => _activeRemaining -= const Duration(seconds: 1));
      }
    });
  }

  void _pauseTimer() {
    if (!mounted) return;
    _activeTicker?.cancel();
    if (mounted) setState(() => _cookPaused = true);
    unawaited(_persistActiveSession());
  }

  void _togglePause() {
    if (!_cookStarted) {
      _startCooking();
      return;
    }
    if (_cookPaused) {
      _resumeTimer();
    } else {
      _pauseTimer();
    }
  }

  void _onActiveTimerDone() {
    if (!mounted) return;
    final idx = _activeStepIndex;
    if (idx == null) return;

    try {
      SystemSound.play(SystemSoundType.click);
      HapticFeedback.lightImpact();
    } catch (e) {
      debugPrint('Timer completion feedback failed: $e');
    }

    setState(() {
      (_completedSteps ??= <int>{}).add(idx);
    });

    final theme = Theme.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Step ${idx + 1} complete. Moving on…',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onInverseSurface),
        ),
        backgroundColor: theme.colorScheme.inverseSurface,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );

    _advanceToNextStep();
  }

  void _advanceToNextStep() {
    if (!mounted) return;
    final idx = _activeStepIndex;
    if (idx == null) return;

    _activeTicker?.cancel();

    final next = idx + 1;
    if (next >= _steps.length) {
      setState(() {
        _activeStepIndex = null;
        _cookPaused = true;
        _activeRemaining = Duration.zero;
      });
      _postFrame(_logCookSessionCompletion);
      return;
    }

    setState(() {
      _activeStepIndex = next;
      _activeRemaining = _steps[next].duration;
      _cookPaused = false;
    });
    _resumeTimer();
    _postFrame(_scrollToActiveStep);
  }

  void _changePortions(int delta) {
    if (!mounted) return;
    final current = _currentPortions ?? _basePortions;
    final next = (current + delta).clamp(1, 12);
    if (next == current) return;
    setState(() => _currentPortions = next);
    unawaited(_persistActiveSession());
  }

  void _toggleStepComplete(int stepIndex) {
    if (!mounted) return;
    final isDone = _completedSteps?.contains(stepIndex) ?? false;
    setState(() {
      final steps = _completedSteps ??= <int>{};
      if (isDone) {
        steps.remove(stepIndex);
      } else {
        steps.add(stepIndex);
      }
    });

    // Manual override: if user marks the active step complete, auto-advance.
    if (!isDone && _activeStepIndex == stepIndex) {
      _advanceToNextStep();
    } else {
      unawaited(_persistActiveSession());
    }
  }

  Duration _remainingForStep(int stepIndex) {
    if (_activeStepIndex == stepIndex) return _activeRemaining;
    return _steps[stepIndex].duration;
  }

  Future<void> _openSos() async {
    // Prevent rapid multi-taps from stacking multiple modal sheets.
    if (_isSosOpen) return;
    if (!mounted) return;
    setState(() => _isSosOpen = true);

    final quickPrompts = _buildQuickPrompts();
    final recipeContext = _buildSosRecipeContext();

    try {
      // If the widget unmounts between tap + async scheduling, do not present.
      if (!mounted) return;

      await AppBottomSheet.show<void>(
        context: context,
        isScrollControlled: true,
        useRootNavigator: true,
        showDragHandle: true,
        backgroundColor: AppDesignTokens.surfaceCream,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (sheetContext) => _ChefSosSheet(
          recipeTitle: _recipeTitle,
          quickPrompts: quickPrompts,
          recipeContext: recipeContext,
        ),
      );
    } catch (e) {
      debugPrint('Failed to open Live SOS sheet: $e');
    } finally {
      _postFrame(() {
        if (!mounted) return;
        setState(() => _isSosOpen = false);
      });
    }
  }

  /// Builds the "actual recipe" context block sent to Chef Harris SOS —
  /// the current (portion-scaled) ingredient list, every step's title,
  /// heat, duration, and bullets, and a marker on whichever step the user
  /// is currently on. Previously SOS only received the recipe title, so
  /// Chef Harris had no way to ground an answer in what the recipe
  /// actually says (e.g. it once advised dicing and pre-cooking potatoes
  /// for a recipe that said thinly slice — a real, observed failure).
  String _buildSosRecipeContext() {
    final b = StringBuffer();
    b.writeln('Ingredients:');
    for (final ing in _ingredients) {
      b.writeln('- $ing');
    }
    b.writeln();
    b.writeln('Steps:');
    for (var i = 0; i < _steps.length; i++) {
      final s = _steps[i];
      final marker = _activeStepIndex == i ? ' ← USER IS ON THIS STEP NOW' : '';
      b.writeln(
          '${i + 1}. ${s.actionTitle} — ${_heatLabelText(s.heat)}, ~${s.duration.inMinutes} min$marker');
      for (final bullet in s.bullets) {
        b.writeln('   - $bullet');
      }
    }
    return b.toString().trimRight();
  }

  static String _heatLabelText(_HeatLevel heat) => switch (heat) {
        _HeatLevel.low => 'low heat',
        _HeatLevel.medium => 'medium heat',
        _HeatLevel.mediumHigh => 'medium-high heat',
        _HeatLevel.offHeat => 'off heat',
      };

  /// Builds SOS quick-prompt chips tailored to the current recipe, based on
  /// keyword matches against the recipe title + step titles/bullets. Falls
  /// back to a generic, dish-agnostic set if nothing matches.
  List<String> _buildQuickPrompts() {
    final searchText = ([
      _recipeTitle,
      for (final s in _steps) ...[s.actionTitle, ...s.bullets],
    ].join(' '))
        .toLowerCase();

    bool hasAny(List<String> keywords) => keywords.any(searchText.contains);

    // Ordered most-specific-first; first category match wins.
    final categories = <(List<String> keywords, List<String> prompts)>[
      (
        ['risotto', 'arborio', 'rice'],
        [
          '🍚 Rice too thick / tight',
          '💧 Rice too watery',
          '🧂 Too salty / too bland',
          '🔥 Not browning / no colour',
        ],
      ),
      (
        ['stir-fry', 'stir fry', 'wok'],
        [
          '🔥 Pan not hot enough',
          '🥦 Veg gone soft / soggy',
          '🧂 Sauce too thin / thick',
          '🍗 Protein tough / rubbery',
        ],
      ),
      (
        ['roast', 'tray bake', 'sheet pan', 'oven'],
        [
          '🔥 Not crisping / browning',
          '⏱️ Some items done before others',
          '🧂 Under-seasoned',
          '🍗 Protein dry / overcooked',
        ],
      ),
      (
        ['braise', 'stew', 'simmer'],
        [
          '💧 Sauce too thin / watery',
          '🍖 Meat still tough',
          '🧂 Tastes flat / needs seasoning',
          '⏱️ Not reducing / thickening',
        ],
      ),
      (
        ['pasta', 'noodle'],
        [
          '🍝 Pasta overcooked / mushy',
          '💧 Sauce too thin / watery',
          '🧂 Tastes bland',
          '🧀 Sauce clumping / not smooth',
        ],
      ),
      (
        ['egg', 'omelette', 'omelet'],
        [
          '🍳 Overcooked / rubbery',
          '🔥 Sticking to the pan',
          '🧂 Tastes bland',
          '⏱️ Too runny / not set',
        ],
      ),
      (
        ['dough', 'bread', 'knead', 'proof'],
        [
          '🍞 Dough not rising',
          '💧 Too sticky / wet',
          '🔥 Not browning on top',
          '⏱️ Dense / gummy inside',
        ],
      ),
      (
        ['sear', 'grill', 'steak'],
        [
          '🔥 Not getting a crust',
          '⏱️ Over / undercooked inside',
          '🧂 Tastes bland',
          '🧈 Pan sauce broke / split',
        ],
      ),
      (
        ['sauté', 'saute', 'pan fry', 'pan-fry', 'pan sear'],
        [
          '🍳 Sticking to the pan',
          '🔥 Not browning / searing',
          '🧈 Sauce broke / separated',
          '🧂 Too salty / too bland',
        ],
      ),
    ];

    for (final (keywords, prompts) in categories) {
      if (hasAny(keywords)) return prompts;
    }

    // Generic fallback for anything unmatched.
    return const [
      '🧂 Too salty / too bland',
      '🔥 Not browning / cooking through',
      '⏱️ Timing feels off',
      '💧 Too thick / too thin',
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final prepController = context.watch<IngredientPrepController>();

    return Scaffold(
      backgroundColor: AppDesignTokens.backgroundSage,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => context.pop(_cookSequenceStarted),
          icon: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: theme.colorScheme.outline.withValues(alpha: 0.18)),
            ),
            child: Icon(Icons.arrow_back, color: theme.colorScheme.onSurface),
          ),
          tooltip: 'Back to Plan',
        ),
        title: Text('Cook Mode',
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w800)),
        centerTitle: false,
      ),
      bottomNavigationBar: !_cookStarted
          ? _StartCookingBottomBar(
              onSosPressed: () => _postFrame(_openSos),
              // Called directly (device-test round F6) — _startCooking
              // already schedules its own post-frame scroll-to-active-step
              // once its setState has taken effect; wrapping the whole call
              // in a second _postFrame only added a needless extra frame of
              // delay before the scroll even got scheduled.
              onStartPressed: _startCooking)
          : (_recipeFinished
              ? _CookModeBottomBar(
                  onSosPressed: () => _postFrame(_openSos),
                  onFinishPressed: () {
                    // Once the post-cook sequence has already run (or been
                    // attempted — the guard fires before the Waste Ledger
                    // write, not after it succeeds), _logCookSessionCompletion
                    // can never run again. Most of the time that's moot,
                    // since the sequence now navigates Home on its own once
                    // it resolves — but if it was interrupted by a thrown
                    // error partway through (see CLAUDE.md Roadmap item 21),
                    // this button is the only way out, and it must actually
                    // go somewhere rather than repeat a snackbar forever.
                    // No confirmation here — nothing new fires, this is pure
                    // recovery navigation.
                    if (_cookSequenceStarted) {
                      context.go(AppRoutes.home);
                      return;
                    }
                    _postFrame(_confirmAndFinish);
                  },
                )
              : _CookPlayerBar(
                  isPaused: _cookPaused,
                  activeStepNumber:
                      _activeStepIndex == null ? null : _activeStepIndex! + 1,
                  remaining: _activeRemaining,
                  onPausePressed: () => _postFrame(_togglePause),
                  onNextPressed: () => _postFrame(() {
                    if (_activeStepIndex != null) {
                      _toggleStepComplete(_activeStepIndex!);
                    }
                  }),
                  onAskChefPressed: () => _postFrame(_openSos),
                  onFinishPressed: () => _postFrame(_confirmAndFinish),
                )),
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics()),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
              sliver: SliverList(
                delegate: SliverChildListDelegate.fixed(
                  [
                    _CookModeHeader(
                      recipeTitle: _recipeTitle,
                      estimatedCookTime: _estimatedCookTime,
                      kitchenGear: _kitchenGear,
                    ),
                    const SizedBox(height: 14),
                    _IngredientsChecklistCard(
                      ingredients: _ingredients,
                      cuts: _ingredientCuts,
                      checked: _checkedIngredientIndices(prepController),
                      onToggle: (i) =>
                          prepController.togglePrepped(_ingredientKeys[i]),
                      portions: _baseStructuredIngredients == null
                          ? null
                          : (_currentPortions ?? _basePortions),
                      onIncreasePortions: _baseStructuredIngredients == null
                          ? null
                          : () => _changePortions(1),
                      onDecreasePortions: _baseStructuredIngredients == null
                          ? null
                          : () => _changePortions(-1),
                    ),
                    const SizedBox(height: 14),
                    _StartCookingCard(
                      started: _cookStarted,
                      // Called directly (device-test round F6) — see the
                      // matching comment on _StartCookingBottomBar's
                      // onStartPressed above.
                      onStart: _startCooking,
                    ),
                    const SizedBox(height: 14),
                    for (var i = 0; i < _steps.length; i++) ...[
                      _CookStepCard(
                        key: _stepKeys[i],
                        stepNumber: i + 1,
                        step: _steps[i],
                        scienceNote: widget.recipe == null
                            ? _scienceNoteForDemoStep(i)
                            : null,
                        isActive: _activeStepIndex == i,
                        isCompleted: _completedSteps?.contains(i) ?? false,
                        remaining: _remainingForStep(i),
                        cookStarted: _cookStarted,
                        onToggleCompleted: () =>
                            _postFrame(() => _toggleStepComplete(i)),
                      ),
                      const SizedBox(height: 12),
                    ],
                    const _FlavorCheckpointCard(),
                    const SizedBox(height: 92),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  models.CulinaryMatrixCard? _scienceNoteForDemoStep(int stepIndex) {
    // Optional, inline educational notes for the built-in demo recipe only.
    // Dynamic recipes can add these later via payload/AI without changing Cook Mode logic.
    return switch (stepIndex) {
      0 => const models.CulinaryMatrixCard(
          id: 'risotto_caramelization_base',
          title: 'Evaporation → Browning (don\'t steam your mushrooms)',
          heatCue: 'Medium-high, then back off if the pan starts smoking.',
          timingNote: 'Wait for moisture to cook off before expecting color.',
          knifeCutSpec:
              'Slice mushrooms evenly so they brown at the same rate.',
          whyThisWorks:
              'Browning needs a dry surface. If water is still in the pan, you\'re boiling — not caramelizing.',
          ratioSummary: 'Crowd less: one even layer beats "more" volume.',
        ),
      1 => const models.CulinaryMatrixCard(
          id: 'risotto_toast_rice',
          title: 'Toast the rice to control starch release',
          heatCue: 'Medium heat; steady sizzle, not aggressive frying.',
          timingNote: 'Stop when edges look slightly translucent (1–2 min).',
          knifeCutSpec: null,
          whyThisWorks:
              'A quick toast coats grains in fat and slows early starch leakage—giving you creaminess without gluey texture.',
          ratioSummary: 'Fat first → rice toast → liquid rhythm.',
        ),
      2 => const models.CulinaryMatrixCard(
          id: 'risotto_ladle_rhythm',
          title: 'Ladle rhythm: absorb → stir → taste',
          heatCue: 'Medium heat; keep a gentle simmer throughout.',
          timingNote: 'Add the next ladle only when the pan goes "almost dry".',
          knifeCutSpec: null,
          whyThisWorks:
              'Starch develops through friction + controlled hydration. Too much liquid at once dilutes agitation and slows thickening.',
          ratioSummary: 'Hot stock + small additions beats big pours.',
        ),
      3 => const models.CulinaryMatrixCard(
          id: 'risotto_mantecatura',
          title: 'Off-heat emulsion (mantecatura) = gloss + lift',
          heatCue: 'Fully off heat before butter + cheese.',
          timingNote:
              'Rest 60 seconds, then adjust looseness with a splash of hot stock.',
          knifeCutSpec: null,
          whyThisWorks:
              'Off-heat emulsification prevents the fat from breaking. You get a stable, glossy sauce that clings to each grain.',
          ratioSummary: 'Cold butter + grated cheese = emulsifier + body.',
        ),
      _ => null,
    };
  }
}

enum _HeatLevel { low, medium, mediumHigh, offHeat }

class _CookStep {
  const _CookStep(
      {required this.actionTitle,
      required this.heat,
      required this.duration,
      required this.bullets,
      this.bulletCuts,
      this.sensoryCue = SensoryCueVocabulary.noCueKey,
      this.hasTimer = true,
      this.techniqueDiagramId = noTechniqueDiagramKey,
      this.cutDiagramKey});

  final String actionTitle;
  final _HeatLevel heat;
  final Duration duration;
  final List<String> bullets;

  /// Optional, index-aligned with [bullets] — the cut for that bullet's
  /// ingredient, or null where none applies. Currently only ever set for
  /// the synthesized prep step (see [_buildPrepStep]) so each ingredient's
  /// cut shows as the same tappable pill the pre-cook checklist uses,
  /// rather than amounts-only text (device-test round F5).
  final List<String?>? bulletCuts;

  final String sensoryCue;

  /// False only for the client-synthesized "prepare ingredients" step
  /// (see [_buildPrepStep]) — no AI-generated step is ever timerless.
  /// Gates both the countdown ticker ([_resumeTimer]) and the timer-related
  /// UI in [_CookStepCard]. Testers found the timer stressful on the very
  /// first step, and rushing knife work is a real cut risk.
  final bool hasTimer;

  /// The step's own declared technique diagram key (see
  /// [CookModeStepPayload.techniqueDiagramId]) — carried through unchanged,
  /// [noTechniqueDiagramKey] when none.
  final String techniqueDiagramId;

  /// Resolved ONCE at construction (see the mapping in [initState]), not
  /// re-derived per render: the cut value of the first ingredient this step
  /// adds (via [CookModeStepPayload.ingredientsAdded], matched against
  /// [CookModeRecipePayload.structuredIngredients] by name) that has a real
  /// built diagram asset (see lib/widgets/diagram_sheet.dart's
  /// `diagramFor`). Null when the step adds no ingredient with a
  /// diagrammed cut — the common case, since only 'julienne' has an asset
  /// in this pilot phase.
  final String? cutDiagramKey;
}

class _CookModeHeader extends StatelessWidget {
  const _CookModeHeader(
      {required this.recipeTitle,
      required this.estimatedCookTime,
      required this.kitchenGear});

  final String recipeTitle;
  final Duration estimatedCookTime;
  final List<String> kitchenGear;

  String _formatCookTime(Duration d) {
    final mins = d.inMinutes;
    if (mins < 60) return '~${mins} min';
    final h = mins ~/ 60;
    final m = mins % 60;
    return '~${h}h ${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          recipeTitle,
          style: theme.textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _InfoPill(
                icon: Icons.timelapse,
                label: 'Est. time',
                value: _formatCookTime(estimatedCookTime),
                accent: theme.colorScheme.tertiary),
            _InfoPill(
                icon: Icons.restaurant_menu, label: 'Mode', value: 'Cook Mode'),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Kitchen Gear Needed',
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < kitchenGear.length; i++) ...[
                _GearChip(label: kitchenGear[i]),
                if (i != kitchenGear.length - 1) const SizedBox(width: 10),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill(
      {required this.icon,
      required this.label,
      required this.value,
      this.accent});

  final IconData icon;
  final String label;
  final String value;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = accent ?? theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
                color: a.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, size: 18, color: a),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 2),
              Text(value,
                  style: theme.textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.w900)),
            ],
          ),
        ],
      ),
    );
  }
}

class _GearChip extends StatelessWidget {
  const _GearChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.kitchen_outlined,
              size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Text(label,
              style: theme.textTheme.labelLarge
                  ?.copyWith(fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class _IngredientsChecklistCard extends StatelessWidget {
  const _IngredientsChecklistCard({
    required this.ingredients,
    required this.cuts,
    required this.checked,
    required this.onToggle,
    this.portions,
    this.onIncreasePortions,
    this.onDecreasePortions,
  });

  final List<String> ingredients;

  /// Index-aligned with [ingredients]. A null entry means no cut is
  /// recorded for that ingredient (missing field, older recipe, or no
  /// structured data at all) — that row renders exactly as it did before
  /// this field existed, no label, no reserved space.
  final List<String?> cuts;
  final Set<int> checked;
  final ValueChanged<int> onToggle;

  /// When non-null (along with the two callbacks below), shows a live +/-
  /// portion stepper above the checklist. Null for recipes without
  /// structured ingredient data (demo recipe, older cached recipes).
  final int? portions;
  final VoidCallback? onIncreasePortions;
  final VoidCallback? onDecreasePortions;

  ({String name, String? note}) _splitIngredient(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return (name: raw, note: null);

    // Prefer a trailing parenthetical: "300g Potatoes (cubed)".
    final open = t.lastIndexOf('(');
    final close = t.endsWith(')') ? t.length - 1 : -1;
    if (open != -1 && close != -1 && close > open + 1) {
      final name = t.substring(0, open).trim();
      final note = t.substring(open + 1, close).trim();
      if (name.isNotEmpty && note.isNotEmpty) return (name: name, note: note);
    }

    // Common separators: em dash, hyphen, colon.
    for (final sep in const [' — ', ' - ', ': ']) {
      final i = t.indexOf(sep);
      if (i > 0 && i < t.length - sep.length) {
        final name = t.substring(0, i).trim();
        final note = t.substring(i + sep.length).trim();
        if (name.isNotEmpty && note.isNotEmpty) return (name: name, note: note);
      }
    }

    return (name: t, note: null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                      color: theme.colorScheme.tertiary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14)),
                  child: Icon(Icons.checklist_rounded,
                      color: theme.colorScheme.tertiary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Ingredients Checklist',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 2),
                      Text(
                        'Check items off as you prep.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.35),
                      ),
                    ],
                  ),
                ),
                if (ingredients.isNotEmpty)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.tertiary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                          color: theme.colorScheme.tertiary
                              .withValues(alpha: 0.18)),
                    ),
                    child: Text(
                      '${checked.length}/${ingredients.length}',
                      style: theme.textTheme.labelLarge
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  ),
              ],
            ),
            if (portions != null &&
                onIncreasePortions != null &&
                onDecreasePortions != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Text('Servings',
                      style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: theme.colorScheme.onSurfaceVariant)),
                  const Spacer(),
                  IconButton(
                    onPressed: onDecreasePortions,
                    icon: const Icon(Icons.remove_circle_outline),
                    color: theme.colorScheme.tertiary,
                    tooltip: 'Fewer servings',
                  ),
                  Text('$portions',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w900)),
                  IconButton(
                    onPressed: onIncreasePortions,
                    icon: const Icon(Icons.add_circle_outline),
                    color: theme.colorScheme.tertiary,
                    tooltip: 'More servings',
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            if (ingredients.isEmpty)
              Text('No ingredients listed for this recipe.',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant))
            else
              Column(
                children: [
                  for (var i = 0; i < ingredients.length; i++) ...[
                    _IngredientChecklistRow(
                      ingredient: ingredients[i],
                      split: _splitIngredient(ingredients[i]),
                      cut: i < cuts.length ? cuts[i] : null,
                      checked: checked.contains(i),
                      onToggle: () => onToggle(i),
                    ),
                    if (i != ingredients.length - 1) const SizedBox(height: 10),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _IngredientChecklistRow extends StatelessWidget {
  const _IngredientChecklistRow(
      {required this.ingredient,
      required this.split,
      required this.cut,
      required this.checked,
      required this.onToggle});

  final String ingredient;
  final ({String name, String? note}) split;

  /// Null renders this row exactly as it did before the cut field
  /// existed — no label, no reserved space for one. `'none'` is real,
  /// deliberate structured data (kept in the model and in storage) but is
  /// also suppressed from rendering — every ingredient in the schema now
  /// carries a cut, so pantry staples (salt, oil, stock) and whole items
  /// (eggs, cheese) all come back as `'none'`, and a row of grey "none"
  /// pills would tell the user nothing.
  final String? cut;
  final bool checked;
  final VoidCallback onToggle;

  void _showCutDefinition(BuildContext context, String cut) {
    AppBottomSheet.show<void>(
      context: context,
      backgroundColor: AppDesignTokens.surfaceCream,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(child: _CutDefinitionSheet(cut: cut)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final border = checked
        ? theme.colorScheme.tertiary.withValues(alpha: 0.28)
        : theme.colorScheme.outline.withValues(alpha: 0.14);
    final bg = checked
        ? theme.colorScheme.tertiary.withValues(alpha: 0.06)
        : theme.colorScheme.surface;
    final titleColor = checked
        ? theme.colorScheme.onSurface.withValues(alpha: 0.55)
        : theme.colorScheme.onSurface;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onToggle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: SizedBox(
                width: 24,
                height: 24,
                child: Checkbox(
                  value: checked,
                  onChanged: (_) => onToggle(),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6)),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    split.name,
                    style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: titleColor,
                        decoration:
                            checked ? TextDecoration.lineThrough : null),
                  ),
                  if (split.note != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      split.note!,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.3),
                    ),
                  ],
                  if (cut != null && cut != 'none') ...[
                    const SizedBox(height: 4),
                    InkWell(
                      onTap: () => _showCutDefinition(context, cut!),
                      borderRadius: BorderRadius.circular(999),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.tertiary
                              .withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                              color: theme.colorScheme.tertiary
                                  .withValues(alpha: 0.20)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              ingredientCutLabel(cut!),
                              style: theme.textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: theme.colorScheme.tertiary),
                            ),
                            const SizedBox(width: 3),
                            Icon(Icons.info_outline_rounded,
                                size: 12, color: theme.colorScheme.tertiary),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Reached by tapping an ingredient's cut label — shows the one-line,
/// beginner-actionable definition from [ingredientCutDefinitions]. Never
/// shown inline on every ingredient row, only on tap, per design.
class _CutDefinitionSheet extends StatelessWidget {
  const _CutDefinitionSheet({required this.cut});

  final String cut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final definition = ingredientCutDefinitions[cut] ??
        'No definition available for this cut yet.';

    return Material(
      color: AppDesignTokens.surfaceCream,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
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
                    color: AppDesignTokens.deepForest.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color:
                            AppDesignTokens.deepForest.withValues(alpha: 0.18)),
                  ),
                  child: const Icon(Icons.content_cut_rounded,
                      color: AppDesignTokens.deepForest, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    ingredientCutLabel(cut),
                    style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: AppDesignTokens.textCharcoal),
                  ),
                ),
                IconButton(
                  onPressed: () => context.pop(),
                  icon:
                      Icon(Icons.close_rounded, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              definition,
              style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppDesignTokens.textCharcoal,
                  height: 1.4,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

/// Renders a step's declared sensory cue (harrisSays, always visible) with
/// the ifNotReady/ifOvershot remedies behind a tappable reveal, in the same
/// tap-to-open-sheet style as [_IngredientChecklistRow]'s cut pill. Renders
/// nothing if the key isn't in [SensoryCueVocabulary.entries] (defensive —
/// [CookModeStepPayload.sensoryCue] should already be a valid key or
/// [SensoryCueVocabulary.noCueKey] by the time it reaches here, but this
/// widget only ever gets built when it's already confirmed not to be
/// [SensoryCueVocabulary.noCueKey]).
///
/// Deliberately display-only — no readiness gate blocking the timer from
/// starting, and no doneness auto-completion. That gating behavior is a
/// separate design decision, not built here.
class _SensoryCueCard extends StatelessWidget {
  const _SensoryCueCard({required this.cueKey});

  final String cueKey;

  String _phaseLabel(CuePhase phase) {
    switch (phase) {
      case CuePhase.readiness:
        return 'BEFORE IT GOES IN';
      case CuePhase.during:
        return 'WHILE IT COOKS';
      case CuePhase.doneness:
        // Doneness cues are the authority on "actually done" — the timer
        // is only ever an estimate of when to start checking.
        return 'HOW YOU KNOW IT\'S DONE';
    }
  }

  void _showRemedies(BuildContext context, SensoryCue cue) {
    AppBottomSheet.show<void>(
      context: context,
      backgroundColor: AppDesignTokens.surfaceCream,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(child: _SensoryCueDetailSheet(cue: cue)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cue = SensoryCueVocabulary.byKey(cueKey);
    if (cue == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final hasRemedy = cue.ifNotReady != null || cue.ifOvershot != null;

    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppDesignTokens.deepForest.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: AppDesignTokens.deepForest.withValues(alpha: 0.16)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.spa_outlined,
              size: 18, color: AppDesignTokens.deepForest),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _phaseLabel(cue.phase),
                  style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.4,
                      color: AppDesignTokens.deepForest),
                ),
                const SizedBox(height: 3),
                Text(
                  cue.harrisSays,
                  style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppDesignTokens.textCharcoal,
                      height: 1.35),
                ),
                if (hasRemedy) ...[
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () => _showRemedies(context, cue),
                    borderRadius: BorderRadius.circular(999),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Not there yet, or gone too far?',
                          style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: AppDesignTokens.ctaTerracotta),
                        ),
                        const SizedBox(width: 3),
                        const Icon(Icons.info_outline_rounded,
                            size: 12, color: AppDesignTokens.ctaTerracotta),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Display-only mapping from a raw remedy token in
/// lib/data/sensory_cue_vocabulary.dart (e.g. `more_heat`) to a plain,
/// warm phrase in Chef Harris's voice. Most `ifNotReady`/`ifOvershot`
/// values in that file are already full sentences Harris wrote by hand —
/// this only covers the handful of short internal tokens that leaked
/// through to the UI unrendered (device-test round F4). Deliberately kept
/// here, in display code, rather than in the data file itself — that
/// file's voice strings are signed and must not be edited for this.
const Map<String, String> _sensoryCueRemedyDisplay = {
  'more_heat': 'Turn the heat up a little and give it a moment.',
  'more_time': 'Give it a little more time, then check again.',
  'less_heat': 'Turn the heat down a touch.',
  'stir_and_wait': 'Give it a stir and wait a moment for it to catch up.',
};

/// Renders [raw] for display: an exact match against
/// [_sensoryCueRemedyDisplay] is replaced outright; a token embedded inside
/// an otherwise hand-written sentence (a couple of `ifOvershot` entries end
/// with one, e.g. "...going bitter - less_heat.") is replaced in place so
/// the rest of the sentence is untouched. Anything that matches nothing —
/// including the entries that are already plain phrases — passes through
/// unchanged.
String _displaySensoryCueRemedy(String raw) {
  final exact = _sensoryCueRemedyDisplay[raw.trim()];
  if (exact != null) return exact;

  var out = raw;
  for (final entry in _sensoryCueRemedyDisplay.entries) {
    out = out.replaceAll(
        RegExp(r'\b' + RegExp.escape(entry.key) + r'\b'), entry.value);
  }
  return out;
}

/// Reached by tapping a sensory cue card's remedy prompt — shows
/// [SensoryCue.ifNotReady]/[SensoryCue.ifOvershot]/[SensoryCue.action] (and
/// [SensoryCue.safetyNote] when present), never shown inline on the step
/// card itself. Mirrors [_CutDefinitionSheet]'s layout.
class _SensoryCueDetailSheet extends StatelessWidget {
  const _SensoryCueDetailSheet({required this.cue});

  final SensoryCue cue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: AppDesignTokens.surfaceCream,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
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
                    color: AppDesignTokens.deepForest.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color:
                            AppDesignTokens.deepForest.withValues(alpha: 0.18)),
                  ),
                  child: const Icon(Icons.spa_outlined,
                      color: AppDesignTokens.deepForest, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    cue.harrisSays,
                    style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: AppDesignTokens.textCharcoal),
                  ),
                ),
                IconButton(
                  onPressed: () => context.pop(),
                  icon:
                      Icon(Icons.close_rounded, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
            if (cue.ifNotReady != null) ...[
              const SizedBox(height: 14),
              Text('Not there yet',
                  style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      color:
                          AppDesignTokens.textCharcoal.withValues(alpha: 0.6))),
              const SizedBox(height: 4),
              Text(_displaySensoryCueRemedy(cue.ifNotReady!),
                  style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppDesignTokens.textCharcoal,
                      height: 1.4,
                      fontWeight: FontWeight.w600)),
            ],
            if (cue.ifOvershot != null) ...[
              const SizedBox(height: 14),
              Text('Gone too far',
                  style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      color:
                          AppDesignTokens.textCharcoal.withValues(alpha: 0.6))),
              const SizedBox(height: 4),
              Text(_displaySensoryCueRemedy(cue.ifOvershot!),
                  style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppDesignTokens.textCharcoal,
                      height: 1.4,
                      fontWeight: FontWeight.w600)),
            ],
            if (cue.action != null) ...[
              const SizedBox(height: 14),
              Text('What to do',
                  style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      color:
                          AppDesignTokens.textCharcoal.withValues(alpha: 0.6))),
              const SizedBox(height: 4),
              Text(_displaySensoryCueRemedy(cue.action!),
                  style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppDesignTokens.textCharcoal,
                      height: 1.4,
                      fontWeight: FontWeight.w600)),
            ],
            if (cue.safetyNote != null) ...[
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 16, color: scheme.error),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(cue.safetyNote!,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.error, fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Renders the "not counted" / "write failed and queued" Waste Ledger
/// verdicts (docs/DECISIONS.md "Waste Ledger legibility — option B"). The
/// "counted" verdict has no equivalent widget — the existing
/// [WasteLedgerCelebrationSheet] already serves that role; this sheet is
/// only ever shown for the other cases (never both in the same sequence).
///
/// Redesigned (device-test round F3): one icon, one line of copy, one CTA
/// that leaves the finished cook and lands on Home. Replaces the old
/// "Got it" button, which only popped the sheet and left Cook Mode sitting
/// there with nowhere else to go.
class _LedgerVerdictSheet extends StatelessWidget {
  const _LedgerVerdictSheet({required this.line});

  final String line;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: AppDesignTokens.surfaceCream,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 44,
              width: 44,
              decoration: BoxDecoration(
                color: AppDesignTokens.deepForest.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: AppDesignTokens.deepForest.withValues(alpha: 0.18)),
              ),
              child: const Icon(Icons.eco_outlined,
                  color: AppDesignTokens.deepForest, size: 22),
            ),
            const SizedBox(height: 14),
            Text(
              line,
              style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppDesignTokens.textCharcoal,
                  height: 1.35),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: AppSizing.primaryButtonHeight,
              child: FilledButton(
                onPressed: () {
                  context.pop();
                  context.go(AppRoutes.home);
                },
                style: FilledButton.styleFrom(
                  backgroundColor: AppDesignTokens.ctaTerracotta,
                  foregroundColor: scheme.onTertiary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18)),
                ),
                child: Text(
                  'Back to Home',
                  style: theme.textTheme.labelLarge?.copyWith(
                      color: scheme.onTertiary, fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CookStepCard extends StatefulWidget {
  const _CookStepCard({
    super.key,
    required this.stepNumber,
    required this.step,
    required this.scienceNote,
    required this.isActive,
    required this.isCompleted,
    required this.remaining,
    required this.cookStarted,
    required this.onToggleCompleted,
  });

  final int stepNumber;
  final _CookStep step;
  final models.CulinaryMatrixCard? scienceNote;
  final bool isActive;
  final bool isCompleted;
  final Duration remaining;
  final bool cookStarted;
  final VoidCallback onToggleCompleted;

  @override
  State<_CookStepCard> createState() => _CookStepCardState();
}

class _CookStepCardState extends State<_CookStepCard> {
  bool _isScienceOpen = false;

  String _format(Duration d) {
    final mins = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final secs = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final bg = widget.isActive
        ? theme.colorScheme.tertiary.withValues(alpha: 0.08)
        : theme.colorScheme.surface;
    final border = widget.isActive
        ? theme.colorScheme.tertiary.withValues(alpha: 0.35)
        : theme.colorScheme.outline.withValues(alpha: 0.14);
    final hasScience = widget.scienceNote != null;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      child: Card(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: widget.isCompleted
                          ? theme.colorScheme.tertiary.withValues(alpha: 0.12)
                          : theme.colorScheme.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: theme.colorScheme.outline
                              .withValues(alpha: 0.14)),
                    ),
                    child: widget.isCompleted
                        ? Icon(Icons.check_rounded,
                            color: theme.colorScheme.tertiary)
                        : Text(
                            '${widget.stepNumber}',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: widget.isActive
                                  ? theme.colorScheme.tertiary
                                  : theme.colorScheme.primary,
                            ),
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Step ${widget.stepNumber}: ${widget.step.actionTitle}',
                          style: theme.textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: widget.step.hasTimer
                              ? [
                                  _HeatBadge(heat: widget.step.heat),
                                  _MiniPill(
                                      icon: Icons.timelapse,
                                      text:
                                          '~${widget.step.duration.inMinutes} min'),
                                  if (widget.cookStarted)
                                    _MiniPill(
                                      icon: Icons.timer_outlined,
                                      text: widget.isActive
                                          ? _format(widget.remaining)
                                          : _format(widget.step.duration),
                                    ),
                                ]
                              : const [
                                  _MiniPill(
                                      icon: Icons.self_improvement_rounded,
                                      text: 'Go at your own pace'),
                                ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton(
                    onPressed: widget.onToggleCompleted,
                    tooltip:
                        widget.isCompleted ? 'Mark not done' : 'Mark complete',
                    icon: Icon(
                      widget.isCompleted
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      color: widget.isCompleted
                          ? theme.colorScheme.tertiary
                          : (widget.isActive
                              ? theme.colorScheme.tertiary
                              : theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              for (var bulletIndex = 0;
                  bulletIndex < widget.step.bullets.length;
                  bulletIndex++) ...[
                _BulletLine(
                  text: widget.step.bullets[bulletIndex],
                  cut: (widget.step.bulletCuts != null &&
                          bulletIndex < widget.step.bulletCuts!.length)
                      ? widget.step.bulletCuts![bulletIndex]
                      : null,
                ),
                const SizedBox(height: 10),
              ],
              if ((widget.step.techniqueDiagramId != noTechniqueDiagramKey &&
                      diagramFor(widget.step.techniqueDiagramId) != null) ||
                  widget.step.cutDiagramKey != null) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (widget.step.techniqueDiagramId !=
                            noTechniqueDiagramKey &&
                        diagramFor(widget.step.techniqueDiagramId) != null)
                      DiagramPill(
                        diagramKey: widget.step.techniqueDiagramId,
                        title:
                            diagramFor(widget.step.techniqueDiagramId)!.title,
                      ),
                    if (widget.step.cutDiagramKey != null)
                      DiagramPill(
                        diagramKey: widget.step.cutDiagramKey!,
                        title: diagramFor(widget.step.cutDiagramKey!)!.title,
                      ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              if (widget.step.sensoryCue != SensoryCueVocabulary.noCueKey)
                _SensoryCueCard(cueKey: widget.step.sensoryCue),
              if (hasScience) ...[
                const SizedBox(height: 4),
                _ScienceNoteDisclosure(
                  isOpen: _isScienceOpen,
                  onToggle: () =>
                      setState(() => _isScienceOpen = !_isScienceOpen),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: !_isScienceOpen
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: matrix_widgets.CulinaryMatrixCard(
                              matrix: widget.scienceNote!),
                        ),
                ),
              ],
              if (widget.isActive && widget.cookStarted) ...[
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color:
                            theme.colorScheme.outline.withValues(alpha: 0.14)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                          widget.step.hasTimer
                              ? Icons.play_circle_fill
                              : Icons.self_improvement_rounded,
                          color: theme.colorScheme.tertiary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.isCompleted
                              ? 'Completed'
                              : (widget.step.hasTimer
                                  ? 'Hands-free timer is running for this step.'
                                  : 'Take your time — mark it complete when you\'re ready.'),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ScienceNoteDisclosure extends StatelessWidget {
  const _ScienceNoteDisclosure({required this.isOpen, required this.onToggle});

  final bool isOpen;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg =
        theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.18);
    final border = theme.colorScheme.outline.withValues(alpha: 0.14);

    return Semantics(
      button: true,
      label: 'Chef\'s Science Note',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onToggle,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border),
          ),
          child: Row(
            children: [
              Icon(Icons.auto_awesome,
                  size: 18, color: theme.colorScheme.tertiary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "Chef's Science Note",
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(width: 8),
              AnimatedRotation(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                turns: isOpen ? 0.5 : 0,
                child: Icon(Icons.expand_more_rounded,
                    color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StartCookingCard extends StatelessWidget {
  const _StartCookingCard({required this.started, required this.onStart});

  final bool started;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: theme.colorScheme.tertiary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(Icons.play_arrow_rounded,
                  color: theme.colorScheme.tertiary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Start Cooking',
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text(
                    started
                        ? 'Player is active — follow the highlighted step.'
                        : 'Kick off Step 1 and enable hands-free auto-advance.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant, height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              height: AppSizing.primaryButtonHeight,
              child: FilledButton(
                onPressed: started ? null : onStart,
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.tertiary,
                  foregroundColor: theme.colorScheme.onTertiary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                ),
                child: Text(started ? 'Live' : 'Start',
                    style: const TextStyle(fontWeight: FontWeight.w900)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CookPlayerBar extends StatelessWidget {
  const _CookPlayerBar({
    required this.isPaused,
    required this.activeStepNumber,
    required this.remaining,
    required this.onPausePressed,
    required this.onNextPressed,
    required this.onAskChefPressed,
    required this.onFinishPressed,
  });

  final bool isPaused;
  final int? activeStepNumber;
  final Duration remaining;
  final VoidCallback onPausePressed;
  final VoidCallback onNextPressed;
  final VoidCallback onAskChefPressed;

  /// Skip-ahead Finish & Plate — reachable from any step during an active
  /// cook, not only once every step is ticked (CLAUDE.md Roadmap item 28).
  /// The caller (`_confirmAndFinish`) shows a confirmation before this ever
  /// actually fires the completion sequence.
  final VoidCallback onFinishPressed;

  String _format(Duration d) {
    final mins = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final secs = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottom = MediaQuery.viewPaddingOf(context).bottom;

    final title = activeStepNumber == null
        ? 'All steps complete'
        : 'Active Step $activeStepNumber';
    final subtitle = activeStepNumber == null
        ? 'You’re done — plate up.'
        : 'Remaining: ${_format(remaining)}';

    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + bottom),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
            top: BorderSide(
                color: theme.colorScheme.outline.withValues(alpha: 0.14))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.3)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: activeStepNumber == null ? null : onPausePressed,
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.tertiary,
                  foregroundColor: theme.colorScheme.onTertiary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                icon: Icon(
                    isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded),
                label: Text(isPaused ? 'Resume' : 'Pause',
                    style: const TextStyle(fontWeight: FontWeight.w900)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: AppSizing.primaryButtonHeight,
                  child: OutlinedButton.icon(
                    onPressed: activeStepNumber == null ? null : onNextPressed,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.onSurface,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    icon: const Icon(Icons.skip_next_rounded),
                    label: const Text('Next Step',
                        style: TextStyle(fontWeight: FontWeight.w900)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: AppSizing.primaryButtonHeight,
                  child: FilledButton.icon(
                    onPressed: onAskChefPressed,
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: theme.colorScheme.onPrimary,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    icon: const Icon(Icons.support_agent),
                    label: Text('Ask ${AppBrand.assistantName}',
                        style: const TextStyle(fontWeight: FontWeight.w900)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Deliberately quieter than the two rows above — a rarer,
          // consequential action (skips remaining steps, fires a permanent
          // ledger write subject to a confirmation) rather than a routine
          // one. See CLAUDE.md Roadmap item 28.
          TextButton.icon(
            onPressed: activeStepNumber == null ? null : onFinishPressed,
            style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.onSurfaceVariant),
            icon: const Icon(Icons.restaurant, size: 18),
            label: const Text('Finish & Plate',
                style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}

/// Confirmation before Finish & Plate fires — it triggers a permanent
/// ledger write (for rescue-eligible, non-re-cook sessions) and skips
/// straight to the post-cook sequence, so an accidental tap would end the
/// session early. Returns true if confirmed. See CLAUDE.md Roadmap item 28.
class _FinishAndPlateConfirmSheet extends StatelessWidget {
  const _FinishAndPlateConfirmSheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: AppDesignTokens.surfaceCream,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
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
                    color: AppDesignTokens.deepForest.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color:
                            AppDesignTokens.deepForest.withValues(alpha: 0.18)),
                  ),
                  child: const Icon(Icons.restaurant,
                      color: AppDesignTokens.deepForest, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Finish & Plate now?',
                    style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: AppDesignTokens.textCharcoal),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              "This ends the cook now and skips any remaining steps — you won't come back to them.",
              style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppDesignTokens.textCharcoal,
                  height: 1.35,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: AppSizing.primaryButtonHeight,
              child: FilledButton(
                onPressed: () => context.pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: AppDesignTokens.ctaTerracotta,
                  foregroundColor: scheme.onTertiary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18)),
                ),
                child: Text(
                  'Finish & Plate',
                  style: theme.textTheme.labelLarge?.copyWith(
                      color: scheme.onTertiary, fontWeight: FontWeight.w900),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => context.pop(false),
                child: Text(
                  'Keep cooking',
                  style: theme.textTheme.labelLarge?.copyWith(
                      color:
                          AppDesignTokens.textCharcoal.withValues(alpha: 0.75),
                      fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeatBadge extends StatelessWidget {
  const _HeatBadge({required this.heat});

  final _HeatLevel heat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, icon, bg, fg) = switch (heat) {
      _HeatLevel.low => (
          'Low Heat',
          Icons.local_fire_department_outlined,
          theme.colorScheme.primary.withValues(alpha: 0.10),
          theme.colorScheme.primary
        ),
      _HeatLevel.medium => (
          'Medium Heat',
          Icons.local_fire_department_outlined,
          theme.colorScheme.tertiary.withValues(alpha: 0.12),
          theme.colorScheme.tertiary
        ),
      _HeatLevel.mediumHigh => (
          'Medium-High',
          Icons.whatshot_outlined,
          theme.colorScheme.tertiary.withValues(alpha: 0.16),
          theme.colorScheme.tertiary
        ),
      _HeatLevel.offHeat => (
          'Off-Heat',
          Icons.power_settings_new_rounded,
          theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
          theme.colorScheme.onSurfaceVariant
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.14))),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 8),
          Text(label,
              style: theme.textTheme.labelLarge
                  ?.copyWith(fontWeight: FontWeight.w900, color: fg)),
        ],
      ),
    );
  }
}

class _MiniPill extends StatelessWidget {
  const _MiniPill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(text,
              style: theme.textTheme.labelLarge
                  ?.copyWith(fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class _BulletLine extends StatelessWidget {
  const _BulletLine({required this.text, this.cut});

  final String text;

  /// Optional cut for this bullet's ingredient (see [_CookStep.bulletCuts])
  /// — renders as the same tappable pill [_IngredientChecklistRow] uses.
  /// Null or `'none'` renders nothing extra, same suppression rule as the
  /// checklist row.
  final String? cut;

  void _showCutDefinition(BuildContext context, String cut) {
    AppBottomSheet.show<void>(
      context: context,
      backgroundColor: AppDesignTokens.surfaceCream,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(child: _CutDefinitionSheet(cut: cut)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showCut = cut != null && cut != 'none';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Icon(Icons.fiber_manual_record,
              size: 10, color: theme.colorScheme.tertiary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(text,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.45)),
              if (showCut) ...[
                const SizedBox(height: 4),
                InkWell(
                  onTap: () => _showCutDefinition(context, cut!),
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.tertiary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                          color: theme.colorScheme.tertiary
                              .withValues(alpha: 0.20)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          ingredientCutLabel(cut!),
                          style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: theme.colorScheme.tertiary),
                        ),
                        const SizedBox(width: 3),
                        Icon(Icons.info_outline_rounded,
                            size: 12, color: theme.colorScheme.tertiary),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _FlavorCheckpointCard extends StatelessWidget {
  const _FlavorCheckpointCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                      color: theme.colorScheme.tertiary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(16)),
                  child: Icon(Icons.auto_awesome,
                      color: theme.colorScheme.tertiary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Chef Harris Flavor Checkpoint',
                          style: theme.textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 4),
                      Text(
                        'Taste now. Adjust off-heat so the finish stays clean and glossy.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.45),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _CheckpointActionChip(
                  icon: Icons.local_drink_outlined,
                  label: 'Needs acid?',
                  response: 'Add 1 tsp lemon juice or apple cider vinegar.',
                ),
                _CheckpointActionChip(
                  icon: Icons.spa,
                  label: 'Needs salt?',
                  response: 'Add a pinch of sea salt now off-heat.',
                ),
                _CheckpointActionChip(
                  icon: Icons.eco,
                  label: 'Needs freshness?',
                  response: 'Toss in fresh chopped parsley or chives.',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckpointActionChip extends StatelessWidget {
  const _CheckpointActionChip(
      {required this.icon, required this.label, required this.response});

  final IconData icon;
  final String label;
  final String response;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ActionChip(
      avatar: Icon(icon, size: 18, color: theme.colorScheme.tertiary),
      label: Text(label,
          style: theme.textTheme.labelLarge
              ?.copyWith(fontWeight: FontWeight.w900)),
      onPressed: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onInverseSurface)),
            backgroundColor: theme.colorScheme.inverseSurface,
            behavior: SnackBarBehavior.floating,
            showCloseIcon: true,
            closeIconColor: theme.colorScheme.onInverseSurface,
          ),
        );
      },
    );
  }
}

class _CookModeBottomBar extends StatelessWidget {
  const _CookModeBottomBar(
      {required this.onSosPressed, required this.onFinishPressed});

  final VoidCallback onSosPressed;
  final VoidCallback onFinishPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + bottom),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
            top: BorderSide(
                color: theme.colorScheme.outline.withValues(alpha: 0.14))),
      ),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: AppSizing.primaryButtonHeight,
              child: OutlinedButton.icon(
                onPressed: onSosPressed,
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.onSurface,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                icon: const Icon(Icons.support_agent),
                label: Text('Live ${AppBrand.assistantName} SOS',
                    style: const TextStyle(fontWeight: FontWeight.w900)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: AppSizing.primaryButtonHeight,
              child: FilledButton.icon(
                onPressed: onFinishPressed,
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                icon: const Icon(Icons.restaurant),
                label: const Text('Finish & Plate',
                    style: TextStyle(fontWeight: FontWeight.w900)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StartCookingBottomBar extends StatelessWidget {
  const _StartCookingBottomBar(
      {required this.onSosPressed, required this.onStartPressed});

  final VoidCallback onSosPressed;
  final VoidCallback onStartPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + bottom),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
            top: BorderSide(
                color: theme.colorScheme.outline.withValues(alpha: 0.14))),
      ),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: AppSizing.primaryButtonHeight,
              child: OutlinedButton.icon(
                onPressed: onSosPressed,
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.onSurface,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                icon: const Icon(Icons.support_agent),
                label: Text('Live ${AppBrand.assistantName} SOS',
                    style: const TextStyle(fontWeight: FontWeight.w900)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: AppSizing.primaryButtonHeight,
              child: FilledButton.icon(
                onPressed: onStartPressed,
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.tertiary,
                  foregroundColor: theme.colorScheme.onTertiary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Start Cooking',
                    style: TextStyle(fontWeight: FontWeight.w900)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SosTipCard extends StatelessWidget {
  const _SosTipCard(
      {required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.14)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: theme.colorScheme.tertiary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, size: 18, color: theme.colorScheme.tertiary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text(body,
                    style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.45)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChefSosSheet extends StatefulWidget {
  const _ChefSosSheet(
      {required this.recipeTitle,
      required this.quickPrompts,
      required this.recipeContext});

  final String recipeTitle;
  final List<String> quickPrompts;

  /// The recipe as written (ingredients, steps, current-step marker) —
  /// see `_OnePanCookingRoadmapScreenState._buildSosRecipeContext`. Passed
  /// through to every `askChefHarris` call so answers stay grounded in
  /// what the recipe actually says.
  final String recipeContext;

  @override
  State<_ChefSosSheet> createState() => _ChefSosSheetState();
}

class _ChefSosSheetState extends State<_ChefSosSheet> {
  final _chefService = ChefService();
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  bool _isSending = false;
  String? _error;

  final List<_SosMessage> _messages = <_SosMessage>[];

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _postFrame(VoidCallback fn) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      fn();
    });
  }

  void _closeSheet() {
    _postFrame(() {
      if (!mounted) return;
      context.pop();
    });
  }

  Future<void> _send(String raw) async {
    final text = raw.trim();
    if (text.isEmpty) return;
    if (_isSending) return;

    setState(() {
      _isSending = true;
      _error = null;
      _messages.add(_SosMessage.user(text));
      _controller.clear();
    });
    _postFrame(_scrollToBottom);

    try {
      final profile = context.read<UserProfileController>().profile;
      // History = everything before the user message just appended above —
      // that message is already carried as `userQuery`, so including it
      // here too would duplicate it.
      final history = _messages.length > 1
          ? _messages
              .sublist(0, _messages.length - 1)
              .map((m) => (isUser: m.speaker == _SosSpeaker.user, text: m.text))
              .toList(growable: false)
          : const <({bool isUser, String text})>[];
      final reply = await _chefService.askChefHarris(
        userQuery: text,
        recipeTitle: widget.recipeTitle,
        profile: profile,
        recipeContext: widget.recipeContext,
        conversationHistory: history,
      );
      if (!mounted) return;
      setState(() => _messages.add(_SosMessage.chef(reply)));
      _postFrame(_scrollToBottom);
    } catch (e) {
      debugPrint('Chef SOS send failed: $e');
      if (!mounted) return;
      setState(
          () => _error = 'Couldn\'t reach Chef Harris. Try again in a moment.');
    } finally {
      if (!mounted) return;
      setState(() => _isSending = false);
    }
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return SafeArea(
      top: false,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Everything except the input row lives inside this Expanded,
              // which gives the inner Column below a genuinely bounded
              // (not infinite, not a fixed fraction of screen height) max
              // height — whatever's actually left after the input row and
              // AnimatedPadding's keyboard-inset padding above. Within that
              // bounded context, the header and quick prompts take their
              // natural size and the message box is the inner Column's own
              // Expanded child, so it gets exactly the true remaining
              // space — no gap, no fixed guess. It's also the ONLY
              // scrollable in this whole sheet now (no outer
              // SingleChildScrollView competing with it for drag gestures,
              // which is what caused messages to appear clipped instead of
              // scrolling last time). The input row stays a plain sibling
              // of this Expanded, never wrapped in anything scrollable —
              // always visible.
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header + quick-prompt chips (device-test round F8):
                    // wrapped in their own Flexible + SingleChildScrollView
                    // so that when the keyboard opens on a short screen and
                    // squeezes the space this Expanded gets, this block
                    // scrolls internally instead of overflowing — it has no
                    // ListView of its own, so it can't repeat the
                    // drag-gesture conflict the comment below warns about.
                    // At normal size (keyboard closed, plenty of room) this
                    // renders identically to before: Flexible only shrinks
                    // below natural size when the available height actually
                    // demands it.
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Ask Chef Harris',
                                        style: theme.textTheme.titleLarge
                                            ?.copyWith(
                                                fontWeight: FontWeight.w900),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Fast rescue steps + smart substitutions.',
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                                color: theme.colorScheme
                                                    .onSurfaceVariant,
                                                height: 1.35),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  onPressed: _closeSheet,
                                  tooltip: 'Back to cooking',
                                  icon: Icon(Icons.close_rounded,
                                      color:
                                          theme.colorScheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (_messages.isEmpty) ...[
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: [
                                    for (final p in widget.quickPrompts)
                                      ActionChip(
                                        label: Text(p,
                                            style: theme.textTheme.labelLarge
                                                ?.copyWith(
                                                    fontWeight:
                                                        FontWeight.w800)),
                                        onPressed: _isSending
                                            ? null
                                            : () {
                                                _controller.text = p.replaceAll(
                                                    RegExp(
                                                        r'^[^A-Za-z0-9]+\s*'),
                                                    '');
                                                _controller.selection =
                                                    TextSelection.collapsed(
                                                        offset: _controller
                                                            .text.length);
                                                _postFrame(() =>
                                                    _send(_controller.text));
                                              },
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 14),
                            ],
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                              color: theme.colorScheme.outline
                                  .withValues(alpha: 0.14)),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: _messages.isEmpty
                              ? Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _SosTipCard(
                                        icon: Icons.pan_tool_alt_rounded,
                                        title: 'Tell me what you see',
                                        body:
                                            '“Too watery”, “too salty”, “nothing is browning”, or “timer done but rice still hard”.',
                                      ),
                                      const SizedBox(height: 10),
                                      _SosTipCard(
                                        icon: Icons.storefront,
                                        title: 'Missing an ingredient?',
                                        body:
                                            'Say what you have — I\'ll give a 1:1 substitute.',
                                      ),
                                    ],
                                  ),
                                )
                              : ListView.builder(
                                  controller: _scrollController,
                                  // Extra right padding (vs. 14 on the
                                  // other sides) so bubble content clears
                                  // the system scrollbar overlay instead
                                  // of running underneath it.
                                  padding:
                                      const EdgeInsets.fromLTRB(14, 14, 20, 14),
                                  itemCount:
                                      _messages.length + (_isSending ? 1 : 0),
                                  itemBuilder: (context, index) {
                                    if (_isSending &&
                                        index == _messages.length) {
                                      return const _ChefTypingBubble();
                                    }
                                    final m = _messages[index];
                                    return Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 10),
                                      child: _SosBubble(message: m),
                                    );
                                  },
                                ),
                        ),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(_error!,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(color: theme.colorScheme.error)),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (v) => _send(v),
                      decoration: InputDecoration(
                        hintText: 'What\'s going wrong in the pan?',
                        filled: true,
                        fillColor: theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.22),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(
                              color: theme.colorScheme.outline
                                  .withValues(alpha: 0.18)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(
                              color: theme.colorScheme.outline
                                  .withValues(alpha: 0.18)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(
                              color: theme.colorScheme.primary
                                  .withValues(alpha: 0.55)),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    height: 52,
                    child: FilledButton(
                      onPressed:
                          _isSending ? null : () => _send(_controller.text),
                      style: FilledButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: theme.colorScheme.onPrimary,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                      child: const Icon(Icons.send_rounded),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _SosSpeaker { user, chef }

class _SosMessage {
  const _SosMessage({required this.speaker, required this.text});

  final _SosSpeaker speaker;
  final String text;

  factory _SosMessage.user(String text) =>
      _SosMessage(speaker: _SosSpeaker.user, text: text);
  factory _SosMessage.chef(String text) =>
      _SosMessage(speaker: _SosSpeaker.chef, text: text);
}

class _SosBubble extends StatelessWidget {
  const _SosBubble({required this.message});

  final _SosMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.speaker == _SosSpeaker.user;

    final bg = isUser
        ? theme.colorScheme.primary
        : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.22);
    final fg =
        isUser ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(18),
            border: isUser
                ? null
                : Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.14)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Text(
              message.text,
              style:
                  theme.textTheme.bodyMedium?.copyWith(color: fg, height: 1.45),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChefTypingBubble extends StatelessWidget {
  const _ChefTypingBubble();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color:
              theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.14)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: theme.colorScheme.primary),
            ),
            const SizedBox(width: 10),
            Text(
              'Chef Harris is thinking…',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
