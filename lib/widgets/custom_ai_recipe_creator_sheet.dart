import 'dart:async';

import 'package:optimeal/models/recipe_model.dart';
import 'package:optimeal/screens/one_pan_cooking_roadmap_screen.dart';
import 'package:optimeal/services/chef_recipe_parser.dart';
import 'package:optimeal/services/chef_service.dart';
import 'package:optimeal/services/cook_session_storage_service.dart';
import 'package:optimeal/services/entitlement_service.dart';
import 'package:optimeal/services/recent_generations_service.dart';
import 'package:optimeal/services/usage_cap_service.dart';
import 'package:optimeal/state/user_profile_controller.dart';
import 'package:optimeal/theme.dart';
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


  String _buildPrompt(String userPrompt, int portions) {
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
      '',
      'Return ONLY valid JSON (no markdown, no extra text) matching this schema:',
      '{',
      '  "title": "...",',
      '  "curriculum_lesson_id": "...",',
      '  "ingredients": [',
      '    {"name": "...", "amount": 0, "unit": "g|ml|tbsp|tsp|piece|clove|slice", "cut": "${ingredientCutVocabulary.join('|')}"}',
      '  ],',
      '  "kitchen_gear": ["..."],',
      '  "steps": [',
      '    {',
      '      "title": "...",',
      '      "duration_minutes": 0,',
      '      "heat": "low|medium|medium_high|off_heat",',
      '      "ingredients_added": ["..."],',
      '      "bullets": ["..."]',
      '    }',
      '  ]',
      '}',
      '',
      'Guidelines:',
      '- Use 4–9 steps. Each step duration 1–15 minutes.',
      '- Heat must be one of the allowed values (default "medium").',
      '- Each ingredient must be a structured object with a numeric "amount" and a "unit", realistically scaled for $portions people. Use "piece", "clove", or "slice" as the unit for whole/countable items instead of inventing a weight.',
      '- Each ingredient\'s "cut" field must be exactly one of: ${ingredientCutVocabulary.join(', ')}. This is a closed set — do not write a free-text cut description in this field, and do not invent a value outside this list. Use "none" if the ingredient needs no cutting. Step bullets may still describe the cut in your own voice; the "cut" field is the structured record of it.',
      '- SEQUENCING RULE (non-negotiable): each step\'s "ingredients_added" field must list every ingredient that step actually adds to the pan/pot, using the exact "name" values from the ingredients list above. If the ingredients in "ingredients_added" do not have comparable cook times, you may not add them at the same moment. Either stagger them within the step — the bullets must state exactly what goes in first, how many minutes it cooks alone, and when each remaining ingredient joins — or split them across separate steps instead. WHAT NOT TO DO: do not write a step like "thinly slice potatoes and onions, then cook together" — thinly sliced onion softens in a few minutes while thinly sliced potato needs several minutes longer to cook through, so the onion will burn or turn bitter well before the potato is done. Instead, add the potato first and give it a real head start before the onion joins, or cook them as two separate steps.',
      '- The "curriculum_lesson_id" field is required and must name the ONE curriculum technique or topic this recipe actually teaches, chosen exactly from this list: ${ChefService.curriculumDrawerKeys.join(', ')}. Base the choice on what the steps physically do, not the dish\'s theme, name, or ingredients — a recipe built from fridge leftovers is not "food_storage" just because using up leftovers is this app\'s whole point; if the steps sauté something, the answer is "sauteing"; if they braise, it\'s "braising"; and so on. Choose the single best match for the technique actually demonstrated.',
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
      final prompt = _buildPrompt(userPrompt, portions);
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
      final reply = await _chefService.askChefHarris(
        userQuery: prompt,
        recipeTitle: userPrompt,
        profile: profile,
        forceJsonObject: true,
        recentDishTitles: recentDishTitles,
        excludeDishFormats: false,
      );
      if (!mounted) return;
      final payload = await parseChefRecipeJson(
        raw: reply,
        portions: portions,
        fallbackTitle: 'Custom Recipe',
        surface: ChefRecipeSurface.customAiRecipeCreator,
      );
      if (!mounted) return;
      if (payload == null) {
        debugPrint('CustomAiRecipeCreatorSheet: invalid JSON from model. Raw: $reply');
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
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  child: _isGenerating
                      ? Row(
                          key: const ValueKey('loading'),
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2.4, color: scheme.onTertiary)),
                            const SizedBox(width: 12),
                            Text('Generating…', style: theme.textTheme.labelLarge?.copyWith(color: scheme.onTertiary, fontWeight: FontWeight.w900)),
                          ],
                        )
                      : Text(
                          '✨ Generate Recipe',
                          key: const ValueKey('cta'),
                          style: theme.textTheme.labelLarge?.copyWith(color: scheme.onTertiary, fontWeight: FontWeight.w900),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}