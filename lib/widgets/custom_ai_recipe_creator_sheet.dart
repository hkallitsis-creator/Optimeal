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
import 'package:optimeal/theme/app_design_tokens.dart';
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

  final _focusNode = FocusNode();

  bool _isGenerating = false;
  String? _error;

  /// Which quick-fill chip wrote the current field text, if any. Cleared the
  /// moment the user edits — the chip stops claiming text it no longer owns.
  String? _activeChip;

  static const _chips = <String>['Quick Pasta', 'High Protein', 'Cozy Comfort', 'Under 20 Mins'];

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
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
    setState(() {
      _error = null;
      _activeChip = label;
    });
    _focusNode.requestFocus();
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
          maxTokens: kRecipeGenerationMaxTokens,
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

    // The wait takes over the whole sheet IN PLACE — no route push, no second
    // sheet. A custom recipe is a full generation, the same 7-10s the Fridge
    // Clearer's stage 2 takes, so it gets the same card in the same mode.
    //
    // The typed craving is the subject line, per the signed stage-2 pattern:
    // the user should see their own words while they wait, not a generic
    // "writing your recipe".
    if (_isGenerating) {
      return SizedBox(
        height: 420,
        child: GenerationLoadingCard(
          stage: GenerationStage.writingRecipe,
          subject: _controller.text.trim().isEmpty
              ? null
              : _controller.text.trim(),
        ),
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
            // 1 — title alone. The sparkle chip that used to sit beside it is
            // gone; so is the explainer paragraph under it, which the field's
            // placeholder now carries.
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ),
                IconButton(
                  onPressed: () => context.pop(),
                  icon: Icon(Icons.close_rounded,
                      color: AppDesignTokens.textCharcoal
                          .withValues(alpha: 0.60)),
                  style: const ButtonStyle(
                      overlayColor: WidgetStatePropertyAll(Colors.transparent)),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 2 — one quiet field, one line. A craving is a phrase, not an
            // essay; the old four-line textarea invited a paragraph.
            SizedBox(
              height: 52,
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                maxLines: 1,
                textInputAction: TextInputAction.go,
                onSubmitted: (_) => _generate(),
                onChanged: (_) {
                  // Editing after a chip fill means the text is the user's
                  // now, so the chip stops claiming it.
                  if (_activeChip != null) setState(() => _activeChip = null);
                  if (_error != null) setState(() => _error = null);
                },
                decoration: InputDecoration(
                  // SIGNED-CONTENT PLACEHOLDER
                  hintText: 'Any dish, craving, or diet…',
                  filled: true,
                  fillColor: AppDesignTokens.quietRowSurface,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(
                          color: AppDesignTokens.textCharcoal
                              .withValues(alpha: 0.14))),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(
                          color: AppDesignTokens.textCharcoal
                              .withValues(alpha: 0.14))),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(
                          color: AppDesignTokens.ctaTerracotta
                              .withValues(alpha: 0.55),
                          width: 1.4)),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // 3 — quick fills. Tapping one WRITES INTO the field; it is not a
            // filter and not a submit, and the text stays editable.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in _chips)
                  _QuickFillChip(
                    label: c,
                    selected: _activeChip == c,
                    onTap: () => _fillChip(c),
                  ),
              ],
            ),

            if (_error != null) ...[
              const SizedBox(height: 14),
              _CreatorErrorCard(message: _error!),
            ],

            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: AppSizing.primaryButtonHeight,
              child: FilledButton(
                onPressed: _generate,
                style: FilledButton.styleFrom(
                  backgroundColor: AppDesignTokens.ctaTerracotta,
                  foregroundColor: scheme.onTertiary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18)),
                ),
                child: Text(
                  // SIGNED-CONTENT PLACEHOLDER. No emoji — emoji in a CTA is
                  // a kit violation, and there is a guard test on it now.
                  _error == null ? 'Generate recipe' : 'Try again',
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

/// A quick fill, not a filter. Champagne while the field still holds exactly
/// what this chip wrote; quiet the moment the user edits it.
class _QuickFillChip extends StatelessWidget {
  const _QuickFillChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected
          ? AppDesignTokens.champagneTint
          : AppDesignTokens.quietRowSurface,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: selected
                ? null
                : Border.all(
                    color:
                        AppDesignTokens.textCharcoal.withValues(alpha: 0.14)),
          ),
          child: Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected
                  ? AppDesignTokens.terracottaOnLight
                  : AppDesignTokens.textCharcoal.withValues(alpha: 0.80),
            ),
          ),
        ),
      ),
    );
  }
}

/// The failure state: a quiet card, not a red alarm. The retry is the sheet's
/// existing terracotta CTA relabelled, so there is still exactly one, and the
/// typed text is untouched underneath.
class _CreatorErrorCard extends StatelessWidget {
  const _CreatorErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppDesignTokens.quietRowSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: AppDesignTokens.textCharcoal.withValues(alpha: 0.12)),
      ),
      child: Text(
        message,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: AppDesignTokens.textCharcoal.withValues(alpha: 0.80),
          height: 1.35,
        ),
      ),
    );
  }
}
