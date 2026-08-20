import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:optimeal/nav.dart';
import 'package:optimeal/screens/one_pan_cooking_roadmap_screen.dart';
import 'package:optimeal/services/cook_session_storage_service.dart';
import 'package:optimeal/services/saved_recipes_service.dart';
import 'package:optimeal/services/weekly_planner_intent_service.dart';
import 'package:optimeal/theme/app_design_tokens.dart';
import 'package:optimeal/widgets/app_bottom_sheet.dart';
import 'package:optimeal/widgets/recipe_provenance_badges.dart';
import 'package:optimeal/widgets/save_recipe_bookmark_button.dart';
import 'package:optimeal/widgets/weekday_picker_sheet.dart';

/// My recipes — the shelf.
///
/// Two sections, and the difference between them is **card weight**, not a
/// label: Saved recipes are full cream cards with visual gravity; Recently
/// Cooked is a quiet log of lighter rows underneath. A saved recipe is
/// something the user chose; a cooked one is just something that happened.
///
/// This screen MAY scroll — the no-scroll rule is Home's alone.
///
/// Depth-1 (opened straight off the Home hub): back button only, and back
/// lands on Home. No home glyph.
class MyRecipesScreen extends StatefulWidget {
  const MyRecipesScreen({super.key, this.service});

  /// Injectable for tests. Defaults to the shared singleton so bookmark state
  /// stays consistent with every other surface.
  ///
  /// Cook history is NOT injected separately: it is reached through
  /// [SavedRecipesService.recentlyCooked] / [SavedRecipesService.timesCooked],
  /// which already own that dependency. A second seam here would let the two
  /// disagree about which history they are reading.
  final SavedRecipesService? service;

  @override
  State<MyRecipesScreen> createState() => _MyRecipesScreenState();
}

class _MyRecipesScreenState extends State<MyRecipesScreen> {
  SavedRecipesService get _service =>
      widget.service ?? SavedRecipesService.instance;

  List<RecentlyCookedEntry> _recentlyCooked = const [];

  /// Derived at read time from the cook history — deliberately not stored on
  /// `saved_recipes`. Keyed by recipe key.
  Map<String, int> _timesCookedByKey = const {};

  /// Held here, not created in `build`: [SavedRecipesService.watchSavedRecipes]
  /// returns a NEW stream per call, so subscribing from `build` would
  /// resubscribe on every emission and spin forever.
  late final Stream<List<SavedRecipe>> _savedStream;

  @override
  void initState() {
    super.initState();
    _savedStream = _service.watchSavedRecipes();
    _loadDerived();
  }

  Future<void> _loadDerived() async {
    final recent = await _service.recentlyCooked();
    final counts = <String, int>{};
    for (final entry in recent) {
      final key = SavedRecipesService.recipeKeyFor(entry.recipe.title);
      counts[key] = await _service.timesCooked(key);
    }
    if (!mounted) return;
    setState(() {
      _recentlyCooked = recent;
      _timesCookedByKey = counts;
    });
  }

  void _openDetails(CookModeRecipePayload recipe) {
    context.push(AppRoutes.recipe, extra: recipe);
  }

  /// Schedules a saved recipe via the EXISTING weekday picker sheet — the
  /// same one Fridge Clearer uses — then hands off through
  /// [WeeklyPlannerIntentService], exactly as that flow already does.
  Future<void> _scheduleToDay(CookModeRecipePayload recipe) async {
    final dayIndex = await AppBottomSheet.show<int>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppDesignTokens.surfaceCream,
      builder: (ctx) => const SafeArea(
        // SIGNED-CONTENT PLACEHOLDER
        child: WeekdayPickerSheet(title: 'Plan for which day?'),
      ),
    );
    if (dayIndex == null || !mounted) return;

    WeeklyPlannerIntentService.instance.queueAddMeal(
      dayIndex: dayIndex,
      recipe: recipe,
      // SIGNED-CONTENT PLACEHOLDER — also the marker the planner reads to
      // decide whether to show the "from saved" chip on the placed row.
      source: kFromSavedMealSource,
    );
    if (!mounted) return;
    context.push(AppRoutes.weeklyPlan);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppDesignTokens.backgroundSage,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => context.go(AppRoutes.home),
          tooltip: 'Home',
          icon: Container(
            padding: const EdgeInsets.all(AppDesignTokens.spaceXS),
            decoration: BoxDecoration(
              color: AppDesignTokens.surfaceCream.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(AppDesignTokens.radiusChip),
              border: Border.all(
                  color: AppDesignTokens.textCharcoal.withValues(alpha: 0.12)),
            ),
            child: const Icon(Icons.arrow_back,
                color: AppDesignTokens.textCharcoal),
          ),
        ),
        // SIGNED-CONTENT PLACEHOLDER
        title: const Text('My recipes', style: AppDesignTokens.headline),
        centerTitle: false,
      ),
      body: SafeArea(
        top: false,
        child: StreamBuilder<List<SavedRecipe>>(
          stream: _savedStream,
          builder: (context, snapshot) {
            // Service order is already last_touched_at desc — never re-sort
            // here, or the two would drift.
            final saved = snapshot.data ?? const <SavedRecipe>[];
            final hasAnything = saved.isNotEmpty || _recentlyCooked.isNotEmpty;

            if (!hasAnything) return const _MyRecipesEmptyState();

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
              children: [
                if (saved.isEmpty)
                  const _SavedEmptyInline()
                else
                  ...saved.map(
                    (s) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _SavedRecipeCard(
                        saved: s,
                        timesCooked: _timesCookedByKey[s.recipeKey] ?? 0,
                        service: _service,
                        onTap: () => _openDetails(s.recipe),
                        onSchedule: () => _scheduleToDay(s.recipe),
                      ),
                    ),
                  ),
                if (_recentlyCooked.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const _SectionLabel(
                    // SIGNED-CONTENT PLACEHOLDER
                    label: 'Recently cooked',
                  ),
                  const SizedBox(height: 8),
                  ..._recentlyCooked.map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: _RecentlyCookedRow(
                        entry: e,
                        service: _service,
                        onTap: () => _openDetails(e.recipe),
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

/// A quiet section divider for the log below the saved cards. Deliberately
/// small: the weight difference between cards and rows is what separates the
/// two sections; this only names the second one.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      label,
      style: theme.textTheme.labelMedium?.copyWith(
        color: AppDesignTokens.deepForest.withValues(alpha: 0.75),
        fontWeight: FontWeight.w900,
        letterSpacing: 0.4,
      ),
    );
  }
}

/// SAVED — a full cream card. This is the section with visual gravity.
///
/// No prose: name, provenance badge (Fridge Clearer origin only), and one
/// small state line that is either a cook count or the not-yet-cooked marker.
class _SavedRecipeCard extends StatelessWidget {
  const _SavedRecipeCard({
    required this.saved,
    required this.timesCooked,
    required this.service,
    required this.onTap,
    required this.onSchedule,
  });

  final SavedRecipe saved;
  final int timesCooked;
  final SavedRecipesService service;
  final VoidCallback onTap;
  final VoidCallback onSchedule;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: AppDesignTokens.surfaceCream,
      borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 6, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard),
            border: Border.all(
                color: AppDesignTokens.deepForest.withValues(alpha: 0.10)),
            boxShadow: AppDesignTokens.cardShadow,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      saved.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        height: 1.15,
                        color: AppDesignTokens.deepForest,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (saved.isFridgeRescue) const ProvenanceLeafBadge(),
                        // Nothing at all when the count is zero — no "0 times".
                        // A saved-but-never-cooked recipe gets its own quiet
                        // marker instead.
                        if (timesCooked > 0)
                          Text(
                            // SIGNED-CONTENT PLACEHOLDER
                            'Cooked $timesCooked${timesCooked == 1 ? ' time' : ' times'}',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: AppDesignTokens.textCharcoal
                                  .withValues(alpha: 0.70),
                              fontWeight: FontWeight.w700,
                            ),
                          )
                        else
                          Text(
                            // SIGNED-CONTENT PLACEHOLDER
                            'Not cooked yet',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: AppDesignTokens.textCharcoal
                                  .withValues(alpha: 0.55),
                              fontWeight: FontWeight.w700,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onSchedule,
                visualDensity: VisualDensity.compact,
                // SIGNED-CONTENT PLACEHOLDER
                tooltip: 'Plan for a day',
                icon: const Icon(Icons.calendar_month_rounded,
                    size: 22, color: AppDesignTokens.deepForest),
              ),
              SaveRecipeBookmarkButton(recipe: saved.recipe, service: service),
            ],
          ),
        ),
      ),
    );
  }
}

/// RECENTLY COOKED — a quiet row. No cream fill, no shadow, no border: this
/// is a log, and it must never compete with the saved cards above it.
class _RecentlyCookedRow extends StatelessWidget {
  const _RecentlyCookedRow({
    required this.entry,
    required this.service,
    required this.onTap,
  });

  final RecentlyCookedEntry entry;
  final SavedRecipesService service;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDesignTokens.radiusChip),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 0, 2),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  entry.recipe.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppDesignTokens.textCharcoal.withValues(alpha: 0.85),
                  ),
                ),
              ),
              // Tapping this promotes the cook into Saved. The shared
              // bookmark saves this row's stored payload, which is exactly
              // what SavedRecipesService.saveFromHistory does with a history
              // entry — origin and originEnteredIngredients ride along, so
              // the new saved card keeps its leaf badge. Using the universal
              // bookmark rather than a bespoke promote button is the point:
              // one icon, one mechanism, and because it reads the shared
              // service stream it flips to filled here and on every other
              // open surface at once.
              SaveRecipeBookmarkButton(
                recipe: entry.recipe,
                service: service,
                size: 20,
                color: AppDesignTokens.textCharcoal.withValues(alpha: 0.70),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown above the log when there are cooks but nothing saved yet — a nudge
/// in place of the cards, not the full-screen empty state.
class _SavedEmptyInline extends StatelessWidget {
  const _SavedEmptyInline();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppDesignTokens.surfaceCream.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard),
        border: Border.all(
            color: AppDesignTokens.deepForest.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.bookmark_border_rounded,
              size: 26,
              color: AppDesignTokens.deepForest.withValues(alpha: 0.65)),
          const SizedBox(height: 10),
          Text(
            'Nothing saved yet.', // SIGNED-CONTENT PLACEHOLDER
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: AppDesignTokens.deepForest,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            // SIGNED-CONTENT PLACEHOLDER
            'Tap the bookmark on anything below to keep it.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppDesignTokens.textCharcoal.withValues(alpha: 0.70),
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

/// The full-screen empty state: nothing saved AND nothing cooked. This is
/// every tester's first impression of the screen, so it is a designed state,
/// not a bare string — a large bookmark glyph on the sage ground, two short
/// lines, generous breathing room, and no dead-end CTA pretending there is
/// something to do here.
class _MyRecipesEmptyState extends StatelessWidget {
  const _MyRecipesEmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 96,
              width: 96,
              decoration: BoxDecoration(
                color: AppDesignTokens.surfaceCream.withValues(alpha: 0.70),
                shape: BoxShape.circle,
                border: Border.all(
                    color: AppDesignTokens.deepForest.withValues(alpha: 0.14)),
              ),
              child: Icon(
                Icons.bookmark_border_rounded,
                size: 44,
                color: AppDesignTokens.deepForest.withValues(alpha: 0.70),
              ),
            ),
            const SizedBox(height: AppDesignTokens.spaceMD),
            Text(
              'Your shelf is empty.', // SIGNED-CONTENT PLACEHOLDER
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
                color: AppDesignTokens.deepForest,
                height: 1.2,
              ),
            ),
            const SizedBox(height: AppDesignTokens.spaceXS),
            Text(
              // SIGNED-CONTENT PLACEHOLDER
              'Recipes you bookmark or cook will land here.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppDesignTokens.textCharcoal.withValues(alpha: 0.72),
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
