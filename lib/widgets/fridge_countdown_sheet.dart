import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:optimeal/models/recipe_model.dart';
import 'package:optimeal/screens/fridge_clearer_screen.dart' show kFridgeClearerFreeWeeklyLimit;
import 'package:optimeal/screens/one_pan_cooking_roadmap_screen.dart';
import 'package:optimeal/services/chef_service.dart';
import 'package:optimeal/services/entitlement_service.dart';
import 'package:optimeal/services/fridge_countdown_service.dart';
import 'package:optimeal/services/usage_cap_service.dart';
import 'package:optimeal/state/user_profile_controller.dart';
import 'package:optimeal/theme.dart';
import 'package:optimeal/widgets/app_bottom_sheet.dart';
import 'package:optimeal/widgets/generated_recipe_actions_sheet.dart';
import 'package:optimeal/widgets/upgrade_prompt_sheet.dart';

/// Bottom sheet listing the user's logged fridge items with a
/// decaying-freshness bar per item. Tapping "Use Tonight" on an item
/// generates one urgency-framed recipe via the shared ChefService pipeline.
///
/// See CLAUDE.md Retention Features Backlog item 1 (Fridge Countdown).
class FridgeCountdownSheet extends StatefulWidget {
  const FridgeCountdownSheet({super.key});

  @override
  State<FridgeCountdownSheet> createState() => _FridgeCountdownSheetState();
}

class _FridgeCountdownSheetState extends State<FridgeCountdownSheet> {
  final _service = FridgeCountdownService();
  final _chefService = ChefService();

  bool _loading = true;
  List<FridgeItem> _items = const [];

  /// Item id currently generating a recipe, if any — disables its row's
  /// button and shows a spinner without blocking the rest of the sheet.
  String? _generatingItemId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final items = await _service.listItems();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _addItem() async {
    final added = await AppBottomSheet.show<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => const SafeArea(child: _AddFridgeItemSheet()),
    );
    if (added == true) await _load();
  }

  Future<void> _removeItem(FridgeItem item) async {
    setState(() => _items = _items.where((i) => i.id != item.id).toList());
    try {
      await _service.removeItem(item.id);
    } catch (e) {
      debugPrint('FridgeCountdownSheet: failed to remove item: $e');
      if (!mounted) return;
      await _load();
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
        title: title.isEmpty ? 'Use it tonight' : title,
        ingredients: ingredients.isEmpty ? const ['Salt', 'Pepper', 'Cooking oil'] : ingredients,
        steps: steps,
        kitchenGear: gear.isEmpty ? const ['1 Pan or Pot', 'Knife', 'Spoon/Spatula'] : gear,
        structuredIngredients: structuredIngredients.isEmpty ? null : structuredIngredients,
        basePortions: portions,
      );
    } catch (e) {
      debugPrint('FridgeCountdownSheet: failed to parse cook-mode JSON: $e');
      return null;
    }
  }

  String _buildPrompt(FridgeItem item, int portions) {
    final urgency = item.daysRemaining <= 0
        ? '${item.ingredientName} is at (or past) its estimated freshness window — this needs to be used TODAY.'
        : '${item.ingredientName} has about ${item.daysRemaining} day(s) left before it spoils — use it very soon.';

    return [
      'Create a cook-mode recipe built around using up one specific ingredient before it spoils.',
      '',
      urgency,
      '',
      'Context (Swiss home kitchen):',
      '- Priority ingredient (must be the star of the dish, not a garnish): ${item.ingredientName}',
      '- Assume pantry staples available: oils, salt/pepper, spices, pasta/rice, plus common long-life vegetables (onion, garlic, carrot, potato).',
      '- Time available: 30-45 min',
      '- Number of people this recipe should serve: $portions',
      '',
      'Return ONLY valid JSON (no markdown, no extra text) matching this schema:',
      '{',
      '  "title": "...",',
      '  "description": "...",',
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
      '- The "description" field should be one short sentence in Chef Harris\' voice that acknowledges the urgency (e.g. rescuing it just in time) without being alarmist.',
      '- Use 4–8 steps. Provide realistic durations (1–15 minutes each).',
      '- Each ingredient must be a structured object with a numeric "amount" and a "unit", realistically scaled for $portions people.',
    ].join('\n');
  }

  Future<void> _useTonight(FridgeItem item) async {
    if (_generatingItemId != null) return;

    final isPro = await EntitlementService.instance.isPro();
    if (!mounted) return;
    if (!isPro) {
      final weeklyCount = await UsageCapService.instance.getRollingWeekCount(UsageFeature.fridgeClearerGeneration);
      if (!mounted) return;
      if (weeklyCount >= kFridgeClearerFreeWeeklyLimit) {
        await UpgradePromptSheet.show(
          context,
          title: "You've used this week's free generations",
          message:
              'Free plan includes $kFridgeClearerFreeWeeklyLimit fridge-rescue generations a week (shared with Fridge Clearer). '
              'Upgrade to Pro for unlimited generations, Custom AI Recipe Creator, and more.',
        );
        return;
      }
    }

    setState(() => _generatingItemId = item.id);
    try {
      final profile = context.read<UserProfileController>().profile;
      final portions = profile.householdServings;
      final prompt = _buildPrompt(item, portions);
      if (!isPro) {
        unawaited(UsageCapService.instance.increment(UsageFeature.fridgeClearerGeneration));
      }
      final reply = await _chefService.askChefHarris(
        userQuery: prompt,
        recipeTitle: 'Use ${item.ingredientName} tonight',
        profile: profile,
        forceJsonObject: true,
      );
      if (!mounted) return;

      final payload = _parseCookModeRecipe(reply, portions: portions);
      if (payload == null) {
        debugPrint('FridgeCountdownSheet: invalid JSON from model. Raw: $reply');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chef Harris returned something unexpected. Try again.'), behavior: SnackBarBehavior.floating),
        );
        return;
      }

      final matchedCurriculumKeys = _chefService.matchedCurriculumDrawerKeys(_buildCurriculumSearchText(payload));
      final payloadWithCurriculum = CookModeRecipePayload(
        title: payload.title,
        ingredients: payload.ingredients,
        steps: payload.steps,
        kitchenGear: payload.kitchenGear,
        description: payload.description,
        structuredIngredients: payload.structuredIngredients,
        basePortions: payload.basePortions,
        curriculumLessonIds: matchedCurriculumKeys,
      );

      if (!mounted) return;
      await AppBottomSheet.show<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (ctx) => SafeArea(child: GeneratedRecipeActionsSheet(recipe: payloadWithCurriculum, sourceLabel: 'Fridge Countdown')),
      );
    } catch (e) {
      debugPrint('FridgeCountdownSheet: generation failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't generate a recipe right now. Try again in a moment."), behavior: SnackBarBehavior.floating),
      );
    } finally {
      if (!mounted) return;
      setState(() => _generatingItemId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final expiringSoonCount = _items.where((i) => i.isExpiringSoon).length;

    return Padding(
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
                  color: scheme.tertiary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: scheme.tertiary.withValues(alpha: 0.18)),
                ),
                child: Icon(Icons.hourglass_bottom_rounded, color: scheme.tertiary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Fridge Countdown', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
              ),
              IconButton(
                onPressed: () => context.pop(),
                icon: Icon(Icons.close_rounded, color: scheme.onSurfaceVariant),
                style: const ButtonStyle(overlayColor: WidgetStatePropertyAll(Colors.transparent)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _items.isEmpty
                ? 'Log what\'s in your fridge and get a nudge before it spoils.'
                : expiringSoonCount == 0
                    ? 'Everything logged is holding up fine — nothing urgent right now.'
                    : '$expiringSoonCount item${expiringSoonCount == 1 ? '' : 's'} need${expiringSoonCount == 1 ? 's' : ''} using up soon.',
            style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
            )
          else if (_items.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: scheme.outline.withValues(alpha: 0.14)),
              ),
              child: Text(
                'Nothing logged yet. Add an item below whenever you put something fresh in the fridge.',
                style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 400),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final item = _items[i];
                  return _FridgeItemRow(
                    item: item,
                    isGenerating: _generatingItemId == item.id,
                    onUseTonight: () => _useTonight(item),
                    onRemove: () => _removeItem(item),
                  );
                },
              ),
            ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: AppSizing.primaryButtonHeight,
            child: OutlinedButton.icon(
              onPressed: _addItem,
              style: OutlinedButton.styleFrom(
                backgroundColor: scheme.surface,
                foregroundColor: scheme.tertiary,
                side: BorderSide(color: scheme.tertiary.withValues(alpha: 0.85), width: 1.2),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ).copyWith(overlayColor: const WidgetStatePropertyAll(Colors.transparent)),
              icon: Icon(Icons.add_rounded, color: scheme.tertiary),
              label: Text('Add fridge item', style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900, color: scheme.tertiary)),
            ),
          ),
        ],
      ),
    );
  }
}

class _FridgeItemRow extends StatelessWidget {
  const _FridgeItemRow({required this.item, required this.isGenerating, required this.onUseTonight, required this.onRemove});

  final FridgeItem item;
  final bool isGenerating;
  final VoidCallback onUseTonight;
  final VoidCallback onRemove;

  /// Semantic urgency colors — deliberately separate from the app's brand
  /// accent, since these encode a real freshness state, not a UI theme.
  Color _urgencyColor(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (item.daysRemaining <= 0) return scheme.error;
    if (item.daysRemaining <= 2) return const Color(0xFFB8863B); // amber
    return const Color(0xFF3E7A4C); // green
  }

  String _daysLabel() {
    final d = item.daysRemaining;
    if (d < 0) return '${-d}d overdue';
    if (d == 0) return 'Use today';
    if (d == 1) return '1 day left';
    return '$d days left';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final urgency = _urgencyColor(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.14)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.ingredientName,
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(_daysLabel(), style: theme.textTheme.labelMedium?.copyWith(color: urgency, fontWeight: FontWeight.w800)),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: item.spoilageRatio,
                    minHeight: 6,
                    backgroundColor: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                    valueColor: AlwaysStoppedAnimation(urgency),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 36,
                        child: FilledButton(
                          onPressed: isGenerating ? null : onUseTonight,
                          style: FilledButton.styleFrom(
                            backgroundColor: scheme.tertiary,
                            foregroundColor: scheme.onTertiary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: EdgeInsets.zero,
                          ),
                          child: isGenerating
                              ? SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2.2, color: scheme.onTertiary))
                              : Text('Use Tonight', style: theme.textTheme.labelMedium?.copyWith(color: scheme.onTertiary, fontWeight: FontWeight.w900)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: isGenerating ? null : onRemove,
                      icon: Icon(Icons.delete_outline_rounded, size: 20, color: scheme.onSurfaceVariant),
                      style: const ButtonStyle(overlayColor: WidgetStatePropertyAll(Colors.transparent)),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AddFridgeItemSheet extends StatefulWidget {
  const _AddFridgeItemSheet();

  @override
  State<_AddFridgeItemSheet> createState() => _AddFridgeItemSheetState();
}

class _AddFridgeItemSheetState extends State<_AddFridgeItemSheet> {
  final _controller = TextEditingController();
  final _service = FridgeCountdownService();
  int _shelfLifeDays = 5;
  bool _shelfLifeTouchedManually = false;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onNameChanged(String value) {
    if (_shelfLifeTouchedManually) return;
    setState(() => _shelfLifeDays = FridgeCountdownService.estimateShelfLifeDays(value));
  }

  Future<void> _save() async {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await _service.addItem(ingredientName: name, shelfLifeDays: _shelfLifeDays);
      if (!mounted) return;
      context.pop(true);
    } catch (e) {
      debugPrint('_AddFridgeItemSheet: failed to add item: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't save that item. Try again."), behavior: SnackBarBehavior.floating),
      );
      setState(() => _saving = false);
    }
  }

  static const _quickPicks = <int>[2, 4, 7, 14, 30];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

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
                Expanded(
                  child: Text('Add a fridge item', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                ),
                IconButton(
                  onPressed: _saving ? null : () => context.pop(),
                  icon: Icon(Icons.close_rounded, color: scheme.onSurfaceVariant),
                  style: const ButtonStyle(overlayColor: WidgetStatePropertyAll(Colors.transparent)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onChanged: _onNameChanged,
              onSubmitted: (_) => _save(),
              decoration: InputDecoration(
                hintText: 'e.g., spinach, chicken thigh, leftover soup…',
                filled: true,
                fillColor: LightModeColors.lightWarmCreamTint,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.18))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.18))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: scheme.tertiary.withValues(alpha: 0.60), width: 1.4)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              ),
            ),
            const SizedBox(height: 14),
            Text('Estimated shelf life', style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final days in _quickPicks)
                  ChoiceChip(
                    label: Text('$days ${days == 1 ? 'day' : 'days'}'),
                    selected: _shelfLifeDays == days,
                    onSelected: (_) => setState(() {
                      _shelfLifeDays = days;
                      _shelfLifeTouchedManually = true;
                    }),
                    labelStyle: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: _shelfLifeDays == days ? scheme.onTertiary : scheme.onSurfaceVariant,
                    ),
                    selectedColor: scheme.tertiary,
                    backgroundColor: LightModeColors.lightWarmCreamTint,
                    side: BorderSide(color: scheme.outline.withValues(alpha: 0.14)),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: AppSizing.primaryButtonHeight,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: scheme.tertiary,
                  foregroundColor: scheme.onTertiary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                ),
                child: _saving
                    ? SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2.4, color: scheme.onTertiary))
                    : Text('Add to fridge', style: theme.textTheme.labelLarge?.copyWith(color: scheme.onTertiary, fontWeight: FontWeight.w900)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
