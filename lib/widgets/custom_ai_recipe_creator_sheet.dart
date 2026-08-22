import 'dart:async';

import 'package:optimeal/prompts/recipe_static_prompts.dart';
import 'package:optimeal/screens/one_pan_cooking_roadmap_screen.dart';
import 'package:optimeal/services/chef_recipe_parser.dart';
import 'package:optimeal/services/chef_service.dart';
import 'package:optimeal/services/cook_session_storage_service.dart';
import 'package:optimeal/services/entitlement_service.dart';
import 'package:optimeal/services/recent_generations_service.dart';
import 'package:optimeal/services/usage_cap_service.dart';
import 'package:optimeal/services/validated_recipe_generation.dart';
import 'package:optimeal/state/user_profile_controller.dart';
import 'package:optimeal/theme.dart';
import 'package:optimeal/widgets/generation_loading_card.dart';
import 'package:optimeal/widgets/upgrade_prompt_sheet.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

/// Custom AI Recipe Creator is Pro-only, with a lifetime free taste: the
/// first [kCustomAiRecipeCreatorFreeLifetimeUses] generations ever are free
/// so users experience the highest-value feature before hitting Pro — see
/// CLAUDE.md "Monetization / paywall tier structure".
const int kCustomAiRecipeCreatorFreeLifetimeUses = 2;

/// Bottom-sheet content that collects a free-form prompt and generates
/// a Cook Mode recipe via Chef Harris.
///
/// Returns a [CookModeRecipePayload] via `context.pop(payload)` on success.
class CustomAiRecipeCreatorSheet extends StatefulWidget {
  const CustomAiRecipeCreatorSheet({super.key, this.title = 'What are you in the mood for?', this.subtitle});

  final String title;
  final String? subtitle;

  @override
  State<CustomAiRecipeCreatorSheet> createState() => _CustomAiRecipeCreatorSheetState();
}

class _CustomAiRecipeCreatorSheetState extends State<CustomAiRecipeCreatorSheet> {
  final _chefService = ChefService();
  final _controller = TextEditingController();

  bool _isGenerating = false;
  String? _error;

  static const _chips = <String>['Quick Pasta', 'High Protein', 'Cozy Comfort', 'Under 20 Mins'];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _fillChip(String label) {
    final v = switch (label) {
      'Quick Pasta' => 'Quick pasta with what I have',
      'High Protein' => 'High-protein dinner idea',
      'Cozy Comfort' => 'Cozy comfort food vibe, modern + lighter',
      'Under 20 Mins' => 'Dinner under 20 minutes',
      _ => label,
    };
    _controller.text = v;
    _controller.selection = TextSelection.collapsed(offset: v.length);
    setState(() => _error = null);
  }


  /// The byte-identical half of the Custom AI Recipe Creator prompt. Sent to
  /// [ChefService.askChefHarris] as `staticPromptBlock`, deliberately NOT
  /// concatenated into the query.
  ///
  /// 2026-08-21: this text used to be the head of one combined string sent as
  /// `userQuery`, which put it behind the per-call `Recipe context:` line
  /// (here, the user's typed craving — different on essentially every call)
  /// and so outside the cacheable prefix. See
  /// [ChefService.buildUserMessage]. Wording is byte-identical to before;
  /// only where it is sent changed. Anything added here must be static.
  static String _buildStaticPrompt() => buildCustomCreatorStaticPrompt();

  /// The per-call half: the user's craving text and the portion count. Sent
  /// as `userQuery`, which lands after all static content.
  String _buildVariablePrompt(String userPrompt, int portions) {
    return [
      'Create a cook-mode recipe based on this user request:',
      '"$userPrompt"',
      '',
      'Constraints:',
      '- Swiss home kitchen assumptions (standard pan/pot, oven optional).',
      '- Be precise: specify quantities, heat levels, and timings.',
      '- Keep steps short and scannable for Cook Mode cards.',
      '- Add ONE witty Chef Harris checkpoint note somewhere in a bullet (not in the step title).',
      '- Number of people this recipe should serve: $portions',
      '- Each ingredient must be a structured object with a numeric "amount" and a "unit", realistically scaled for $portions people. Use "piece", "clove", or "slice" as the unit for whole/countable items instead of inventing a weight.',
    ].join('\n');
  }

  Future<void> _generate() async {
    final userPrompt = _controller.text.trim();
    if (userPrompt.isEmpty) {
      setState(() => _error = 'Type a dish, craving, or diet first.');
      return;
    }
    if (_isGenerating) return;

    final isPro = await EntitlementService.instance.isPro();
    if (!mounted) return;
    if (!isPro) {
      final lifetimeCount = await UsageCapService.instance.getLifetimeCount(UsageFeature.customAiRecipeCreator);
      if (!mounted) return;
      if (lifetimeCount >= kCustomAiRecipeCreatorFreeLifetimeUses) {
        await UpgradePromptSheet.show(
          context,
          title: 'Custom AI Recipe Creator is Pro',
          message:
              "You've used your $kCustomAiRecipeCreatorFreeLifetimeUses free taste${kCustomAiRecipeCreatorFreeLifetimeUses == 1 ? '' : 's'} of Custom AI Recipe Creator. "
              'Upgrade to Pro for unlimited custom recipes, built from what you actually cook.',
        );
        return;
      }
    }

    setState(() {
      _isGenerating = true;
      _error = null;
    });

    try {
      final profile = context.read<UserProfileController>().profile;
      final portions = profile.householdServings;
      final staticPrompt = _buildStaticPrompt();
      final prompt = _buildVariablePrompt(userPrompt, portions);
      // Usage tracking is unconditional and independent of entitlement
      // (CLAUDE.md roadmap item 11 follow-up, 2026-08-13) — see
      // fridge_clearer_screen.dart for the full rationale. Only the cap
      // CHECK above stays gated on isPro.
      unawaited(UsageCapService.instance.increment(UsageFeature.customAiRecipeCreator));
      // Recipe variety (CLAUDE.md roadmap item 13): title-level exclusion
      // only, deliberately no dish-format exclusion here (excludeDishFormats:
      // false below) — the user may have explicitly typed a format by name
      // ("frittata"), and format-excluding it would fight their own request.
      final recentCookHistory = await CookSessionStorageService().loadCookHistory();
      final recentDishTitles = [
        ...RecentGenerationsService.instance.recent(),
        ...recentCookHistory.map((e) => e.recipe.title),
      ];
      // The correction note rides on the VARIABLE half. `staticPrompt` is the
      // cached prefix and must stay byte-identical between the first attempt
      // and every retry — see ChefService.buildUserMessage.
      final result = await generateValidatedRecipe(
        logSurface: kChefCallSurfaceCustomCreator,
        avoidedAllergens: profile.allergies,
        attempt: ({String? correctionNote, required RecipeRetryKind retryKind}) =>
            _chefService.askChefHarris(
          userQuery: correctionNote == null ? prompt : '$prompt\n\n$correctionNote',
          staticPromptBlock: staticPrompt,
          recipeTitle: userPrompt,
          profile: profile,
          forceJsonObject: true,
          recentDishTitles: recentDishTitles,
          excludeDishFormats: false,
          surface: switch (retryKind) {
            RecipeRetryKind.first => kChefCallSurfaceCustomCreator,
            RecipeRetryKind.compatibility => kChefCallSurfaceCustomCreatorRetry,
            RecipeRetryKind.safety => kChefCallSurfaceCustomCreatorSafetyRetry,
            RecipeRetryKind.allergen =>
              kChefCallSurfaceCustomCreatorAllergenRetry,
          },
        ),
        parse: (raw, unknownKeys) => parseChefRecipeJson(
          raw: raw,
          portions: portions,
          fallbackTitle: 'Custom Recipe',
          surface: ChefRecipeSurface.customAiRecipeCreator,
          unknownCookingTimesKeys: unknownKeys,
        ),
      );
      if (!mounted) return;

      // Fail-open: a still-flagged recipe is served silently, exactly like a
      // clean one. Only a real generation or parse failure shows an error.
      final payload = result.recipe;
      if (payload == null) {
        debugPrint('CustomAiRecipeCreatorSheet: no usable recipe from the model.');
        setState(() => _error = 'Chef Harris returned something unexpected. Try again.');
        return;
      }
      RecentGenerationsService.instance.record(payload.title);

      // curriculumLessonIds is populated by the parser directly from the
      // model's own declared "curriculum_lesson_id" field now — no more
      // keyword-matching the recipe's generated text after the fact.
      debugPrint('CookModeRecipePayload constructed with curriculumLessonIds=${payload.curriculumLessonIds}');

      FocusScope.of(context).unfocus();
      context.pop(payload);
    } catch (e) {
      debugPrint('CustomAiRecipeCreatorSheet: generation failed: $e');
      if (!mounted) return;
      setState(() => _error = 'Couldn\'t generate a recipe right now. Try again in a moment.');
    } finally {
      if (!mounted) return;
      setState(() => _isGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final subtitle = widget.subtitle ?? 'Type a dish, craving, or diet — I\'ll generate a precise Cook Mode recipe.';

    // The wait takes over the whole sheet rather than sitting inside the CTA
    // as a spinner. A custom recipe is a full generation — the same 7-10s the
    // Fridge Clearer's stage 2 takes — so it gets the same card, in the same
    // mode. No ingredients are passed: this surface takes free text and has no
    // structured list to name.
    if (_isGenerating) {
      return const SizedBox(
        height: 420,
        child: GenerationLoadingCard(stage: GenerationStage.writingRecipe),
      );
    }

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
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
                    color: scheme.tertiary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: scheme.tertiary.withValues(alpha: 0.18)),
                  ),
                  child: Icon(Icons.auto_awesome_rounded, color: scheme.tertiary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.title,
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ),
                IconButton(
                  onPressed: _isGenerating ? null : () => context.pop(),
                  icon: Icon(Icons.close_rounded, color: scheme.onSurfaceVariant),
                  style: const ButtonStyle(overlayColor: WidgetStatePropertyAll(Colors.transparent)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(subtitle, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant, height: 1.35)),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.go,
              onSubmitted: (_) => _generate(),
              decoration: InputDecoration(
                hintText: 'e.g., keto rösti bowl, spicy veggie noodles, dairy-free comfort soup…',
                filled: true,
                fillColor: LightModeColors.lightWarmCreamTint,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.18))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.18))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: scheme.tertiary.withValues(alpha: 0.60), width: 1.4)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final c in _chips)
                  ActionChip(
                    onPressed: _isGenerating ? null : () => _fillChip(c),
                    label: Text(c, style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900)),
                    avatar: Icon(Icons.bolt_rounded, size: 18, color: scheme.tertiary),
                    backgroundColor: LightModeColors.lightWarmCreamTint,
                    side: BorderSide(color: scheme.outline.withValues(alpha: 0.14)),
                  ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.errorContainer.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: scheme.error.withValues(alpha: 0.22)),
                ),
                child: Text(_error!, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onErrorContainer, fontWeight: FontWeight.w800)),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: AppSizing.primaryButtonHeight,
              child: FilledButton(
                onPressed: _isGenerating ? null : _generate,
                style: FilledButton.styleFrom(
                  backgroundColor: scheme.tertiary,
                  foregroundColor: scheme.onTertiary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                ),
                child: Text(
                  '✨ Generate Recipe',
                  style: theme.textTheme.labelLarge?.copyWith(color: scheme.onTertiary, fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
