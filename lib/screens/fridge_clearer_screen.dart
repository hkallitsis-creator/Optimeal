import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:optimeal/nav.dart';
import 'package:optimeal/models/fridge_idea.dart';
import 'package:optimeal/prompts/recipe_static_prompts.dart';
import 'package:optimeal/models/user_profile.dart';
import 'package:optimeal/services/allergen_flag_log.dart';
import 'package:optimeal/services/allergen_guard.dart';
import 'package:optimeal/services/chef_recipe_parser.dart';
import 'package:optimeal/services/chef_service.dart';
import 'package:optimeal/services/cook_session_storage_service.dart';
import 'package:optimeal/services/entitlement_service.dart';
import 'package:optimeal/services/fridge_clearer_entry_service.dart';
import 'package:optimeal/services/fridge_nudge_service.dart';
import 'package:optimeal/services/recent_generations_service.dart';
import 'package:optimeal/services/validated_recipe_generation.dart';
import 'package:optimeal/services/usage_cap_service.dart';
import 'package:optimeal/screens/one_pan_cooking_roadmap_screen.dart';
import 'package:optimeal/state/user_profile_controller.dart';
import 'package:optimeal/theme.dart';
import 'package:optimeal/theme/app_design_tokens.dart';
import 'package:optimeal/widgets/app_bottom_sheet.dart';
import 'package:optimeal/widgets/generated_recipe_actions_sheet.dart';
import 'package:optimeal/widgets/generation_loading_card.dart';
import 'package:optimeal/widgets/home_glyph_button.dart';
import 'package:optimeal/widgets/upgrade_prompt_sheet.dart';

/// Free-tier weekly cap on Fridge Clearer AI generations (protects real
/// marginal OpenAI cost — see CLAUDE.md "Monetization / paywall tier
/// structure"). Pro users are unlimited.
///
/// Counted against **stage 1**, once per "Let's cook". Committing to an idea
/// costs a second OpenAI call but not a second unit of the user's allowance:
/// the cap exists to bound cost per user *intent*, and browsing three ideas
/// and then cooking one is a single intent. Charging twice would also punish
/// exactly the behaviour the two-stage flow is trying to encourage.
const int kFridgeClearerFreeWeeklyLimit = 3;

/// Which half of the two-stage flow the screen is showing.
///
/// Deliberately one screen with two bodies rather than two routes: the Weekly
/// Planner pushes this screen expecting a `CookModeRecipePayload` popped back
/// to it, and a second route in the middle would have to forward that contract
/// by hand. Back from [ideas] returns to [input] with every selection intact,
/// which is what makes "if all three disappoint, go back" cheap.
enum _FridgeStage { input, ideas }

enum _FridgeTimePreset { min15, min30, min45Plus }

enum _CookwarePreset { pan, onePot, ovenTray, wok, airFryer, blender }

/// Fridge Clearer — input screen + the two-stage ideas moment.
///
/// Redesigned 2026-08-22 against the signed spec card. What died: the
/// four-card scrolling interview (≈2 screens of headline + explainer paragraph
/// per question), per-chip icons, the horizontal-scrolling time and portion
/// selectors that clipped their own labels ("45+ M…", "4 …"), the inline
/// generated-recipe card, and the "Try Another" regenerate affordance —
/// choosing among three ideas replaces retrying one recipe.
///
/// What the flow is now: one no-scroll input screen → **stage 1**, one small
/// call returning three idea summaries → the user picks one → **stage 2**, the
/// full recipe generated for that idea alone. Perceived speed improves because
/// the long generation happens after commitment rather than before it.
class FridgeClearerScreen extends StatefulWidget {
  const FridgeClearerScreen({
    super.key,
    this.returnCookModePayload = false,
    this.chefService,
  });

  /// Injectable for tests. Defaults to a real [ChefService].
  ///
  /// Both stages go through `askChefHarris`, so overriding this one method in
  /// a subclass is enough to drive the whole two-stage flow with no network,
  /// no Supabase and no edge function — which is what lets the tests assert
  /// the thing that actually matters here: that stage 2 fires only after a
  /// choice, and that provenance survives the split.
  final ChefService? chefService;

  /// When true, committing to an idea `pop()`s the generated
  /// [CookModeRecipePayload] back to the caller instead of opening the actions
  /// sheet.
  ///
  /// This is the Weekly Planner's "Clear Fridge Leftovers" path. It lands on
  /// the same ideas screen as everything else; only what happens after the
  /// choice differs, because the planner is already waiting to place the
  /// result into a specific day.
  final bool returnCookModePayload;

  @override
  State<FridgeClearerScreen> createState() => _FridgeClearerScreenState();
}

class _FridgeClearerScreenState extends State<FridgeClearerScreen> {
  late final ChefService _chefService = widget.chefService ?? ChefService();
  final _extraController = TextEditingController();
  final _extraFocusNode = FocusNode();

  final Set<String> _selectedIngredients = <String>{};
  _FridgeTimePreset? _timePreset;
  final Set<_CookwarePreset> _cookware = <_CookwarePreset>{};

  /// Null means "use the value from the user's profile". Set once the user
  /// taps a portion segment to override it just for this session.
  int? _selectedPortions;

  _FridgeStage _stage = _FridgeStage.input;

  /// Stage-1 results. Non-null exactly when [_stage] is [_FridgeStage.ideas].
  List<FridgeIdea>? _ideas;

  /// True while either stage is in flight — they are never concurrent.
  bool _isGenerating = false;

  /// Which idea is currently being turned into a real recipe, so its own card
  /// can show the wait rather than a screen-wide spinner that hides the menu
  /// the user just chose from.
  int? _committingIdeaIndex;

  String? _generationError;

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

  /// Portion presets, matching the same 1/2/4/6+ options offered in onboarding.
  static const List<int> _portionOptions = [1, 2, 4, 6];

  @override
  void dispose() {
    _extraController.dispose();
    _extraFocusNode.dispose();
    super.dispose();
  }

  // ── Input state ────────────────────────────────────────────────────────

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

  String _timeLabel(_FridgeTimePreset p) => switch (p) {
        _FridgeTimePreset.min15 => '15',
        _FridgeTimePreset.min30 => '30',
        _FridgeTimePreset.min45Plus => '45+',
      };

  String _timePromptLabel(_FridgeTimePreset p) => switch (p) {
        _FridgeTimePreset.min15 => '15 minutes',
        _FridgeTimePreset.min30 => '30 minutes',
        _FridgeTimePreset.min45Plus => '45 minutes or more',
      };

  /// Short by design — the spec caps the gear row at two lines, and the old
  /// labels ("Blender/Processor", "Pan/Skillet") were what forced a third.
  String _cookwareLabel(_CookwarePreset c) => switch (c) {
        _CookwarePreset.pan => 'Pan',
        _CookwarePreset.onePot => 'One-pot',
        _CookwarePreset.ovenTray => 'Oven tray',
        _CookwarePreset.wok => 'Wok',
        _CookwarePreset.airFryer => 'Air fryer',
        _CookwarePreset.blender => 'Blender',
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

  List<String> get _sortedIngredients => _selectedIngredients.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

  String get _cookwareText => _cookware.isEmpty
      ? 'not specified'
      : (_cookware.toList()
            ..sort((a, b) => _cookwareLabel(a).compareTo(_cookwareLabel(b))))
          .map(_cookwareLabel)
          .join(', ');

  // ── Stage 1: the menu ──────────────────────────────────────────────────

  /// The per-call half of the stage-1 prompt.
  ///
  /// Everything here changes between calls, which is exactly why it is here
  /// and not in [buildFridgeIdeasStaticPrompt] — it lands AFTER the static
  /// block in the assembled message, so the static prefix stays cacheable.
  /// See `ChefService.buildUserMessage`.
  String _buildIdeasVariablePrompt(int portions) {
    final ingredients = _sortedIngredients;
    return [
      'Suggest three ways to clear this fridge.',
      '',
      'Context (Swiss home kitchen):',
      '- Ingredients the user has and wants to use up: ${ingredients.join(', ')}',
      '- Time available: ${_timePreset == null ? 'not specified' : _timePromptLabel(_timePreset!)}',
      '- Cookware/appliances available: $_cookwareText',
      '- Number of people to serve: $portions',
    ].join('\n');
  }


  /// Stage 1, with allergen-flagged ideas dropped before the user sees them.
  ///
  /// # Why dropping, and not annotating
  ///
  /// The profile block already reaches this call — and on a real run the model
  /// still offered "Cheesy Potato Skillet" and "Spinach Walnut Salad" to a
  /// profile avoiding dairy and tree nuts. Stage 2 then produced a clean
  /// recipe, so nothing unsafe was ever cooked; but the ideas screen is the
  /// menu, and putting a dish someone cannot eat on their menu is the surface
  /// working against the profile they filled in.
  ///
  /// A flagged idea is therefore **never shown**, annotated or otherwise.
  ///
  /// # The three-idea floor, and why it bends
  ///
  /// Fewer than three survivors buys exactly **one** silent regenerate, with
  /// the dropped titles added to the exclusion list so the retry does not
  /// re-offer them. If that still leaves fewer than three, the survivors are
  /// shown anyway — one good idea beats an error screen. Zero survivors is
  /// the error state, because an empty menu with no explanation reads as the
  /// app being broken.
  ///
  /// Returns null on a genuine generation/parse failure, an empty list when
  /// everything was filtered out, and otherwise whatever survived.
  Future<List<FridgeIdea>?> _generateIdeasWithAllergenFilter({
    required UserProfile profile,
    required int portions,
    required List<String> recentDishTitles,
  }) async {
    final avoided = profile.allergies;
    final dropped = <String>[];

    Future<List<FridgeIdea>?> attempt(List<String> exclusions) async {
      final reply = await _chefService.askChefHarris(
        userQuery: _buildIdeasVariablePrompt(portions),
        staticPromptBlock: buildFridgeIdeasStaticPrompt(),
        profile: profile,
        forceJsonObject: true,
        recentDishTitles: [...recentDishTitles, ...exclusions],
        surface: kChefCallSurfaceFridgeIdeas,
      );
      final parsed = parseFridgeIdeasJson(reply);
      if (parsed == null) {
        debugPrint('FridgeClearer: stage-1 reply unusable. Raw: $reply');
      }
      return parsed;
    }

    List<FridgeIdea> keepSafe(List<FridgeIdea> ideas) {
      if (avoided.isEmpty) return ideas;
      final safe = <FridgeIdea>[];
      for (final idea in ideas) {
        // Title AND the ingredients the model says the dish uses: "Cheesy
        // Potato Skillet" is caught by the title, a dish that quietly lists
        // walnuts is caught by the hints.
        final scope =
            '${idea.title} ${idea.ingredientsCleared.join(' ')}';
        final hits = allergensInIdeaText(scope, avoided);
        if (hits.isEmpty) {
          safe.add(idea);
        } else {
          dropped.add(idea.title);
          debugPrint(
              'FridgeClearer: dropped idea "${idea.title}" — $hits');
        }
      }
      return safe;
    }

    final first = await attempt(const []);
    if (first == null) return null;
    var safe = keepSafe(first);

    if (safe.length < 3 && dropped.isNotEmpty) {
      // ONE retry, silent to the user. The dropped titles ride the existing
      // exclusion mechanism rather than a new one.
      final second = await attempt(List<String>.from(dropped));
      if (second != null) {
        final extra = keepSafe(second);
        final seen = safe.map((i) => i.title.toLowerCase()).toSet();
        for (final idea in extra) {
          if (seen.add(idea.title.toLowerCase())) safe.add(idea);
          if (safe.length >= 3) break;
        }
      }
    }

    if (dropped.isNotEmpty) {
      unawaited(AllergenFlagLog.record(
        surface: kChefCallSurfaceFridgeIdeas,
        outcome: safe.isEmpty ? 'all_ideas_dropped' : 'ideas_dropped',
        details: [
          for (final title in dropped) {'idea': title},
        ],
      ));
    }

    return safe.take(3).toList(growable: false);
  }

  Future<void> _generateIdeas() async {
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

    setState(() {
      _isGenerating = true;
      _generationError = null;
      _ideas = null;
    });

    try {
      final profile = context.read<UserProfileController>().profile;
      final portions = _selectedPortions ?? profile.householdServings;

      // Usage tracking is unconditional and independent of entitlement — see
      // the constant's doc for why stage 1 is the one that counts.
      unawaited(UsageCapService.instance
          .increment(UsageFeature.fridgeClearerGeneration));

      // Variety pressure on stage 1, same list stage 2 already gets.
      //
      // Without it, back → "Let's Cook" — which is the ONLY escape from three
      // ideas you do not like, since the signed flow has no regenerate button
      // — re-ran at temperature 0.25 against a byte-identical prompt and
      // returned near-identical dishes. Measured on dev before this change:
      // two of the three ideas came back the same across a back-and-retry
      // pair. That made the signed escape path a dead end in practice.
      //
      // Passed as `recentDishTitles`, which ChefService writes into the
      // VARIABLE half of the message — after the whole static prefix, so the
      // prompt-cache ordering rule is unaffected.
      final recentCookHistory =
          await CookSessionStorageService().loadCookHistory();
      if (!mounted) return;
      final recentDishTitles = [
        ...RecentGenerationsService.instance.recent(),
        ...recentCookHistory.map((e) => e.recipe.title),
      ];

      // The stage-1 profile block is the PREVENT half: `profile:` is passed
      // here exactly as stage 2 passes it, so the allergen and diet lines
      // reach the ideas call in the same static-before-variable position.
      // That was already true and was not enough — a real run offered
      // "Cheesy Potato Skillet" and "Spinach Walnut Salad" to a profile
      // avoiding dairy and tree nuts. Hence the DETECT half below.
      final ideas = await _generateIdeasWithAllergenFilter(
        profile: profile,
        portions: portions,
        recentDishTitles: recentDishTitles,
      );
      if (!mounted) return;

      if (ideas == null) {
        setState(() => _generationError =
            'Couldn\'t come up with ideas right now. Please try again.');
        return;
      }

      // Record the ideas themselves, not just cooked dishes: the whole point
      // is that pressing back and asking again produces something new, and
      // RecentGenerationsService is in-memory so it survives exactly as long
      // as that matters.
      for (final idea in ideas) {
        RecentGenerationsService.instance.record(idea.title);
      }

      if (ideas.isEmpty) {
        // Everything the model offered contained something this user cannot
        // eat, and the one retry did not help. An empty menu with no
        // explanation reads as the app being broken, so this is the error
        // state — never an empty ideas screen, never an annotated unsafe card.
        setState(() => _generationError =
            "Couldn't find ideas that avoid your allergens. Try different ingredients.");
        return;
      }

      setState(() {
        _ideas = ideas;
        _stage = _FridgeStage.ideas;
      });
    } catch (e, st) {
      debugPrint('Fridge Clearer stage-1 generation failed: $e');
      debugPrint('$st');
      if (!mounted) return;
      setState(() => _generationError =
          'Couldn\'t come up with ideas right now. Please try again.');
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  // ── Stage 2: the real recipe, for one chosen idea ──────────────────────

  /// The per-call half of the stage-2 prompt, anchored on the chosen idea.
  String _buildRecipeVariablePrompt(FridgeIdea idea, int portions) {
    final ingredients = _sortedIngredients;
    return [
      'Create a cook-mode recipe for this specific idea: "${idea.title}".',
      '',
      'Context (Swiss home kitchen):',
      '- Ingredients available (focus on perishables): ${ingredients.join(', ')}',
      '- Assume pantry staples available: oils, salt/pepper, spices, pasta/rice.',
      '- Time available: ${_timePreset == null ? 'not specified' : _timePromptLabel(_timePreset!)}',
      '- Cookware/appliances available: $_cookwareText',
      '- Number of people this recipe should serve: $portions',
      '- Each ingredient must be a structured object with a numeric "amount" and a "unit", realistically scaled for $portions people — do not reuse the same quantity regardless of how many people are being served. Use "piece", "clove", or "slice" as the unit for whole/countable items instead of inventing a weight.',
    ].join('\n');
  }

  /// Turns one chosen idea into a real recipe, then hands it to the shared
  /// Cook / Save / Plan sheet.
  ///
  /// **All three actions act on a real recipe, never on a summary** — a saved
  /// "recipe" that turned out to be three words and a time would be a bug the
  /// user only discovers a week later. That is why generation happens on the
  /// choice rather than on the action press.
  ///
  /// Provenance is stamped exactly as the old single-stage flow stamped it:
  /// `origin` comes from the parser via [ChefRecipeSurface.fridgeClearer], and
  /// `originEnteredIngredients` is attached here because only this screen
  /// knows what the user actually entered. The two-stage split changes when
  /// the recipe is generated, never what it carries — see [RecipeOrigin].
  Future<void> _commitToIdea(int index) async {
    if (_isGenerating) return;
    final ideas = _ideas;
    if (ideas == null || index < 0 || index >= ideas.length) return;
    final idea = ideas[index];

    setState(() {
      _isGenerating = true;
      _committingIdeaIndex = index;
      _generationError = null;
    });

    try {
      final profile = context.read<UserProfileController>().profile;
      final portions = _selectedPortions ?? profile.householdServings;

      final recentCookHistory =
          await CookSessionStorageService().loadCookHistory();
      final recentDishTitles = [
        ...RecentGenerationsService.instance.recent(),
        ...recentCookHistory.map((e) => e.recipe.title),
      ];

      // The correction note is appended to the VARIABLE half, never to the
      // static block — the static block is the cached prefix, and a per-call
      // correction inside it would break caching for every recipe call.
      final variablePrompt = _buildRecipeVariablePrompt(idea, portions);
      final result = await generateValidatedRecipe(
        logSurface: kChefCallSurfaceFridgeClearer,
        avoidedAllergens: profile.allergies,
        attempt: ({String? correctionNote, required RecipeRetryKind retryKind}) =>
            _chefService.askChefHarris(
          userQuery: correctionNote == null
              ? variablePrompt
              : '$variablePrompt\n\n$correctionNote',
          staticPromptBlock: buildFridgeClearerStaticPrompt(),
          recipeTitle: idea.title,
          profile: profile,
          forceJsonObject: true,
          recentDishTitles: recentDishTitles,
          surface: switch (retryKind) {
            RecipeRetryKind.first => kChefCallSurfaceFridgeClearer,
            RecipeRetryKind.compatibility => kChefCallSurfaceFridgeClearerRetry,
            RecipeRetryKind.safety => kChefCallSurfaceFridgeClearerSafetyRetry,
            RecipeRetryKind.allergen =>
              kChefCallSurfaceFridgeClearerAllergenRetry,
          },
        ),
        parse: (raw, unknownKeys) => parseChefRecipeJson(
          raw: raw,
          portions: portions,
          fallbackTitle: idea.title,
          surface: ChefRecipeSurface.fridgeClearer,
          useGenericFallbacks: false,
          readDescription: true,
          unknownCookingTimesKeys: unknownKeys,
        ),
      );
      if (!mounted) return;

      // Fail-open: a recipe that still carries flags is served exactly like a
      // clean one, with nothing shown to the user. Only a genuine generation
      // or parse failure reaches the error card.
      var recipe = result.recipe;
      if (recipe == null) {
        debugPrint('FridgeClearer: stage-2 produced no usable recipe.');
        if (!mounted) return;
        setState(() => _generationError =
            'Couldn\'t build that recipe right now. Please try again.');
        return;
      }

      final enteredIngredients = _selectedIngredients.toList(growable: false);
      recipe = recipe.copyWith(originEnteredIngredients: enteredIngredients);

      RecentGenerationsService.instance.record(recipe.title);
      unawaited(
          FridgeNudgeService.instance.onFridgeClearerIngredientsGenerated());
      unawaited(FridgeClearerEntryService()
          .recordEnteredIngredients(enteredIngredients));

      if (!mounted) return;

      if (widget.returnCookModePayload) {
        // The Weekly Planner is waiting underneath for exactly this. Its own
        // add/persist/confirm flow takes over from here.
        context.pop(recipe);
        return;
      }

      await AppBottomSheet.show<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        backgroundColor: AppDesignTokens.surfaceIvory,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (ctx) => SafeArea(
          child: GeneratedRecipeActionsSheet(
            recipe: recipe!,
            sourceLabel: 'Clear Fridge Leftovers',
            surface: CookModeSurface.fridgeClearer,
          ),
        ),
      );
    } catch (e, st) {
      debugPrint('Fridge Clearer stage-2 generation failed: $e');
      debugPrint('$st');
      if (!mounted) return;
      setState(() => _generationError =
          'Couldn\'t build that recipe right now. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
          _committingIdeaIndex = null;
        });
      }
    }
  }

  void _backToInput() {
    setState(() {
      _stage = _FridgeStage.input;
      _ideas = null;
      _generationError = null;
    });
  }

  // ── Chrome ─────────────────────────────────────────────────────────────

  Widget _buildBackButton({required VoidCallback onPressed, String? tooltip}) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip ?? 'Back',
      icon: Container(
        padding: const EdgeInsets.all(AppDesignTokens.spaceXS),
        decoration: BoxDecoration(
          color: AppDesignTokens.surfaceIvory.withValues(alpha: 0.92),
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
    final onIdeas = _stage == _FridgeStage.ideas;

    // From the ideas stage, back always means "back to my selections" — that
    // is the whole replacement for the removed regenerate button.
    final backAction = onIdeas
        ? _backToInput
        : (widget.returnCookModePayload
            ? () => context.pop()
            : () => context.go(AppRoutes.home));

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
        leadingWidth:
            widget.returnCookModePayload ? kBackWithHomeLeadingWidth : null,
        leading: widget.returnCookModePayload
            ? BackWithHomeLeading(
                back: _buildBackButton(onPressed: backAction))
            : _buildBackButton(
                onPressed: backAction, tooltip: onIdeas ? 'Back' : 'Home'),
        title: const Text('Fridge Clearer', style: AppDesignTokens.headline),
        centerTitle: false,
      ),
      body: SafeArea(
        bottom: false,
        child: _buildBody(effectivePortions, onIdeas),
      ),
      // The CTA goes away while either stage is in flight: the loading card
      // occupies the canvas, and a disabled button under it is just something
      // else to look at.
      bottomNavigationBar: (onIdeas || _isGenerating)
          ? null
          : _GenerateCtaBar(onPressed: _generateIdeas),
    );
  }

  /// Routes between the three things this screen can be: the input, the menu,
  /// and the wait.
  ///
  /// **The wait wins over both.** Stage 1's card replaces the input; stage 2's
  /// replaces the menu — see the supersession note on [_buildIdeasBody].
  Widget _buildBody(int effectivePortions, bool onIdeas) {
    if (_isGenerating) {
      final committing = _committingIdeaIndex;
      final ideas = _ideas;
      final chosen = (committing != null && ideas != null &&
              committing < ideas.length)
          ? ideas[committing]
          : null;

      return GenerationLoadingCard(
        stage: chosen != null
            ? GenerationStage.writingRecipe
            : GenerationStage.findingIdeas,
        // Keeps the chosen dish visible while it is being written, so the
        // user does not lose hold of what they picked.
        subject: chosen?.title,
        // Ingredient-aware lines: this surface has the real entered list, so
        // the first cycling line can name it.
        ingredients: chosen == null ? null : _sortedIngredients,
      );
    }
    return onIdeas ? _buildIdeasBody() : _buildInputBody(effectivePortions);
  }

  // ── Input body: one screen, no page scroll ─────────────────────────────

  Widget _buildInputBody(int effectivePortions) {
    final typedExtras = _selectedIngredients
        .where((e) => !_quickIngredients.contains(e))
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppDesignTokens.spaceSM,
          AppDesignTokens.spaceXS, AppDesignTokens.spaceSM, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The work. Flexible so a long ingredient list eats the surplus
          // rather than pushing the settings card off screen; only the chip
          // area scrolls, never the page.
          Flexible(
            child: _FridgeCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    // PLACEHOLDER
                    'What needs using up?',
                    style: AppDesignTokens.subheadline,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    // PLACEHOLDER
                    'Pantry staples are assumed — oil, spices, pasta.',
                    style: AppDesignTokens.caption,
                  ),
                  const SizedBox(height: AppDesignTokens.spaceSM),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final label in _quickIngredients)
                            _SelectChip(
                              label: label,
                              selected: _selectedIngredients.contains(label),
                              onTap: () => _toggleIngredient(label),
                            ),
                          // Typed ingredients join the SAME wrap as removable
                          // ✕-chips — one list of what you have, not a
                          // suggestions row plus a separate "yours" row.
                          for (final label in typedExtras)
                            _SelectChip(
                              label: label,
                              selected: true,
                              removable: true,
                              onTap: () => _toggleIngredient(label),
                            ),
                        ],
                      ),
                    ),
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
                          style: AppDesignTokens.body,
                          decoration: InputDecoration(
                            isDense: true,
                            // PLACEHOLDER
                            hintText: 'Add something else…',
                            filled: true,
                            fillColor: AppDesignTokens.quietRowSurface,
                            border: _inputBorder(false),
                            enabledBorder: _inputBorder(false),
                            focusedBorder: _inputBorder(true),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppDesignTokens.spaceXS),
                      // Champagne add button — an affordance beside a field,
                      // not the screen's action. The one terracotta CTA is
                      // pinned at the bottom.
                      SizedBox(
                        height: 44,
                        width: 44,
                        child: Material(
                          color: AppDesignTokens.champagneTint,
                          borderRadius: BorderRadius.circular(
                              AppDesignTokens.radiusChip),
                          child: InkWell(
                            onTap: _addExtraIngredient,
                            borderRadius: BorderRadius.circular(
                                AppDesignTokens.radiusChip),
                            child: const Icon(Icons.add_rounded,
                                color: AppDesignTokens.terracottaOnLight),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          // ONE settings card, three rows. No headlines, no explainers — the
          // three questions that used to own a card each.
          _FridgeCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SettingsRow(
                  icon: Icons.schedule_rounded,
                  // PLACEHOLDER
                  label: 'Time',
                  child: _SegmentedRow(
                    children: [
                      for (final p in _FridgeTimePreset.values)
                        _SelectChip(
                          label: _timeLabel(p),
                          selected: _timePreset == p,
                          onTap: () => setState(() => _timePreset = p),
                          compact: true,
                        ),
                    ],
                  ),
                ),
                const _SettingsDivider(),
                _SettingsRow(
                  icon: Icons.soup_kitchen_outlined,
                  // PLACEHOLDER
                  label: 'Gear',
                  child: _SegmentedRow(
                    children: [
                      for (final c in _CookwarePreset.values)
                        _SelectChip(
                          label: _cookwareLabel(c),
                          selected: _cookware.contains(c),
                          onTap: () => _toggleCookware(c),
                          compact: true,
                        ),
                    ],
                  ),
                ),
                const _SettingsDivider(),
                _SettingsRow(
                  icon: Icons.people_alt_outlined,
                  // PLACEHOLDER
                  label: 'For',
                  child: _SegmentedRow(
                    children: [
                      for (final p in _portionOptions)
                        _SelectChip(
                          label: '$p',
                          // Silently defaults from the profile — no "defaults
                          // to your profile" explainer, the selected segment
                          // says it.
                          selected: effectivePortions == p,
                          onTap: () => setState(() => _selectedPortions = p),
                          compact: true,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_generationError != null) ...[
            const SizedBox(height: 10),
            _InlineErrorCard(
                message: _generationError!, onRetry: _generateIdeas),
          ],
        ],
      ),
    );
  }

  static OutlineInputBorder _inputBorder(bool focused) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppDesignTokens.radiusChip),
        borderSide: BorderSide(
          color: focused
              ? AppDesignTokens.ctaTerracotta.withValues(alpha: 0.75)
              : AppDesignTokens.textCharcoal.withValues(alpha: 0.12),
          width: focused ? 1.4 : 1,
        ),
      );

  // ── Ideas body: the menu ───────────────────────────────────────────────

  Widget _buildIdeasBody() {
    final ideas = _ideas ?? const <FridgeIdea>[];
    final entered = _sortedIngredients;

    return ListView(
      padding: const EdgeInsets.fromLTRB(AppDesignTokens.spaceSM, 4,
          AppDesignTokens.spaceSM, AppDesignTokens.spaceMD),
      children: [
        Text(
          // PLACEHOLDER — must name the actual ingredients, never a generic
          // "Three ways to clear it".
          'Three ways to use your ${_ideasHeaderIngredients(entered)}',
          style: AppDesignTokens.subheadline.copyWith(height: 1.25),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < ideas.length; i++) ...[
          _IdeaCard(
            idea: ideas[i],
            clearance: FridgeClearance.forIdea(ideas[i], entered),
            onTap: _isGenerating ? null : () => _commitToIdea(i),
          ),
          const SizedBox(height: 10),
        ],
        if (_generationError != null) ...[
          const SizedBox(height: 2),
          _InlineErrorCard(
            message: _generationError!,
            onRetry: _committingIdeaIndex == null
                ? _backToInput
                : () => _commitToIdea(_committingIdeaIndex!),
          ),
        ],
      ],
    );
  }

  /// Names the user's actual ingredients in the header, per the spec's
  /// insistence that it not read as a generic line. Long lists elide rather
  /// than wrapping the header to four lines.
  static String _ideasHeaderIngredients(List<String> entered) {
    final words = entered.map((e) => e.toLowerCase()).toList();
    if (words.isEmpty) return 'fridge';
    if (words.length == 1) return words.first;
    if (words.length == 2) return '${words[0]} and ${words[1]}';
    if (words.length == 3) return '${words[0]}, ${words[1]} and ${words[2]}';
    return '${words[0]}, ${words[1]} and ${words.length - 2} more';
  }
}

/// A cream card with the app's standard weight. Replaces `_SectionCard`, whose
/// whole reason to exist was a title + explainer paragraph per question.
class _FridgeCard extends StatelessWidget {
  const _FridgeCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppDesignTokens.spaceSM),
      decoration: BoxDecoration(
        color: AppDesignTokens.surfaceIvory,
        borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard),
        border: Border.all(
            color: AppDesignTokens.textCharcoal.withValues(alpha: 0.10)),
        boxShadow: AppDesignTokens.cardShadow,
      ),
      child: child,
    );
  }
}

/// One row of the settings card: icon + one-word label + the control.
class _SettingsRow extends StatelessWidget {
  const _SettingsRow(
      {required this.icon, required this.label, required this.child});

  final IconData icon;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Icon(icon,
                      size: 18,
                      color: AppDesignTokens.textCharcoal
                          .withValues(alpha: 0.60)),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppDesignTokens.caption
                            .copyWith(fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _SettingsDivider extends StatelessWidget {
  const _SettingsDivider();

  @override
  Widget build(BuildContext context) => Divider(
        height: 1,
        thickness: 1,
        color: AppDesignTokens.textCharcoal.withValues(alpha: 0.08),
      );
}

/// **Kit rule: controls wrap, never clip.**
///
/// A `Wrap`, deliberately not a horizontally scrolling `Row`. The selectors
/// this replaces clipped their own labels at common phone widths — "45+ M…",
/// "4 …" — which is the failure this rule exists to make impossible. Anything
/// that does not fit moves to the next line where it can still be read.
class _SegmentedRow extends StatelessWidget {
  const _SegmentedRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 6,
        runSpacing: 6,
        children: children,
      );
}

/// **Kit rule: selection state = champagne fill.**
///
/// Selected is a champagne fill with terracotta-on-light text; unselected is
/// the quiet row surface with a hairline. Never border-only, never icon-only —
/// both read as "nothing is selected" at a glance in a kitchen, and the old
/// terracotta-fill treatment was loud enough to compete with the actual CTA.
class _SelectChip extends StatelessWidget {
  const _SelectChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.removable = false,
    this.compact = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool removable;

  /// Settings-row density. Ingredient chips stay comfortable to hit.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? AppDesignTokens.champagneTint
          : AppDesignTokens.quietRowSurface,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        splashFactory: NoSplash.splashFactory,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? AppDesignTokens.terracottaOnLight.withValues(alpha: 0.28)
                  : AppDesignTokens.textCharcoal.withValues(alpha: 0.12),
            ),
          ),
          padding: EdgeInsets.symmetric(
              horizontal: compact ? 14 : 14, vertical: compact ? 8 : 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: AppDesignTokens.body.copyWith(
                  fontWeight: FontWeight.w500,
                  color: selected
                      ? AppDesignTokens.terracottaOnLight
                      : AppDesignTokens.textCharcoal,
                ),
              ),
              if (removable) ...[
                const SizedBox(width: 6),
                const Icon(Icons.close_rounded,
                    size: 16, color: AppDesignTokens.terracottaOnLight),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One stage-1 idea. The **clearance line is the hero** — not the title.
///
/// That inversion is the feature: the user came here to empty a fridge, so the
/// number that decides between three dishes is how much of their list each one
/// uses. The title is what the dish is called; the clearance line is why they
/// would pick it.
class _IdeaCard extends StatelessWidget {
  const _IdeaCard({
    required this.idea,
    required this.clearance,
    required this.onTap,
  });

  final FridgeIdea idea;
  final FridgeClearance clearance;

  /// Null while a recipe is being written, so a second choice cannot queue a
  /// second generation behind the first.
  final VoidCallback? onTap;

  /// Built from the user's own list, never from model prose. See
  /// [FridgeClearance].
  String get clearanceLine {
    // PLACEHOLDER (both phrasings)
    final base =
        'Clears ${clearance.clearedCount} of your ${clearance.enteredCount}';
    if (clearance.left.isEmpty) return '$base ingredients';
    final stays = clearance.left.map((e) => e.toLowerCase()).join(', ');
    // Always "stay", never "stays". Verb agreement follows the NOUN's number,
    // not the count of leftovers, and the app cannot know whether a single
    // leftover is "potatoes" (plural) or "cheese" (singular). The signed
    // example is "— potatoes stay.", and "potatoes stays" is the failure this
    // avoids; "cheese stay" is mildly odd where "potatoes stays" is wrong.
    return '$base — $stays stay.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: AppDesignTokens.surfaceIvory,
      borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard),
            border: Border.all(
                color: AppDesignTokens.textCharcoal.withValues(alpha: 0.10)),
            boxShadow: AppDesignTokens.cardShadow,
          ),
          padding: const EdgeInsets.all(AppDesignTokens.spaceSM),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(idea.title,
                        style: AppDesignTokens.subheadline
                            .copyWith(height: 1.2)),
                  ),
                  const SizedBox(width: 10),
                  if (idea.totalTimeMinutes > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '${idea.totalTimeMinutes} min',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppDesignTokens.textCharcoal
                              .withValues(alpha: 0.55),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.eco_rounded,
                      size: 18, color: AppDesignTokens.deepForest),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      clearanceLine,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1.3,
                        color: AppDesignTokens.deepForest,
                      ),
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

class _InlineErrorCard extends StatelessWidget {
  const _InlineErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppDesignTokens.surfaceIvory,
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
                        backgroundColor: AppDesignTokens.surfaceIvory,
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

/// The pinned primary CTA.
///
/// **No loading state.** It used to carry a spinner and a "Chef Harris is
/// thinking…" label; the generation loading card replaced that outright, and
/// this bar is simply removed from the tree while a stage is in flight.
class _GenerateCtaBar extends StatelessWidget {
  const _GenerateCtaBar({required this.onPressed});
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    final disabled = onPressed == null;

    final bg = disabled
        ? AppDesignTokens.surfaceIvory
        : AppDesignTokens.ctaTerracotta;
    final fg = disabled ? AppDesignTokens.textCharcoal : Colors.white;
    final border = BorderSide(
        color: AppDesignTokens.textCharcoal
            .withValues(alpha: disabled ? 0.14 : 0));

    return Container(
      padding: EdgeInsets.fromLTRB(
          AppDesignTokens.spaceSM,
          AppDesignTokens.spaceSM,
          AppDesignTokens.spaceSM,
          AppDesignTokens.spaceSM + bottom),
      decoration: BoxDecoration(
        color: AppDesignTokens.surfaceIvory,
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
          child: Center(
            child: Text(
              // PLACEHOLDER
              'Let\'s cook — clear that fridge',
              style: AppDesignTokens.subheadline
                  .copyWith(color: fg, fontWeight: FontWeight.w900),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }
}
