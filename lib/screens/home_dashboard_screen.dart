import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:optimeal/nav.dart';
import 'package:optimeal/services/cook_session_storage_service.dart';
import 'package:optimeal/services/data_change_signal.dart';
import 'package:optimeal/services/ledger_service.dart';
import 'package:optimeal/services/ledger_sync_coordinator.dart';
import 'package:optimeal/screens/one_pan_cooking_roadmap_screen.dart';
import 'package:optimeal/state/user_profile_controller.dart';
import 'package:optimeal/theme/app_design_tokens.dart';
import 'package:optimeal/theme.dart';
import 'package:optimeal/widgets/app_bottom_sheet.dart';
import 'package:optimeal/widgets/custom_ai_recipe_creator_sheet.dart';
import 'package:optimeal/widgets/generated_recipe_actions_sheet.dart';
import 'package:optimeal/widgets/branded_avatar_glyph.dart';

/// The Home hub.
///
/// One screen, no scroll. Six zones, top-anchored, with exactly one flexible
/// gap (the [Spacer] before the rescue strip) absorbing all surplus height:
///
///   1. Greeting + profile avatar
///   2. Fridge Clearer hero card
///   3. Custom recipe slim row
///   4. Tile shelf — Weekly · My recipes · Techniques
///   5. Flexible gap
///   6. Rescue strip, pinned bottom
///
/// Palette is fixed: sage background, cream cards, terracotta CTAs, deep
/// forest text — all from [AppDesignTokens], no local color constants. The
/// hero and the slim row share the SAME cream: hierarchy comes from size,
/// type, and glyph scale only, never from a color break.
class HomeDashboardScreen extends StatefulWidget {
  const HomeDashboardScreen({super.key});

  static Future<void> _showCustomAiRecipeCreator(BuildContext context) async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final payload = await AppBottomSheet.show<CookModeRecipePayload>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: isDark
          ? theme.colorScheme.surface
          : LightModeColors.lightWarmCreamSurface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => const SafeArea(
        child: CustomAiRecipeCreatorSheet(
          title: 'What are you in the mood for?',
          subtitle:
              'Type any dish, craving, or diet — I\'ll generate an instant Cook Mode recipe.',
        ),
      ),
    );

    if (payload == null) return;
    if (!context.mounted) return;

    await AppBottomSheet.show<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: isDark
          ? theme.colorScheme.surface
          : LightModeColors.lightWarmCreamSurface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: GeneratedRecipeActionsSheet(
            recipe: payload,
            sourceLabel: 'Custom AI Craving',
            surface: CookModeSurface.customAiRecipeCreator),
      ),
    );
  }

  @override
  State<HomeDashboardScreen> createState() => _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends State<HomeDashboardScreen>
    with WidgetsBindingObserver, RouteAware {
  final _sessionStorage = CookSessionStorageService();
  final _ledgerService = LedgerService();

  /// Null means either "no saved session" or "not loaded yet" — both render
  /// the same way (banner hidden), so no separate loading flag is needed.
  ActiveCookSession? _activeSession;

  int _weeklyIngredientsRescued = 0;
  List<String> _weeklyIngredientsList = const [];
  int _lifetimeIngredientsRescued = 0;

  /// Write-driven invalidation. Home sits mounted underneath every cook, so
  /// both figures it shows can go stale without Home being rebuilt or
  /// re-entered — see [didPopNext] for why navigation alone cannot be the
  /// trigger.
  StreamSubscription<void>? _ledgerChangesSub;
  StreamSubscription<void>? _cookLogChangesSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ledgerChangesSub = AppDataChanges.ledger.listen(_loadWeeklyLedger);
    _cookLogChangesSub = AppDataChanges.cookLog.listen(_loadActiveSession);
    _loadActiveSession();
    _loadWeeklyLedger();
    _checkDeepLinkIntent();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(
        this, ModalRoute.of(context)! as PageRoute<dynamic>);
  }

  @override
  void dispose() {
    _ledgerChangesSub?.cancel();
    _cookLogChangesSub?.cancel();
    routeObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Fires when a route pushed on top of Home (Fridge Clearer, Cook Mode,
  /// Weekly Planner, etc.) is popped and Home becomes the top-of-stack route
  /// again. Home's own [State] is never disposed by that push/pop — it just
  /// sits underneath — so without this, nothing ever tells it a cook may have
  /// just completed. See device-test-round I1 investigation.
  ///
  /// **Secondary trigger only, and it must stay that way.** This does NOT
  /// fire for the post-cook exit: every verdict sheet leaves via
  /// `context.pop()` + `context.go('/')`, and a Navigator page that still has
  /// a modal (pageless) route attached when the page list shrinks is resolved
  /// as *complete*, not *pop* — [RouteObserver] only forwards `didPop`, so
  /// nothing reaches Home. That is what made the rescue strip stale
  /// (2026-08-22). The real refresh is the write-driven
  /// [AppDataChanges] subscriptions above; this stays because it also covers
  /// ordinary back-pops at no cost.
  @override
  void didPopNext() {
    _loadActiveSession();
    _loadWeeklyLedger();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadWeeklyLedger();
      LedgerSyncCoordinator.instance.onAppResume();
    }
  }

  /// Handles the fridge nudge notification's "AI generator" action, which
  /// lands here via AppRoutes.homeOpenAiGenerator ('/?open=ai_generator') —
  /// there's no bottom sheet to deep-link to directly, so it's opened here
  /// on first frame instead. Runs once; the query param isn't re-checked on
  /// rebuild.
  ///
  /// The [GoRouterState.of] lookup itself must stay inside the post-frame
  /// callback: it's an InheritedWidget dependency, and reading it during
  /// [initState] crashes with
  /// `dependOnInheritedWidgetOfExactType<_ModalScopeStatus>() was called
  /// before _HomeDashboardScreenState.initState() completed`.
  void _checkDeepLinkIntent() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final open = GoRouterState.of(context).uri.queryParameters['open'];
      if (open != 'ai_generator') return;
      HomeDashboardScreen._showCustomAiRecipeCreator(context);
    });
  }

  Future<void> _loadActiveSession() async {
    final session = await _sessionStorage.loadActiveSession();
    if (!mounted) return;
    setState(() => _activeSession = session);
  }

  Future<void> _discardActiveSession() async {
    await _sessionStorage.clearActiveSession();
    if (!mounted) return;
    setState(() => _activeSession = null);
  }

  Future<void> _loadWeeklyLedger() async {
    final summary = await _ledgerService.getWeeklySummary();
    if (!mounted) return;
    setState(() {
      _weeklyIngredientsRescued =
          (summary['weeklyIngredientsRescued'] as int?) ?? 0;
      _weeklyIngredientsList =
          (summary['weeklyIngredientsList'] as List?)?.cast<String>() ??
              const [];
      _lifetimeIngredientsRescued =
          (summary['lifetimeIngredientsRescued'] as int?) ?? 0;
    });
  }

  /// Resumes a saved Cook Mode session, then refreshes state on return so the
  /// Resume banner reflects whatever happened in Cook Mode (finished,
  /// discarded, or still in progress).
  Future<void> _resumeCookMode(ActiveCookSession session) async {
    await context.push(AppRoutes.onePanCookingRoadmap, extra: session);
    if (!mounted) return;
    _loadActiveSession();
    _loadWeeklyLedger();
  }

  /// The permanent Waste Ledger explainer, opened from the rescue strip's
  /// "how?" affordance. Unchanged content — this is the same sheet the old
  /// "This Week" card opened.
  Future<void> _showLedgerExplainer(BuildContext context) async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    await AppBottomSheet.show<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: isDark
          ? theme.colorScheme.surface
          : LightModeColors.lightWarmCreamSurface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) => SafeArea(
        child: _ThisWeekLedgerSheet(
          weeklyIngredients: _weeklyIngredientsList,
          weeklyCount: _weeklyIngredientsRescued,
          lifetimeCount: _lifetimeIngredientsRescued,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<UserProfileController>().profile;

    final displayName = profile.displayName.trim().isEmpty
        ? 'Chef'
        : profile.displayName.trim();
    final activeSession = _activeSession;

    return Scaffold(
      backgroundColor: AppDesignTokens.backgroundSage,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1 — Greeting
              _GreetingBlock(
                displayName: displayName,
                onProfileTap: () => context.push(AppRoutes.profile),
              ),
              const SizedBox(height: 16),

              // Resume banner is conditional and rare — it only renders when
              // a cook was left mid-session, and it is the only way back into
              // one. Fixed height, so the single Spacer below still owns all
              // surplus.
              if (activeSession != null) ...[
                _ResumeSessionBanner(
                  session: activeSession,
                  onResume: () => _resumeCookMode(activeSession),
                  onDiscard: _discardActiveSession,
                ),
                const SizedBox(height: 12),
              ],

              // 2 — Fridge Clearer hero
              _FridgeClearerHeroCard(
                onTap: () => context.push(AppRoutes.aiFridgeScrapGenerator),
              ),
              const SizedBox(height: 12),

              // 3 — Custom recipe slim row (same cream as the hero)
              _CustomRecipeSlimRow(
                onTap: () =>
                    HomeDashboardScreen._showCustomAiRecipeCreator(context),
              ),
              const SizedBox(height: 12),

              // 4 — Tile shelf. No cross-axis stretch: a Column hands its
              // non-flexible children unbounded height, and a stretching Row
              // would forward that infinity straight to the tiles. The three
              // tiles carry identical content shapes, so they match height
              // anyway.
              Row(
                children: [
                  Expanded(
                    child: _ShelfTile(
                      icon: Icons.calendar_month_rounded,
                      label: 'Weekly', // SIGNED-CONTENT PLACEHOLDER
                      onTap: () => context.push(AppRoutes.weeklyPlan),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ShelfTile(
                      icon: Icons.bookmark_border_rounded,
                      label: 'My recipes', // SIGNED-CONTENT PLACEHOLDER
                      onTap: () => context.push(AppRoutes.myRecipes),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ShelfTile(
                      icon: Icons.school_outlined,
                      label: 'Techniques', // SIGNED-CONTENT PLACEHOLDER
                      onTap: () => context.push(AppRoutes.techniques),
                    ),
                  ),
                ],
              ),

              // 5 — The one flexible gap. Nothing else on this screen flexes.
              const Spacer(),

              // 6 — Rescue strip, pinned bottom
              _RescueStrip(
                count: _weeklyIngredientsRescued,
                onHowTap: () => _showLedgerExplainer(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Zone 1 — two short greeting lines with the profile avatar at top-right.
class _GreetingBlock extends StatelessWidget {
  const _GreetingBlock({required this.displayName, required this.onProfileTap});

  final String displayName;
  final VoidCallback onProfileTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hello, $displayName.', // SIGNED-CONTENT PLACEHOLDER
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  height: 1.15,
                  color: AppDesignTokens.deepForest,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'What are we cooking?', // SIGNED-CONTENT PLACEHOLDER
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  height: 1.2,
                  color: AppDesignTokens.deepForest.withValues(alpha: 0.72),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        _ProfileAvatarButton(onTap: onProfileTap),
      ],
    );
  }
}

/// Zone 2 — the hero. Full-width cream card, oversized terracotta glyph.
class _FridgeClearerHeroCard extends StatelessWidget {
  const _FridgeClearerHeroCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return _CreamSurface(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Fridge Clearer', // SIGNED-CONTENT PLACEHOLDER
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontSize: 23,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                    color: AppDesignTokens.deepForest,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Cook what you already have.', // SIGNED-CONTENT PLACEHOLDER
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    height: 1.2,
                    color: AppDesignTokens.textCharcoal.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          const Icon(
            Icons.kitchen_rounded,
            size: 56,
            color: AppDesignTokens.ctaTerracotta,
          ),
        ],
      ),
    );
  }
}

/// Zone 3 — the quiet slim row. Same cream as the hero on purpose.
class _CustomRecipeSlimRow extends StatelessWidget {
  const _CustomRecipeSlimRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return _CreamSurface(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          const Icon(
            Icons.auto_awesome_rounded,
            size: 22,
            color: AppDesignTokens.ctaTerracotta,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              'Cook something specific', // SIGNED-CONTENT PLACEHOLDER
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppDesignTokens.deepForest,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            Icons.chevron_right_rounded,
            size: 22,
            color: AppDesignTokens.deepForest.withValues(alpha: 0.55),
          ),
        ],
      ),
    );
  }
}

/// Zone 4 — one of three equal-flex tiles. Icon + one-word label, nothing
/// else: no state text, no previews.
class _ShelfTile extends StatelessWidget {
  const _ShelfTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return _CreamSurface(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 24, color: AppDesignTokens.deepForest),
          const SizedBox(height: 8),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppDesignTokens.deepForest,
            ),
          ),
        ],
      ),
    );
  }
}

/// Zone 6 — the rescue strip. A sage panel rather than a cream card: sage
/// inside the layout carries the teaching-moment semantics, so the Waste
/// Ledger reads as the app explaining itself, not as another action.
class _RescueStrip extends StatelessWidget {
  const _RescueStrip({required this.count, required this.onHowTap});

  final int count;
  final VoidCallback onHowTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        // `sageStripOnCanvas`, not `backgroundSage`: this strip sits directly
        // on the canvas and has to separate from it. It used to fill with the
        // canvas token itself and lean entirely on its border, which worked
        // only because the two were the same colour by accident. Palette v1.2
        // gives the strip its own lighter sage — see the token, and the open
        // device item on whether the separation is now enough.
        //
        // It stays SAGE and does not become gold: a running rescue total is
        // not an earned moment.
        color: AppDesignTokens.sageStripOnCanvas,
        borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard),
        border: Border.all(
            color: AppDesignTokens.deepForest.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          const Icon(Icons.eco_outlined,
              size: 22, color: AppDesignTokens.deepForest),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              // SIGNED-CONTENT PLACEHOLDER
              '$count ingredient${count == 1 ? '' : 's'} rescued this week',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppDesignTokens.deepForest,
              ),
            ),
          ),
          TextButton(
            onPressed: onHowTap,
            style: TextButton.styleFrom(
              foregroundColor: AppDesignTokens.deepForest,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            child: Text(
              'how?', // SIGNED-CONTENT PLACEHOLDER
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                decoration: TextDecoration.underline,
                color: AppDesignTokens.deepForest,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The single cream surface used by the hero, the slim row, and the tiles.
/// One widget on purpose: dominance between them must come from size, type,
/// and glyph scale only — never from a different fill.
class _CreamSurface extends StatelessWidget {
  const _CreamSurface({
    required this.child,
    required this.onTap,
    required this.padding,
  });

  final Widget child;
  final VoidCallback onTap;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppDesignTokens.surfaceIvory,
      borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard),
            border: Border.all(
                color: AppDesignTokens.deepForest.withValues(alpha: 0.10)),
            boxShadow: AppDesignTokens.cardShadow,
          ),
          child: child,
        ),
      ),
    );
  }
}

class _ThisWeekLedgerSheet extends StatelessWidget {
  const _ThisWeekLedgerSheet(
      {required this.weeklyIngredients,
      required this.weeklyCount,
      required this.lifetimeCount});

  final List<String> weeklyIngredients;
  final int weeklyCount;
  final int lifetimeCount;

  Map<String, _IngredientTally> _tallyIngredients() {
    final map = <String, _IngredientTally>{};
    for (final raw in weeklyIngredients) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) continue;
      final key = trimmed.toLowerCase();
      final existing = map[key];
      if (existing == null) {
        map[key] = _IngredientTally(label: trimmed, count: 1);
      } else {
        map[key] =
            _IngredientTally(label: existing.label, count: existing.count + 1);
      }
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final tallied = _tallyIngredients();
    final rows = tallied.values.toList()
      ..sort((a, b) => b.count.compareTo(a.count));

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppDesignTokens.deepForest.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color:
                          AppDesignTokens.deepForest.withValues(alpha: 0.18)),
                ),
                child: const Icon(Icons.eco_rounded,
                    color: AppDesignTokens.deepForest, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                  child: Text('This Week',
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w900))),
              IconButton(
                onPressed: () => context.pop(),
                icon: Icon(Icons.close_rounded, color: scheme.onSurfaceVariant),
                style: const ButtonStyle(
                    overlayColor: WidgetStatePropertyAll(Colors.transparent)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            weeklyCount == 0
                ? 'No rescued ingredients logged yet.'
                : '$weeklyCount ingredient${weeklyCount == 1 ? '' : 's'} rescued so far this week.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          // Permanent explainer — docs/DECISIONS.md "Waste Ledger legibility
          // — option B": correct behavior was reading as inconsistent
          // because nothing in the UI explained the rules. Always visible,
          // not a tap-to-reveal.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppDesignTokens.deepForest.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: AppDesignTokens.deepForest.withValues(alpha: 0.16)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "This tracks real fridge rescues — cooking food that would've gone to waste.",
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: AppDesignTokens.deepForest,
                      fontWeight: FontWeight.w700,
                      height: 1.35),
                ),
                const SizedBox(height: 4),
                // Approved wording, verbatim (2026-08-21). Replaces
                // 'Fridge Clearer cooks count toward it.', which described
                // the pre-2026-08-20 rule: eligibility is a property of the
                // RECIPE's origin now, not of the screen the cook was
                // launched from. Do not paraphrase or re-compress this.
                Text(
                  'A recipe created in the Fridge Clearer counts as a rescue wherever you cook it — right away, or later from your Weekly Planner. What matters is where the recipe came from, not where you pressed Cook.',
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: AppDesignTokens.deepForest,
                      fontWeight: FontWeight.w700,
                      height: 1.35),
                ),
                const SizedBox(height: 4),
                Text(
                  "Other recipes and re-cooks don't count again.",
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: AppDesignTokens.deepForest,
                      fontWeight: FontWeight.w700,
                      height: 1.35),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (rows.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(16),
                border:
                    Border.all(color: scheme.outline.withValues(alpha: 0.14)),
              ),
              child: Text(
                'Cook something that uses up fresh items in your fridge, and your rescued list will show up here.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: rows.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) =>
                    _RescuedIngredientRow(tally: rows[i]),
              ),
            ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: scheme.outline.withValues(alpha: 0.12)),
            ),
            child: Text(
              'Lifetime: $lifetimeCount ingredient${lifetimeCount == 1 ? '' : 's'} rescued',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

class _RescuedIngredientRow extends StatelessWidget {
  const _RescuedIngredientRow({required this.tally});

  final _IngredientTally tally;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.14)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppDesignTokens.deepForest.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.local_florist_rounded,
                color: AppDesignTokens.deepForest, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Text(tally.label,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w900))),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: scheme.outline.withValues(alpha: 0.10)),
            ),
            child: Text('×${tally.count}',
                style: theme.textTheme.labelMedium
                    ?.copyWith(fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }
}

class _IngredientTally {
  const _IngredientTally({required this.label, required this.count});

  final String label;
  final int count;
}

class _ResumeSessionBanner extends StatelessWidget {
  const _ResumeSessionBanner(
      {required this.session, required this.onResume, required this.onDiscard});

  final ActiveCookSession session;
  final VoidCallback onResume;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppDesignTokens.champagneTint,
        borderRadius: BorderRadius.circular(AppDesignTokens.radiusCard),
        border: Border.all(
            color: AppDesignTokens.ctaTerracotta.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppDesignTokens.champagneTint,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.restaurant_menu_rounded,
                    color: AppDesignTokens.ctaTerracotta),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Pick up where you left off',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 2),
                    Text(
                      session.recipe.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onDiscard,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: scheme.onSurfaceVariant,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Discard',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: onResume,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppDesignTokens.ctaTerracotta,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Resume Cooking',
                      style: TextStyle(fontWeight: FontWeight.w900)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProfileAvatarButton extends StatefulWidget {
  const _ProfileAvatarButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_ProfileAvatarButton> createState() => _ProfileAvatarButtonState();
}

class _ProfileAvatarButtonState extends State<_ProfileAvatarButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _pressed ? 0.96 : 1,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      child: Material(
        color: AppDesignTokens.surfaceIvory,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap,
          onHighlightChanged: (v) => setState(() => _pressed = v),
          splashFactory: NoSplash.splashFactory,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          hoverColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                  color: AppDesignTokens.deepForest.withValues(alpha: 0.14)),
            ),
            child: const BrandedAvatarGlyph(size: 22),
          ),
        ),
      ),
    );
  }
}
