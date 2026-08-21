import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:optimeal/nav.dart';
import 'package:optimeal/models/technique_lesson.dart' as models;
import 'package:optimeal/prompts/recipe_static_prompts.dart';
import 'package:optimeal/services/ai_recipe_service.dart';
import 'package:optimeal/services/chef_recipe_parser.dart';
import 'package:optimeal/services/chef_service.dart';
import 'package:optimeal/services/cook_session_storage_service.dart';
import 'package:optimeal/services/entitlement_service.dart';
import 'package:optimeal/services/fridge_clearer_entry_service.dart';
import 'package:optimeal/services/fridge_nudge_service.dart';
import 'package:optimeal/services/recent_generations_service.dart';
import 'package:optimeal/services/saved_recipes_service.dart';
import 'package:optimeal/services/usage_cap_service.dart';
import 'package:optimeal/screens/one_pan_cooking_roadmap_screen.dart';
import 'package:optimeal/state/user_profile_controller.dart';
import 'package:optimeal/theme.dart';
import 'package:optimeal/theme/app_design_tokens.dart';
import 'package:optimeal/widgets/app_bottom_sheet.dart';
import 'package:optimeal/widgets/culinary_matrix_card.dart' as matrix_widgets;
import 'package:optimeal/widgets/home_glyph_button.dart';
import 'package:optimeal/widgets/save_recipe_bookmark_button.dart';
import 'package:optimeal/widgets/upgrade_prompt_sheet.dart';
import 'package:optimeal/widgets/weekday_picker_sheet.dart';
import 'package:optimeal/services/weekly_planner_intent_service.dart';

/// Free-tier weekly cap on Fridge Clearer AI generations (protects real
/// marginal OpenAI cost — see CLAUDE.md "Monetization / paywall tier
/// structure"). Pro users are unlimited.
const int kFridgeClearerFreeWeeklyLimit = 3;

enum _FridgeTimePreset { min15, min30, min45Plus }

enum _CookwarePreset { pan, onePot, ovenTray, wok, airFryer, blender }

class FridgeClearerScreen extends StatefulWidget {
  const FridgeClearerScreen({super.key, this.returnCookModePayload = false});

  /// When true, tapping "Cook This" will `pop()` a [CookModeRecipePayload]
  /// back to the caller instead of pushing Cook Mode.
  ///
  /// This is used by Weekly Planner to fill a selected day/slot.
  final bool returnCookModePayload;

  @override
  State<FridgeClearerScreen> createState() => _FridgeClearerScreenState();
}

class _FridgeClearerScreenState extends State<FridgeClearerScreen> {
  final _aiRecipeService = AiRecipeService();
  final _chefService = ChefService();
  final _extraController = TextEditingController();
  final _extraFocusNode = FocusNode();

  final Set<String> _selectedIngredients = <String>{};
  _FridgeTimePreset? _timePreset;
  final Set<_CookwarePreset> _cookware = <_CookwarePreset>{};

  /// Null means "use the value from the user's profile". Set once the user
  /// taps a portion pill to override it just for this session.
  int? _selectedPortions;

  bool _isGenerating = false;
  List<models.CulinaryMatrixCard> _precisionCards = const [];
  CookModeRecipePayload? _generatedRecipe;
  String? _generationError;
  bool _scienceNotesExpanded = false;

  /// Attached to [GeneratedRecipeCard] so a fresh generation can scroll
  /// itself into view (device-test round F7) — the result previously
  /// landed below several sections of the fold with no cue to scroll down
  /// to it.
  final _generatedRecipeKey = GlobalKey();

  static const List<String> _quickIngredients = [
    'Zucchini',
    'Eggs',
    'Potatoes',
    'Cheese',
    'Cream',
    'Onions',
    'Stale Bread',
    'Meat/Tofu',
  ];

  static const Map<String, IconData> _ingredientIcons = {
    'Zucchini': Icons.eco_outlined,
    'Eggs': Icons.egg_alt_outlined,
    'Potatoes': Icons.agriculture_outlined,
    'Cheese': Icons.restaurant_outlined,
    'Cream': Icons.local_cafe_outlined,
    'Onions': Icons.grass_outlined,
    'Stale Bread': Icons.bakery_dining_outlined,
    'Meat/Tofu': Icons.set_meal_outlined,
  };

  /// Portion presets, matching the same 1/2/4/6+ options offered in onboarding.
  static const List<int> _portionOptions = [1, 2, 4, 6];

  @override
  void dispose() {
    _extraController.dispose();
    _extraFocusNode.dispose();
    super.dispose();
  }

  /// Scrolls the freshly-generated recipe card into view (device-test
  /// round F7). Runs on the next frame so [_generatedRecipeKey] has
  /// already attached to the newly-built card.
  void _scrollToGeneratedRecipe() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final cardContext = _generatedRecipeKey.currentContext;
      if (cardContext == null) return;
      unawaited(
        Scrollable.ensureVisible(
          cardContext,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          alignment: 0.05,
        ),
      );
    });
  }

  void _toggleIngredient(String label) {
    setState(() {
      if (_selectedIngredients.contains(label)) {
        _selectedIngredients.remove(label);
      } else {
        _selectedIngredients.add(label);
      }
    });
  }

  void _addExtraIngredient() {
    final v = _extraController.text.trim();
    if (v.isEmpty) return;

    setState(() {
      _selectedIngredients.add(v);
      _extraController.clear();
    });
    _extraFocusNode.requestFocus();
  }

  IconData _timeIcon(_FridgeTimePreset p) => switch (p) {
        _FridgeTimePreset.min15 => Icons.flash_on_rounded,
        _FridgeTimePreset.min30 => Icons.timer_outlined,
        _FridgeTimePreset.min45Plus => Icons.schedule_rounded,
      };

  String _timeLabel(_FridgeTimePreset p) => switch (p) {
        _FridgeTimePreset.min15 => '15 Min',
        _FridgeTimePreset.min30 => '30 Min',
        _FridgeTimePreset.min45Plus => '45+ Min',
      };

  IconData _cookwareIcon(_CookwarePreset c) => switch (c) {
        _CookwarePreset.pan => Icons.kitchen_outlined,
        _CookwarePreset.onePot => Icons.soup_kitchen_outlined,
        _CookwarePreset.ovenTray => Icons.local_pizza_outlined,
        _CookwarePreset.wok => Icons.ramen_dining_outlined,
        _CookwarePreset.airFryer => Icons.air_outlined,
        _CookwarePreset.blender => Icons.blender_outlined,
      };

  String _cookwareLabel(_CookwarePreset c) => switch (c) {
        _CookwarePreset.pan => 'Pan/Skillet',
        _CookwarePreset.onePot => 'One-Pot',
        _CookwarePreset.ovenTray => 'Oven Tray',
        _CookwarePreset.wok => 'Wok',
        _CookwarePreset.airFryer => 'Air Fryer',
        _CookwarePreset.blender => 'Blender/Processor',
      };

  void _toggleCookware(_CookwarePreset c) {
    setState(() {
      if (_cookware.contains(c)) {
        _cookware.remove(c);
      } else {
        _cookware.add(c);
      }
    });
  }

  /// Human-friendly label for a portion count, e.g. "1 Person", "4 People", "6+ People".
  String _portionLabel(int p) {
    if (p >= 6) return '6+ People';
    if (p == 1) return '1 Person';
    return '$p People';
  }

  /// The byte-identical half of the Fridge Clearer prompt: JSON schema,
  /// guidelines, and the closed-vocabulary declarations. Sent to
  /// [ChefService.askChefHarris] as `staticPromptBlock`, deliberately NOT
  /// concatenated into the query.
  ///
  /// 2026-08-21: this text used to be the head of one combined string that
  /// travelled as `userQuery`. That put it *behind* the per-call
  /// `Recipe context:` line in the assembled message, so ~1,200 static
  /// tokens sat outside the cacheable prefix on every call — the cedf753
  /// reorder was correct within this string but defeated downstream. See
  /// [ChefService.buildUserMessage]. Wording here is byte-identical to
  /// before; only where it is sent changed.
  ///
  /// Anything added here must be genuinely static. The one guideline line
  /// that embeds `$portions` mid-sentence stays in the variable half below,
  /// since its own text can't be made static without changing wording.
  static String _buildCookModeStaticPrompt() =>
      buildFridgeClearerStaticPrompt();

  /// The per-call half: the idea, the real ingredient selection, and the
  /// context that changes on every generation. Sent as `userQuery`, which
  /// lands after all static content in the assembled message.
  String _buildCookModeVariablePrompt(_RecipeIdea idea, int portions,
      {String? excludeTitle}) {
    final ingredients = _selectedIngredients.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final ingredientsText = ingredients.isEmpty
        ? 'No ingredients specified.'
        : ingredients.join(', ');

    final timeText =
        _timePreset == null ? 'not specified' : _timeLabel(_timePreset!);
    final cookwareText = _cookware.isEmpty
        ? 'not specified'
        : (_cookware.toList()
              ..sort((a, b) => _cookwareLabel(a).compareTo(_cookwareLabel(b))))
            .map(_cookwareLabel)
            .join(', ');

    return [
      'Create a cook-mode recipe for this specific idea: "${idea.title}" (tag: ${idea.tag}).',
      '',
      'Context (Swiss home kitchen):',
      '- Ingredients available (focus on perishables): $ingredientsText',
      '- Assume pantry staples available: oils, salt/pepper, spices, pasta/rice.',
      '- Time available: $timeText',
      '- Cookware/appliances available: $cookwareText',
      '- Number of people this recipe should serve: $portions',
      if (excludeTitle != null && excludeTitle.trim().isNotEmpty)
        '- Do NOT suggest this exact dish again: "${excludeTitle.trim()}". Come up with a genuinely different dish idea using the same ingredients.',
      '- Each ingredient must be a structured object with a numeric "amount" and a "unit", realistically scaled for $portions people — do not reuse the same quantity regardless of how many people are being served. Use "piece", "clove", or "slice" as the unit for whole/countable items instead of inventing a weight.',
    ].join('\n');
  }

  _RecipeIdea _buildCookModeIdeaFromCurrentInputs() {
    final ingredients = _selectedIngredients.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final title = ingredients.isEmpty
        ? 'Fridge Clearer One-Pan'
        : 'Fridge Clearer: ${ingredients.take(2).join(' + ')}${ingredients.length > 2 ? ' + …' : ''}';

    final cookware = _cookware.isEmpty
        ? const <String>['Pan/Skillet', 'One-Pot']
        : (_cookware.toList()
              ..sort((a, b) => _cookwareLabel(a).compareTo(_cookwareLabel(b))))
            .map(_cookwareLabel)
            .toList(growable: false);

    final prepMinutes = switch (_timePreset) {
      _FridgeTimePreset.min15 => 15,
      _FridgeTimePreset.min30 => 30,
      _FridgeTimePreset.min45Plus => 45,
      null => 30,
    };

    return _RecipeIdea(
        tag: 'Cook Mode',
        title: title,
        prepMinutes: prepMinutes,
        cookware: cookware);
  }

  void _cookNow() {
    final payload = _generatedRecipe;
    if (payload == null) return;
    if (widget.returnCookModePayload) {
      context.pop(payload);
    } else {
      context.push(
        AppRoutes.onePanCookingRoadmap,
        extra: CookModeLaunchRequest(
            recipe: payload, surface: CookModeSurface.fridgeClearer),
      );
    }
  }

  Future<void> _planForDay() async {
    final payload = _generatedRecipe;
    if (payload == null) return;

    final dayIndex = await AppBottomSheet.show<int>(
      context: context,
      isScrollControlled: false,
      showDragHandle: true,
      backgroundColor: AppDesignTokens.surfaceCream,
      builder: (ctx) => const SafeArea(
          child: WeekdayPickerSheet(title: '📅 Plan for which day?')),
    );
    if (!mounted || dayIndex == null) return;

    WeeklyPlannerIntentService.instance.queueAddMeal(
        dayIndex: dayIndex, recipe: payload, source: 'Clear Fridge Leftovers');

    if (widget.returnCookModePayload) {
      // We were pushed FROM the Weekly Planner (e.g. "Add Meal" -> "Clear
      // Fridge"). The planner screen is still alive underneath us and is
      // already listening for the intent we just queued above — it will
      // add the meal, persist it, and show its own "Added to <Day>!"
      // confirmation.
      //
      // Previously this method never popped in that branch, so this screen
      // stayed on top and the user saw the "Cook This / Plan for Day"
      // prompt again — looking like the app was asking them to confirm a
      // second time, even though the meal had already been queued.
      if (context.mounted) context.pop();
      return;
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text('Added to ${WeekdayPickerSheet.labelsLong[dayIndex]}!'),
          behavior: SnackBarBehavior.floating),
    );
  }

  String _formatHeatCue(Map<String, dynamic>? heatSpec) {
    if (heatSpec == null || heatSpec.isEmpty) return '';
    final entries = heatSpec.entries
        .where((e) => e.key.trim().isNotEmpty)
        .map((e) => '${e.key}: ${e.value}'.trim())
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
    return entries.isEmpty ? '' : entries.join(' • ');
  }

  String? _formatRatioSummary(Map<String, dynamic>? baseRatios) {
    if (baseRatios == null || baseRatios.isEmpty) return null;
    final pieces = <String>[];
    for (final e in baseRatios.entries) {
      final k = e.key.toString().trim();
      final v = e.value;
      if (k.isEmpty || v == null) continue;
      final vs = v.toString().trim();
      if (vs.isEmpty) continue;
      pieces.add('$k=$vs');
    }
    if (pieces.isEmpty) return null;
    return pieces.length <= 3
        ? pieces.join('  ')
        : '${pieces.take(3).join('  ')}  +…';
  }

  String _formatSubstitutes(Map<String, dynamic>? subs) {
    if (subs == null || subs.isEmpty) return '';
    final pieces = <String>[];
    for (final e in subs.entries) {
      final k = e.key.toString().trim();
      final v = e.value;
      if (k.isEmpty || v == null) continue;
      final vs = v.toString().trim();
      if (vs.isEmpty) continue;
      pieces.add('$k → $vs');
    }
    return pieces.isEmpty ? '' : pieces.join(' • ');
  }

  /// Fetches the precision/technique notes cards. May hit the cache; is a
  /// nice-to-have, so failures are swallowed here (never thrown) rather than
  /// blocking the actual recipe generation running alongside it.
  Future<List<models.CulinaryMatrixCard>> _fetchPrecisionCards(
      List<String> ingredients) async {
    final cards = <models.CulinaryMatrixCard>[];
    try {
      final precision = await _aiRecipeService.getPrecisionData(
        ingredients: ingredients,
        method: 'fridge_clearer',
        protein: '',
        cutStyle: '',
      );

      final heatCue = _formatHeatCue(precision.heatSpec);
      final ratioSummary = _formatRatioSummary(precision.baseRatios);
      final substitutes = _formatSubstitutes(precision.swissSubstitutes);
      final salt = (precision.saltTiming ?? '').trim();

      cards.add(
        models.CulinaryMatrixCard(
          id: 'precision_core',
          title: 'Chef\'s Precision Notes',
          heatCue: heatCue,
          timingNote: salt.isEmpty
              ? 'Salt in layers: early for diffusion, finish for brightness.'
              : salt,
          knifeCutSpec: precision.knifeCutSpec,
          whyThisWorks: precision.source == 'cache'
              ? 'This is pulled from Chef Harris\' reference playbook — fast, consistent, and very Swiss-kitchen friendly.'
              : 'This is generated for your exact fridge mix, so you get better browning, texture, and timing control.',
          ratioSummary: ratioSummary,
        ),
      );
      if (substitutes.isNotEmpty) {
        cards.add(
          models.CulinaryMatrixCard(
            id: 'precision_subs',
            title: 'Swiss Substitute Map',
            heatCue: '',
            timingNote: '',
            knifeCutSpec: null,
            whyThisWorks: substitutes,
            ratioSummary: null,
          ),
        );
      }
    } catch (e, st) {
      // Non-fatal: the actual recipe is the priority. If this fails, the
      // Science Notes section is simply omitted for this generation.
      debugPrint(
          'Fridge Clearer: precision notes fetch failed (non-fatal): $e');
      debugPrint('$st');
    }
    return cards;
  }

  /// Primary CTA action. Generates BOTH the technique/precision notes and the
  /// actual recipe (title, description, ingredients, steps) in one pass, so
  /// the dish identity is visible immediately rather than only after "Cook Now".
  ///
  /// Pass [excludePrevious] = true to ask Chef Harris for a different idea
  /// than whatever is currently in [_generatedRecipe] (used by "Try Another").
  Future<void> _generateRecipe({bool excludePrevious = false}) async {
    if (_isGenerating) return;
    final theme = Theme.of(context);

    if (_selectedIngredients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Add at least 1 ingredient so Chef Harris can suggest ideas.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onInverseSurface),
          ),
          backgroundColor: theme.colorScheme.inverseSurface,
          behavior: SnackBarBehavior.floating,
        ),
      );
      _extraFocusNode.requestFocus();
      return;
    }

    final isPro = await EntitlementService.instance.isPro();
    if (!mounted) return;
    if (!isPro) {
      final weeklyCount = await UsageCapService.instance
          .getRollingWeekCount(UsageFeature.fridgeClearerGeneration);
      if (!mounted) return;
      if (weeklyCount >= kFridgeClearerFreeWeeklyLimit) {
        await UpgradePromptSheet.show(
          context,
          title: "You've used this week's free generations",
          message:
              'Free plan includes $kFridgeClearerFreeWeeklyLimit Fridge Clearer generation${kFridgeClearerFreeWeeklyLimit == 1 ? '' : 's'} a week. '
              'Upgrade to Pro for unlimited generations, Custom AI Recipe Creator, and more.',
        );
        return;
      }
    }

    final previousTitle = excludePrevious ? _generatedRecipe?.title : null;

    setState(() {
      _isGenerating = true;
      _precisionCards = const [];
      _generatedRecipe = null;
      _generationError = null;
    });

    try {
      final ingredients = _selectedIngredients.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      final idea = _buildCookModeIdeaFromCurrentInputs();
      final profile = context.read<UserProfileController>().profile;
      final portions = _selectedPortions ?? profile.householdServings;

      // The precision/technique notes and the actual recipe are two fully
      // independent AI calls — the recipe prompt doesn't depend on precision
      // data in any way. Kick both off before awaiting either so they run
      // concurrently instead of serially doubling the user's wait.
      final precisionCardsFuture = _fetchPrecisionCards(ingredients);
      final staticPrompt = _buildCookModeStaticPrompt();
      final prompt = _buildCookModeVariablePrompt(idea, portions,
          excludeTitle: previousTitle);
      // Usage tracking is unconditional and independent of entitlement
      // (CLAUDE.md roadmap item 11 follow-up, 2026-08-13) — always counts
      // this real attempted call, regardless of Pro/kDebugMode status. Only
      // the cap CHECK above (weeklyCount >= kFridgeClearerFreeWeeklyLimit)
      // stays gated on isPro; tracking and gating must not share a
      // conditional, or a bypass in one silently breaks the other.
      unawaited(UsageCapService.instance
          .increment(UsageFeature.fridgeClearerGeneration));
      // Recipe variety (CLAUDE.md roadmap item 13): steer away from
      // recently cooked dishes so the same handful (frittata, stir-fry,
      // etc.) doesn't keep recurring regardless of actual ingredients.
      // Merges two sources: persisted cook history (only populated when a
      // recipe is actually opened in Cook Mode) and this app session's
      // in-memory RecentGenerationsService (every generation, cooked or
      // not) — the latter is what closes the gap where 5 straight "Try
      // Another"/"Generate" calls in one sitting previously had nothing to
      // exclude against.
      final recentCookHistory =
          await CookSessionStorageService().loadCookHistory();
      final recentDishTitles = [
        ...RecentGenerationsService.instance.recent(),
        ...recentCookHistory.map((e) => e.recipe.title),
      ];
      final replyFuture = _chefService.askChefHarris(
        userQuery: prompt,
        staticPromptBlock: staticPrompt,
        recipeTitle: idea.title,
        profile: profile,
        forceJsonObject: true,
        recentDishTitles: recentDishTitles,
        surface: kChefCallSurfaceFridgeClearer,
      );

      // Precision notes are a nice-to-have and never throw (errors are
      // caught inside _fetchPrecisionCards), so await them first without
      // risk of masking a real recipe-generation failure below.
      final cards = await precisionCardsFuture;
      if (!mounted) return;
      final reply = await replyFuture;
      if (!mounted) return;

      var recipe = await parseChefRecipeJson(
        raw: reply,
        portions: portions,
        fallbackTitle: 'Fridge Clearer Recipe',
        surface: ChefRecipeSurface.fridgeClearer,
        useGenericFallbacks: false,
        readDescription: true,
      );
      if (recipe == null) {
        debugPrint(
            'FridgeClearer: cook-mode generation returned invalid JSON. Raw: $reply');
        if (!mounted) return;
        setState(() {
          _generationError =
              'Couldn\'t generate a recipe right now. Please try again.';
        });
        return;
      }

      // curriculumLessonIds is populated by the parser directly from the
      // model's own declared "curriculum_lesson_id" field now — no more
      // keyword-matching the recipe's generated text after the fact (that
      // mechanism could match a reference drawer like food_storage on any
      // zero-waste-flavored sentence regardless of what the recipe
      // actually taught; see CLAUDE.md for the frittata/food_storage case
      // that motivated this).
      debugPrint(
          'CookModeRecipePayload constructed with curriculumLessonIds=${recipe.curriculumLessonIds}');

      // Provenance travels with the recipe. `origin` is already stamped by
      // the parser; the entered list has to be attached here, since only
      // this screen knows it. Together these are what let a Fridge Clearer
      // recipe scheduled into the Weekly Planner still count as a rescue
      // when it's finally cooked — see RecipeOrigin.
      final enteredIngredients = _selectedIngredients.toList(growable: false);
      recipe = recipe.copyWith(originEnteredIngredients: enteredIngredients);

      RecentGenerationsService.instance.record(recipe.title);
      // Fridge nudge (docs/decisions_2026-08-17.md item 5): a generated
      // recipe is the earliest durable signal that these ingredients were
      // "entered" — schedules a single 2-day-out nudge if the user never
      // actually cooks it.
      unawaited(FridgeNudgeService.instance.onFridgeClearerIngredientsGenerated());
      // Persists the entered ingredients (device-test round F12/F13) so a
      // later completed cook can check for leftovers and the Waste Ledger
      // can apply its provenance rule — see FridgeClearerEntryService.
      unawaited(
          FridgeClearerEntryService().recordEnteredIngredients(enteredIngredients));

      setState(() {
        _precisionCards = cards;
        _generatedRecipe = recipe;
      });
      _scrollToGeneratedRecipe();
    } catch (e, st) {
      debugPrint('Fridge Clearer recipe generation failed: $e');
      debugPrint('$st');

      try {
        void logIfPresent(String label, Object? value) {
          if (value == null) return;
          final s = value.toString();
          if (s.trim().isEmpty) return;
          debugPrint('Fridge Clearer chef-service raw $label: $s');
        }

        final dyn = e as dynamic;
        logIfPresent('status', () {
          try {
            return dyn.status;
          } catch (_) {
            return null;
          }
        }());
        logIfPresent('statusCode', () {
          try {
            return dyn.statusCode;
          } catch (_) {
            return null;
          }
        }());
        logIfPresent('body', () {
          try {
            return dyn.body;
          } catch (_) {
            return null;
          }
        }());
        logIfPresent('response', () {
          try {
            return dyn.response;
          } catch (_) {
            return null;
          }
        }());
      } catch (logErr) {
        debugPrint(
            'Fridge Clearer generation: failed to extract raw response details: $logErr');
      }

      if (!mounted) return;
      setState(() {
        _generationError =
            'Couldn\'t generate a recipe right now. Please try again.';
      });
    } finally {
      if (!mounted) return;
      setState(() => _isGenerating = false);
    }
  }

  Widget _buildBackButton({required bool pop}) {
    return IconButton(
      onPressed: pop ? () => context.pop() : () => context.go(AppRoutes.home),
      tooltip: pop ? 'Back' : 'Home',
      icon: Container(
        padding: const EdgeInsets.all(AppDesignTokens.spaceXS),
        decoration: BoxDecoration(
          color: AppDesignTokens.surfaceCream.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(AppDesignTokens.radiusChip),
          border: Border.all(
              color: AppDesignTokens.textCharcoal.withValues(alpha: 0.12)),
        ),
        child:
            const Icon(Icons.arrow_back, color: AppDesignTokens.textCharcoal),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<UserProfileController>().profile;
    final effectivePortions = _selectedPortions ?? profile.householdServings;

    return Scaffold(
      backgroundColor: AppDesignTokens.backgroundSage,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        // Two depths, one screen. Opened straight off the Home hub this is
        // depth-1 — back only, and back means Home. Opened as the Weekly
        // Planner's picker (returnCookModePayload) it's depth-2 — back pops
        // to the planner it must return a payload to, and the quiet home
        // glyph is the escape hatch the bottom nav bar used to be.
        leadingWidth: widget.returnCookModePayload
            ? kBackWithHomeLeadingWidth
            : null,
        leading: widget.returnCookModePayload
            ? BackWithHomeLeading(back: _buildBackButton(pop: true))
            : _buildBackButton(pop: false),
        title: const Text('Fridge Clearer', style: AppDesignTokens.headline),
        centerTitle: false,
      ),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppDesignTokens.spaceMD,
              AppDesignTokens.spaceSM, AppDesignTokens.spaceMD, 140),
          children: [
            _SectionCard(
              title: 'What\'s in your fridge?',
              subtitle:
                  'Focus on perishables from your fridge. Chef Harris assumes basic pantry staples (oils, spices, pasta/rice) are available!',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final label in _quickIngredients)
                        _TapChip(
                          label: label,
                          leadingIcon: _ingredientIcons[label],
                          selected: _selectedIngredients.contains(label),
                          onTap: () => _toggleIngredient(label),
                        ),
                      for (final label in _selectedIngredients
                          .where((e) => !_quickIngredients.contains(e))
                          .toList()
                        ..sort((a, b) =>
                            a.toLowerCase().compareTo(b.toLowerCase())))
                        _TapChip(
                            label: label,
                            selected: true,
                            onTap: () => _toggleIngredient(label),
                            removable: true),
                    ],
                  ),
                  const SizedBox(height: AppDesignTokens.spaceSM),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _extraController,
                          focusNode: _extraFocusNode,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _addExtraIngredient(),
                          decoration: InputDecoration(
                            hintText:
                                'Type an ingredient (e.g., spinach, chicken)…',
                            filled: true,
                            fillColor: AppDesignTokens.surfaceCream,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                  AppDesignTokens.radiusButton),
                              borderSide: BorderSide(
                                  color: AppDesignTokens.textCharcoal
                                      .withValues(alpha: 0.12)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                  AppDesignTokens.radiusButton),
                              borderSide: BorderSide(
                                  color: AppDesignTokens.textCharcoal
                                      .withValues(alpha: 0.12)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                  AppDesignTokens.radiusButton),
                              borderSide: BorderSide(
                                  color: AppDesignTokens.ctaTerracotta
                                      .withValues(alpha: 0.75),
                                  width: 1.4),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: AppDesignTokens.spaceSM,
                                vertical: AppDesignTokens.spaceSM),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppDesignTokens.spaceXS),
                      SizedBox(
                        height: 52,
                        child: FilledButton.icon(
                          onPressed: _addExtraIngredient,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppDesignTokens.ctaTerracotta,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                    AppDesignTokens.radiusButton)),
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppDesignTokens.spaceSM),
                          ),
                          icon: const Icon(Icons.add, color: Colors.white),
                          label: const Text('Add',
                              style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppDesignTokens.spaceSM),
            _SectionCard(
              title: 'How much time do you have?',
              subtitle: 'Pick a quick time-box.',
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final p in _FridgeTimePreset.values) ...[
                      _PillOption(
                        label: _timeLabel(p),
                        leadingIcon: _timeIcon(p),
                        selected: _timePreset == p,
                        onTap: () => setState(() => _timePreset = p),
                      ),
                      if (p != _FridgeTimePreset.values.last)
                        const SizedBox(width: AppDesignTokens.spaceXS),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppDesignTokens.spaceSM),
            _SectionCard(
              title: 'What cookware are you using?',
              subtitle:
                  'Select one or more so Chef Harris can adapt the ideas.',
              child: Wrap(
                spacing: AppDesignTokens.spaceXS,
                runSpacing: AppDesignTokens.spaceXS,
                children: [
                  for (final c in _CookwarePreset.values)
                    _TapChip(
                      label: _cookwareLabel(c),
                      leadingIcon: _cookwareIcon(c),
                      selected: _cookware.contains(c),
                      onTap: () => _toggleCookware(c),
                      dense: true,
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppDesignTokens.spaceSM),
            _SectionCard(
              title: 'How many people are you cooking for?',
              subtitle:
                  'Defaults to your profile — tap to adjust just for this recipe.',
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final p in _portionOptions) ...[
                      _PillOption(
                        label: _portionLabel(p),
                        leadingIcon: Icons.people_alt_outlined,
                        selected: effectivePortions == p,
                        onTap: () => setState(() => _selectedPortions = p),
                      ),
                      if (p != _portionOptions.last)
                        const SizedBox(width: AppDesignTokens.spaceXS),
                    ],
                  ],
                ),
              ),
            ),
            if (_isGenerating) ...[
              const SizedBox(height: AppDesignTokens.spaceSM),
              const _InlineGeneratingCard(),
            ],
            if (_generationError != null) ...[
              const SizedBox(height: AppDesignTokens.spaceSM),
              _InlineErrorCard(
                  message: _generationError!, onRetry: _generateRecipe),
            ],
            if (_generatedRecipe != null) ...[
              const SizedBox(height: AppDesignTokens.spaceSM),
              GeneratedRecipeCard(
                key: _generatedRecipeKey,
                recipe: _generatedRecipe!,
                portions: effectivePortions,
                showPlanForDay: !widget.returnCookModePayload,
                onCookNow: _cookNow,
                onPlanForDay: _planForDay,
                onTryAnother: () => _generateRecipe(excludePrevious: true),
              ),
              if (_precisionCards.isNotEmpty) ...[
                const SizedBox(height: AppDesignTokens.spaceSM),
                _ScienceNotesDisclosure(
                  cards: _precisionCards,
                  expanded: _scienceNotesExpanded,
                  onToggle: () => setState(
                      () => _scienceNotesExpanded = !_scienceNotesExpanded),
                ),
              ],
            ],
          ],
        ),
      ),
      bottomNavigationBar: _generatedRecipe == null
          ? _GenerateCtaBar(
              isLoading: _isGenerating,
              onPressed: _isGenerating ? null : _generateRecipe)
          : null,
    );
  }
}

class _RecipeIdea {
  const _RecipeIdea(
      {required this.tag,
      required this.title,
      required this.prepMinutes,
      required this.cookware});
  final String tag;
  final String title;
  final int prepMinutes;
  final List<String> cookware;
}

class _SectionCard extends StatelessWidget {
  const _SectionCard(
      {required this.title, required this.subtitle, required this.child});
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppDesignTokens.surfaceCream,
      elevation: 0,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard)),
      child: Padding(
        padding: const EdgeInsets.all(AppDesignTokens.spaceMD),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: AppDesignTokens.subheadline
                    .copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(subtitle, style: AppDesignTokens.body.copyWith(height: 1.35)),
            const SizedBox(height: AppDesignTokens.spaceSM),
            child,
          ],
        ),
      ),
    );
  }
}

class _TapChip extends StatelessWidget {
  const _TapChip(
      {required this.label,
      required this.selected,
      required this.onTap,
      this.leadingIcon,
      this.removable = false,
      this.dense = false});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? leadingIcon;
  final bool removable;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final bg =
        selected ? AppDesignTokens.ctaTerracotta : AppDesignTokens.surfaceCream;
    final fg = selected ? Colors.white : AppDesignTokens.textCharcoal;

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppSizing.minTouchTarget),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
              color: AppDesignTokens.textCharcoal
                  .withValues(alpha: selected ? 0 : 0.12)),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppDesignTokens.textCharcoal.withValues(alpha: 0.10),
                    blurRadius: 14,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: InkWell(
          onTap: onTap,
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          hoverColor: Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppDesignTokens.spaceSM,
              vertical:
                  dense ? AppDesignTokens.spaceXS : AppDesignTokens.spaceSM,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (leadingIcon != null) ...[
                  Icon(leadingIcon,
                      size: 18, color: fg.withValues(alpha: 0.95)),
                  const SizedBox(width: AppDesignTokens.spaceXS),
                ],
                Flexible(
                  child: Text(
                    label,
                    style: AppDesignTokens.body
                        .copyWith(color: fg, fontWeight: FontWeight.w800),
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (removable) ...[
                  const SizedBox(width: AppDesignTokens.spaceXS),
                  Icon(Icons.close_rounded,
                      size: 18, color: fg.withValues(alpha: 0.9)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PillOption extends StatelessWidget {
  const _PillOption(
      {required this.label,
      required this.selected,
      required this.onTap,
      this.leadingIcon});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? leadingIcon;

  @override
  Widget build(BuildContext context) {
    final bg =
        selected ? AppDesignTokens.ctaTerracotta : AppDesignTokens.surfaceCream;
    final fg = selected ? Colors.white : AppDesignTokens.textCharcoal;

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppSizing.minTouchTarget),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
              color: AppDesignTokens.textCharcoal
                  .withValues(alpha: selected ? 0 : 0.12)),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppDesignTokens.textCharcoal.withValues(alpha: 0.10),
                    blurRadius: 14,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: InkWell(
          onTap: onTap,
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          hoverColor: Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppDesignTokens.spaceSM,
                vertical: AppDesignTokens.spaceSM),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (leadingIcon != null) ...[
                  Icon(leadingIcon,
                      size: 18, color: fg.withValues(alpha: 0.95)),
                  const SizedBox(width: AppDesignTokens.spaceXS),
                ],
                Text(label,
                    style: AppDesignTokens.body
                        .copyWith(color: fg, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The primary results card: shows the actual generated dish (title,
/// description, quick stats, ingredients) and the three actions available
/// once a recipe exists.
/// The Fridge Clearer's generation result.
///
/// Public (was `_GeneratedRecipeCard`) purely so the bookmark added in the
/// header row on 2026-08-21 can be covered by a widget test without pumping
/// the whole screen and its Supabase/provider dependencies. Still only
/// constructed by [_FridgeClearerScreenState].
///
/// Bookmark placement is deliberate: it sits beside the title, NOT in the
/// action row — Cook Now stays the single primary action, and the bookmark
/// keeps the same quiet treatment it has on every other mount (no label, no
/// copy, nothing to dismiss).
class GeneratedRecipeCard extends StatelessWidget {
  const GeneratedRecipeCard({
    super.key,
    required this.recipe,
    required this.portions,
    this.showPlanForDay = true,
    required this.onCookNow,
    required this.onPlanForDay,
    required this.onTryAnother,
    this.service,
  });

  final CookModeRecipePayload recipe;
  final int portions;
  final bool showPlanForDay;
  final VoidCallback onCookNow;
  final VoidCallback onPlanForDay;
  final VoidCallback onTryAnother;

  /// Injectable for tests. Defaults to the shared singleton.
  final SavedRecipesService? service;

  Widget _infoPill(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppDesignTokens.spaceSM, vertical: 6),
      decoration: BoxDecoration(
        color: AppDesignTokens.ctaTerracotta.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
            color: AppDesignTokens.ctaTerracotta.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppDesignTokens.ctaTerracotta),
          const SizedBox(width: 4),
          Text(label,
              style: AppDesignTokens.caption
                  .copyWith(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ingredientsPreview =
        recipe.ingredients.take(6).toList(growable: false);
    final overflow = recipe.ingredients.length - ingredientsPreview.length;
    final totalMinutes =
        recipe.steps.fold<int>(0, (sum, s) => sum + s.durationMinutes);
    final description = (recipe.description ?? '').trim();

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppDesignTokens.surfaceCream,
        borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard),
        border: Border.all(
            color: AppDesignTokens.textCharcoal.withValues(alpha: 0.12)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppDesignTokens.spaceMD),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(recipe.title,
                      style: AppDesignTokens.headline
                          .copyWith(fontWeight: FontWeight.w900, height: 1.15)),
                ),
                SaveRecipeBookmarkButton(recipe: recipe, service: service),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (totalMinutes > 0)
                  _infoPill('~$totalMinutes min', Icons.timelapse),
                _infoPill(portions == 1 ? '1 Person' : '$portions People',
                    Icons.people_alt_outlined),
              ],
            ),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(description,
                  style: AppDesignTokens.body.copyWith(height: 1.4)),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final ing in ingredientsPreview)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                          color: AppDesignTokens.textCharcoal
                              .withValues(alpha: 0.12)),
                    ),
                    child: Text(ing,
                        style: AppDesignTokens.caption
                            .copyWith(fontWeight: FontWeight.w800)),
                  ),
                if (overflow > 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                          color: AppDesignTokens.textCharcoal
                              .withValues(alpha: 0.12)),
                    ),
                    child: Text('+$overflow more',
                        style: AppDesignTokens.caption
                            .copyWith(fontWeight: FontWeight.w800)),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: onCookNow,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppDesignTokens.ctaTerracotta,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                                AppDesignTokens.radiusButton)),
                      ),
                      icon: Icon(
                        showPlanForDay
                            ? Icons.local_fire_department_rounded
                            : Icons.check_circle_rounded,
                        color: Colors.white,
                      ),
                      label: Text(
                        showPlanForDay ? '🔥 Cook Now' : '✅ Add to Planner',
                        style: const TextStyle(
                            fontWeight: FontWeight.w900, color: Colors.white),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppDesignTokens.spaceXS),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton(
                      onPressed: showPlanForDay ? onPlanForDay : onTryAnother,
                      style: OutlinedButton.styleFrom(
                        backgroundColor: AppDesignTokens.surfaceCream,
                        foregroundColor: AppDesignTokens.textCharcoal,
                        side: BorderSide(
                            color: AppDesignTokens.textCharcoal
                                .withValues(alpha: 0.22),
                            width: 1.2),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                                AppDesignTokens.radiusButton)),
                      ).copyWith(
                          overlayColor:
                              const WidgetStatePropertyAll(Colors.transparent)),
                      child: Text(
                        showPlanForDay ? '📅 Plan for Day' : '🔄 Generate New',
                        style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            color: AppDesignTokens.textCharcoal),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (showPlanForDay)
              Center(
                child: TextButton.icon(
                  onPressed: onTryAnother,
                  style: TextButton.styleFrom(
                    foregroundColor:
                        AppDesignTokens.textCharcoal.withValues(alpha: 0.75),
                  ).copyWith(
                      overlayColor:
                          const WidgetStatePropertyAll(Colors.transparent)),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Try Another',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Collapsible "Chef's Science Notes" section — demoted below the actual
/// recipe card, collapsed by default, matching the same disclosure pattern
/// used inside Cook Mode's per-step science notes.
class _ScienceNotesDisclosure extends StatelessWidget {
  const _ScienceNotesDisclosure(
      {required this.cards, required this.expanded, required this.onToggle});

  final List<models.CulinaryMatrixCard> cards;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppDesignTokens.surfaceCream,
      elevation: 0,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard)),
      child: Padding(
        padding: const EdgeInsets.all(AppDesignTokens.spaceMD),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: onToggle,
              splashFactory: NoSplash.splashFactory,
              highlightColor: Colors.transparent,
              hoverColor: Colors.transparent,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Chef\'s Science Notes',
                            style: AppDesignTokens.subheadline
                                .copyWith(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text(
                          'Heat cues, cut specs, timing, and Swiss-kitchen swaps — tailored to your fridge.',
                          style: AppDesignTokens.body.copyWith(height: 1.35),
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    duration: const Duration(milliseconds: 180),
                    turns: expanded ? 0.5 : 0,
                    child: const Icon(Icons.expand_more_rounded,
                        color: AppDesignTokens.textCharcoal),
                  ),
                ],
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              alignment: Alignment.topCenter,
              child: !expanded
                  ? const SizedBox.shrink()
                  : Padding(
                      padding:
                          const EdgeInsets.only(top: AppDesignTokens.spaceSM),
                      child: Column(
                        children: [
                          for (final card in cards) ...[
                            matrix_widgets.CulinaryMatrixCard(matrix: card),
                            if (card != cards.last) const SizedBox(height: 12),
                          ],
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineGeneratingCard extends StatefulWidget {
  const _InlineGeneratingCard();

  @override
  State<_InlineGeneratingCard> createState() => _InlineGeneratingCardState();
}

class _InlineGeneratingCardState extends State<_InlineGeneratingCard> {
  // Generation genuinely takes several seconds (real OpenAI completion
  // latency, see CLAUDE.md roadmap item 5) — rotating the status message
  // makes that wait feel shorter without claiming it's faster than it is.
  static const _statusMessages = [
    'Checking your ingredients…',
    'Thinking through techniques…',
    'Balancing the flavors…',
    'Plating the details…',
  ];

  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 2200), (_) {
      if (!mounted) return;
      setState(() => _index = (_index + 1) % _statusMessages.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppDesignTokens.surfaceCream,
        borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard),
        border: Border.all(
            color: AppDesignTokens.textCharcoal.withValues(alpha: 0.12)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppDesignTokens.spaceMD),
        child: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2.2, color: AppDesignTokens.ctaTerracotta),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(
                  _statusMessages[_index],
                  key: ValueKey(_index),
                  style: AppDesignTokens.body
                      .copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineErrorCard extends StatelessWidget {
  const _InlineErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppDesignTokens.surfaceCream,
        borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard),
        border: Border.all(
            color: AppDesignTokens.textCharcoal.withValues(alpha: 0.12)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppDesignTokens.spaceMD),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline_rounded,
                color: AppDesignTokens.textCharcoal.withValues(alpha: 0.8),
                size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(message,
                      style: AppDesignTokens.body.copyWith(
                          color: AppDesignTokens.textCharcoal, height: 1.25)),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton(
                      onPressed: onRetry,
                      style: OutlinedButton.styleFrom(
                        backgroundColor: AppDesignTokens.surfaceCream,
                        foregroundColor: AppDesignTokens.textCharcoal,
                        side: BorderSide(
                            color: AppDesignTokens.textCharcoal
                                .withValues(alpha: 0.22),
                            width: 1.2),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                                AppDesignTokens.radiusButton)),
                      ).copyWith(
                          overlayColor:
                              const WidgetStatePropertyAll(Colors.transparent)),
                      child: const Text('Try Again',
                          style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: AppDesignTokens.textCharcoal)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GenerateCtaBar extends StatelessWidget {
  const _GenerateCtaBar({required this.isLoading, required this.onPressed});
  final bool isLoading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    final disabled = onPressed == null;

    final bg = (isLoading || disabled)
        ? AppDesignTokens.surfaceCream
        : AppDesignTokens.ctaTerracotta;
    final fg =
        (isLoading || disabled) ? AppDesignTokens.textCharcoal : Colors.white;
    final border = BorderSide(
        color: AppDesignTokens.textCharcoal
            .withValues(alpha: (isLoading || disabled) ? 0.14 : 0));

    return Container(
      padding: EdgeInsets.fromLTRB(
          AppDesignTokens.spaceSM,
          AppDesignTokens.spaceSM,
          AppDesignTokens.spaceSM,
          AppDesignTokens.spaceSM + bottom),
      decoration: BoxDecoration(
        color: AppDesignTokens.surfaceCream,
        border: Border(
            top: BorderSide(
                color: AppDesignTokens.textCharcoal.withValues(alpha: 0.12))),
      ),
      child: SizedBox(
        height: AppSizing.primaryButtonHeight,
        child: FilledButton(
          onPressed: onPressed,
          style: ButtonStyle(
            backgroundColor: WidgetStatePropertyAll(bg),
            foregroundColor: WidgetStatePropertyAll(fg),
            shape: WidgetStatePropertyAll(RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(AppDesignTokens.radiusButton))),
            side: WidgetStatePropertyAll(border),
            overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isLoading) ...[
                const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: AppDesignTokens.ctaTerracotta)),
                const SizedBox(width: 12),
              ],
              Flexible(
                child: Text(
                  isLoading ? 'Chef Harris is thinking…' : 'Let\'s Cook',
                  style: AppDesignTokens.subheadline
                      .copyWith(color: fg, fontWeight: FontWeight.w900),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
