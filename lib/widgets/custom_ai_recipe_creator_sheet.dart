import 'dart:async';
import 'dart:convert';

import 'package:optimeal/models/recipe_model.dart';
import 'package:optimeal/screens/one_pan_cooking_roadmap_screen.dart';
import 'package:optimeal/services/chef_service.dart';
import 'package:optimeal/services/entitlement_service.dart';
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

  String _extractJsonObject(String raw) {
    final t = raw.trim();
    final start = t.indexOf('{');
    final end = t.lastIndexOf('}');
    if (start == -1 || end == -1 || end <= start) return t;
    return t.substring(start, end + 1);
  }

  String _formatIngredientAmount(double amount) {
    if (amount == amount.roundToDouble()) return amount.toInt().toString();
    return amount.toStringAsFixed(1);
  }

  CookModeRecipePayload? _parseCookModeRecipe(String raw, {required int portions}) {
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
            final amount = (m['amount'] is num)
                ? (m['amount'] as num).toDouble()
                : double.tryParse('${m['amount'] ?? ''}'.trim()) ?? 0;
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
        title: title.isEmpty ? 'Custom Recipe' : title,
        ingredients: ingredients.isEmpty ? const ['Salt', 'Pepper', 'Cooking oil'] : ingredients,
        steps: steps,
        kitchenGear: gear.isEmpty ? const ['1 Pan or Pot', 'Knife', 'Spoon/Spatula'] : gear,
        structuredIngredients: structuredIngredients.isEmpty ? null : structuredIngredients,
        basePortions: portions,
        curriculumLessonIds: curriculumLessonIds,
      );
    } catch (e) {
      debugPrint('CustomAiRecipeCreatorSheet: failed to parse cook-mode JSON: $e');
      return null;
    }
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
      '  "ingredients": [',
      '    {"name": "...", "amount": 0, "unit": "g|ml|tbsp|tsp|piece|clove|slice"}',
      '  ],',
      '  "kitchen_gear": ["..."],',
      '  "steps": [',
      '    {',
      '      "title": "...",',
      '      "duration_minutes": 0,',
      '      "heat": "low|medium|medium_high|off_heat",',
      '      "bullets": ["..."]',
      '    }',
      '  ]',
      '}',
      '',
      'Guidelines:',
      '- Use 4–9 steps. Each step duration 1–15 minutes.',
      '- Heat must be one of the allowed values (default "medium").',
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
              "You've used your $kCustomAiRecipeCreatorFreeLifetimeUses free tastes of Custom AI Recipe Creator. "
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
      if (!isPro) {
        // Counts against the lifetime free-taste allowance the moment the
        // call fires, mirroring the real OpenAI cost incurred either way.
        unawaited(UsageCapService.instance.increment(UsageFeature.customAiRecipeCreator));
      }
      final reply = await _chefService.askChefHarris(
        userQuery: prompt,
        recipeTitle: userPrompt,
        profile: profile,
        forceJsonObject: true,
      );
      if (!mounted) return;
      final payload = _parseCookModeRecipe(reply, portions: portions);
      if (payload == null) {
        debugPrint('CustomAiRecipeCreatorSheet: invalid JSON from model. Raw: $reply');
        setState(() => _error = 'Chef Harris returned something unexpected. Try again.');
        return;
      }

      final matchedCurriculumKeys = _chefService.matchedCurriculumDrawerKeys(_buildCurriculumSearchText(payload));

      final merged = <String>[];
      final seen = <String>{};
      for (final id in matchedCurriculumKeys) {
        if (seen.add(id)) merged.add(id);
      }
      for (final id in (payload.curriculumLessonIds ?? const <String>[])) {
        if (seen.add(id)) merged.add(id);
      }
      final payloadWithCurriculum = CookModeRecipePayload(
        title: payload.title,
        ingredients: payload.ingredients,
        steps: payload.steps,
        kitchenGear: payload.kitchenGear,
        description: payload.description,
        structuredIngredients: payload.structuredIngredients,
        basePortions: payload.basePortions,
        curriculumLessonIds: merged,
      );
      debugPrint('CookModeRecipePayload constructed with curriculumLessonIds=${payloadWithCurriculum.curriculumLessonIds}');

      FocusScope.of(context).unfocus();
      context.pop(payloadWithCurriculum);
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