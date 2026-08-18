import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:optimeal/nav.dart';
import 'package:optimeal/services/chef_service.dart';
import 'package:optimeal/services/cook_session_storage_service.dart';
import 'package:optimeal/services/entitlement_service.dart';
import 'package:optimeal/services/ledger_service.dart';
import 'package:optimeal/services/ledger_sync_coordinator.dart';
import 'package:optimeal/services/recent_generations_service.dart';
import 'package:optimeal/services/usage_cap_service.dart';
import 'package:optimeal/screens/one_pan_cooking_roadmap_screen.dart';
import 'package:optimeal/state/user_profile_controller.dart';
import 'package:optimeal/theme/app_design_tokens.dart';
import 'package:optimeal/theme.dart';
import 'package:optimeal/widgets/app_bottom_sheet.dart';
import 'package:optimeal/widgets/curriculum_drawer_content.dart';
import 'package:optimeal/widgets/custom_ai_recipe_creator_sheet.dart';
import 'package:optimeal/widgets/generated_recipe_actions_sheet.dart';
import 'package:optimeal/widgets/branded_avatar_glyph.dart';
import 'package:optimeal/widgets/upgrade_prompt_sheet.dart';
import 'package:optimeal/widgets/your_month_card.dart';

/// Free-tier daily cap on Chef Harris AI chat, applied ONLY to the Home
/// "Chef Harris Suggestion" generator (_ChefSuggestionSheet). Deliberately
/// does NOT apply to _ChefSosSheet (Cook Mode's SOS chat) — that stays
/// free-forever as part of Cook Mode, since asking for help mid-recipe is
/// exactly the moment this app needs to be reliable. See CLAUDE.md
/// "Monetization / paywall tier structure".
const int kChefHarrisChatFreeDailyLimit = 5;

class HomeDashboardScreen extends StatefulWidget {
  const HomeDashboardScreen({super.key});

  static const Color _deepForest = Color(0xFF1E3A2B);
  static const Color _terracotta = Color(0xFFD96B43);
  static const double _cardRadius = 16.0;
  static const List<BoxShadow> _cardShadow = AppDesignTokens.cardShadow;

  static String _dietLabel(String raw) {
    switch (raw) {
      case 'omnivore':
        return 'Omnivore';
      case 'vegetarian':
        return 'Vegetarian';
      case 'pescatarian':
        return 'Pescatarian';
      case 'vegan':
        return 'Vegan';
      case 'flexitarian':
        return 'Flexitarian';
      default:
        return raw.trim().isEmpty ? 'Omnivore' : raw;
    }
  }

  static Future<void> _showChefSuggestion(BuildContext context) async {
    await AppBottomSheet.show<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppDesignTokens.surfaceCream,
      builder: (ctx) => const SafeArea(child: _ChefSuggestionSheet()),
    );
  }

  static Future<void> _showTechniqueOfTheWeek(
      BuildContext context, ResolvedDrawerEntry entry) async {
    await AppBottomSheet.show<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppDesignTokens.surfaceCream,
      builder: (ctx) => SafeArea(child: _TechniqueOfTheWeekSheet(entry: entry)),
    );
  }

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    routeObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Fires when a route pushed on top of Home (Fridge Clearer, Cook Mode,
  /// Recently Cooked's re-entry, etc.) is popped and Home becomes the
  /// top-of-stack route again. Home's own [State] is never disposed by
  /// that push/pop — it just sits underneath — so without this, nothing
  /// ever tells it a cook may have just completed. See device-test-round
  /// I1 investigation.
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
  void _checkDeepLinkIntent() {
    final open = GoRouterState.of(context).uri.queryParameters['open'];
    if (open != 'ai_generator') return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
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

  /// Pushes Cook Mode with either a fresh [recipe] or a saved
  /// [resumeSession], then refreshes the saved-session state on return so
  /// the Resume banner reflects whatever happened in Cook Mode (finished,
  /// discarded, or still in progress).
  ///
  /// [recipe] is only ever passed from Recently Cooked, so it's always a
  /// re-cook (CLAUDE.md Roadmap item 28) — [surface] is null since original
  /// provenance isn't tracked and doesn't matter: [isReCook] alone already
  /// excludes it from Waste Ledger logging.
  Future<void> _openCookMode(BuildContext context,
      {CookModeRecipePayload? recipe, ActiveCookSession? resumeSession}) async {
    final extra = resumeSession ??
        (recipe != null
            ? CookModeLaunchRequest(
                recipe: recipe, surface: null, isReCook: true)
            : null);
    await context.push(AppRoutes.onePanCookingRoadmap, extra: extra);
    if (!mounted) return;
    _loadActiveSession();
    _loadWeeklyLedger();
  }

  Future<void> _showThisWeekLedger(BuildContext context) async {
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

  Future<void> _showRecentlyCooked(BuildContext context) async {
    final entries = await _sessionStorage.loadRecentlyCooked();
    if (!context.mounted) return;
    await AppBottomSheet.show<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppDesignTokens.surfaceCream,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) => SafeArea(
        child: _RecentlyCookedSheet(
          entries: entries,
          onSelect: (recipe) {
            Navigator.of(sheetContext).pop();
            _openCookMode(context, recipe: recipe);
          },
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
    final dietLabel = HomeDashboardScreen._dietLabel(profile.diet.name);
    final allergyLabels = profile.allergies
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    final activeSession = _activeSession;

    return Scaffold(
      backgroundColor: AppDesignTokens.backgroundSage,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: _HeaderSection(
                  displayName: displayName,
                  dietLabel: dietLabel,
                  allergyLabels: allergyLabels,
                  onProfileTap: () => context.push(AppRoutes.profile),
                  onGetIdeaTap: () =>
                      HomeDashboardScreen._showChefSuggestion(context),
                ),
              ),
            ),
            if (activeSession != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                  child: _ResumeSessionBanner(
                    session: activeSession,
                    onResume: () =>
                        _openCookMode(context, resumeSession: activeSession),
                    onDiscard: _discardActiveSession,
                  ),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  // Kept close to square: tall cards (aspect < 0.9) push the
                  // 3-row grid + bottom nav past small-phone viewport heights.
                  childAspectRatio: 0.95,
                ),
                delegate: SliverChildListDelegate.fixed([
                  // Reordered 2026-08-17 (docs/decisions_2026-08-17.md):
                  // Fridge Clearer leads as the hero action, the AI
                  // generator (Custom AI Recipe Creator) second, everything
                  // else after. No destination removed, only reweighted.
                  _ActionCard(
                    title: 'Fridge Clearer',
                    subtitle: 'Turn leftover ingredients into great meals.',
                    emoji: '💡',
                    accent: HomeDashboardScreen._deepForest,
                    icon: Icons.auto_awesome_rounded,
                    onTap: () => context.push(AppRoutes.aiFridgeScrapGenerator),
                  ),
                  _ActionCard(
                    title: 'Custom AI Recipe Creator',
                    subtitle:
                        'Type any dish, craving, or diet to generate an instant recipe.',
                    emoji: '🪄',
                    accent: HomeDashboardScreen._terracotta,
                    icon: Icons.restaurant_rounded,
                    onTap: () =>
                        HomeDashboardScreen._showCustomAiRecipeCreator(context),
                  ),
                  _ActionCard(
                    title: 'Weekly Planner',
                    subtitle: 'Plan Mon–Sun and stay on track.',
                    emoji: '📅',
                    accent: HomeDashboardScreen._terracotta,
                    icon: Icons.calendar_month_rounded,
                    onTap: () => context.push(AppRoutes.weeklyPlan),
                  ),
                  _ActionCard(
                    title: 'Recipe Library',
                    subtitle: 'Browse technique matrixes & saved favorites.',
                    emoji: '📚',
                    accent: HomeDashboardScreen._deepForest,
                    icon: Icons.menu_book_rounded,
                    // Index 2 — Techniques & Media moved up a slot when the
                    // Fridge tab was cut (docs/decisions_2026-08-17.md item 5).
                    onTap: () => context.go(AppRoutes.homeTab(2)),
                  ),
                  _ActionCard(
                    title: 'Recently Cooked',
                    subtitle: 'Revisit or remake your last few dishes.',
                    emoji: '🕒',
                    accent: HomeDashboardScreen._terracotta,
                    icon: Icons.history_rounded,
                    onTap: () => _showRecentlyCooked(context),
                  ),
                  // Waste Ledger summary — stays visible on Home, per
                  // instruction (it's the app's identity). Reweighted to
                  // last position, not removed.
                  _ActionCard(
                    title: 'This Week',
                    subtitle: _weeklyIngredientsRescued == 0
                        ? 'Nothing rescued yet this week.'
                        : '$_weeklyIngredientsRescued ingredient${_weeklyIngredientsRescued == 1 ? '' : 's'} rescued so far.',
                    emoji: '🌿',
                    accent: HomeDashboardScreen._deepForest,
                    icon: Icons.eco_rounded,
                    onTap: () => _showThisWeekLedger(context),
                  ),
                ]),
              ),
            ),
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: YourMonthCard(),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: _TechniqueOfTheWeekCard(
                  onTap: (entry) => HomeDashboardScreen._showTechniqueOfTheWeek(
                      context, entry),
                ),
              ),
            ),
          ],
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
                  color:
                      HomeDashboardScreen._deepForest.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: HomeDashboardScreen._deepForest
                          .withValues(alpha: 0.18)),
                ),
                child: const Icon(Icons.eco_rounded,
                    color: HomeDashboardScreen._deepForest, size: 20),
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
              color: HomeDashboardScreen._deepForest.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color:
                      HomeDashboardScreen._deepForest.withValues(alpha: 0.16)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "This tracks real fridge rescues — cooking food that would've gone to waste.",
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: HomeDashboardScreen._deepForest,
                      fontWeight: FontWeight.w700,
                      height: 1.35),
                ),
                const SizedBox(height: 4),
                Text(
                  'Fridge Clearer cooks count toward it.',
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: HomeDashboardScreen._deepForest,
                      fontWeight: FontWeight.w700,
                      height: 1.35),
                ),
                const SizedBox(height: 4),
                Text(
                  "Other recipes and re-cooks don't count again.",
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: HomeDashboardScreen._deepForest,
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
              color: HomeDashboardScreen._deepForest.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.local_florist_rounded,
                color: HomeDashboardScreen._deepForest, size: 20),
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
        color: HomeDashboardScreen._terracotta.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(HomeDashboardScreen._cardRadius),
        border: Border.all(
            color: HomeDashboardScreen._terracotta.withValues(alpha: 0.24)),
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
                  color:
                      HomeDashboardScreen._terracotta.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.restaurant_menu_rounded,
                    color: HomeDashboardScreen._terracotta),
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
                    backgroundColor: HomeDashboardScreen._terracotta,
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

class _TechniqueOfTheWeekCard extends StatelessWidget {
  const _TechniqueOfTheWeekCard({required this.onTap});

  final ValueChanged<ResolvedDrawerEntry> onTap;

  @override
  Widget build(BuildContext context) {
    final entry = techniqueOfTheWeek();
    if (entry == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onTap(entry),
        borderRadius: BorderRadius.circular(HomeDashboardScreen._cardRadius),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius:
                BorderRadius.circular(HomeDashboardScreen._cardRadius),
            border: Border.all(
                color: HomeDashboardScreen._deepForest.withValues(alpha: 0.16)),
            boxShadow: HomeDashboardScreen._cardShadow,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color:
                      HomeDashboardScreen._deepForest.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.auto_stories_rounded,
                    color: HomeDashboardScreen._deepForest),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Technique of the Week',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: HomeDashboardScreen._deepForest,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(entry.title,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w900)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _TechniqueOfTheWeekSheet extends StatelessWidget {
  const _TechniqueOfTheWeekSheet({required this.entry});

  final ResolvedDrawerEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: AppDesignTokens.surfaceCream,
      child: SingleChildScrollView(
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
                  child: const Icon(Icons.auto_stories_rounded,
                      color: AppDesignTokens.deepForest, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Technique of the Week',
                    style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: AppDesignTokens.textCharcoal),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            DrawerCard(entry: entry, initiallyOpen: true),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: AppSizing.primaryButtonHeight,
              child: FilledButton(
                onPressed: () => context.pop(),
                style: FilledButton.styleFrom(
                  backgroundColor: AppDesignTokens.ctaTerracotta,
                  foregroundColor: scheme.onTertiary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18)),
                ),
                child: Text(
                  'Got it',
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

class _RecentlyCookedSheet extends StatelessWidget {
  const _RecentlyCookedSheet({required this.entries, required this.onSelect});

  final List<RecentlyCookedEntry> entries;
  final ValueChanged<CookModeRecipePayload> onSelect;

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Recently Cooked',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(
            'The last few recipes you\'ve actually cooked.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          if (entries.isEmpty)
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
                'Nothing here yet — recipes you open in Cook Mode will show up here.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            )
          else
            for (var i = 0; i < entries.length; i++) ...[
              _RecentlyCookedRow(
                entry: entries[i],
                relativeTime: _relativeTime(entries[i].cookedAt),
                onTap: () => onSelect(entries[i].recipe),
              ),
              if (i != entries.length - 1) const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }
}

class _RecentlyCookedRow extends StatelessWidget {
  const _RecentlyCookedRow(
      {required this.entry, required this.relativeTime, required this.onTap});

  final RecentlyCookedEntry entry;
  final String relativeTime;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: scheme.outline.withValues(alpha: 0.14)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color:
                      HomeDashboardScreen._deepForest.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.history_rounded,
                    color: HomeDashboardScreen._deepForest),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.recipe.title,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 2),
                    Text(relativeTime,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderSection extends StatelessWidget {
  const _HeaderSection(
      {required this.displayName,
      required this.dietLabel,
      required this.allergyLabels,
      required this.onProfileTap,
      required this.onGetIdeaTap});

  final String displayName;
  final String dietLabel;
  final List<String> allergyLabels;
  final VoidCallback onProfileTap;
  final VoidCallback onGetIdeaTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hello, $displayName!',
                    style: theme.textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w900, height: 1.1),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          'What are we cooking today? I’ll keep it fast, simple, and delicious.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant, height: 1.35),
                        ),
                      ),
                      const SizedBox(width: 10),
                      _GetIdeaChip(onTap: onGetIdeaTap),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _ProfileAvatarButton(onTap: onProfileTap),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _PreferenceBadge(icon: Icons.restaurant_rounded, label: dietLabel),
            ...allergyLabels.take(4).map((a) =>
                _PreferenceBadge(icon: Icons.warning_amber_rounded, label: a)),
            if (allergyLabels.length > 4)
              _PreferenceBadge(
                  icon: Icons.more_horiz_rounded,
                  label: '+${allergyLabels.length - 4} more',
                  isActive: false),
          ],
        ),
      ],
    );
  }
}

class _GetIdeaChip extends StatefulWidget {
  const _GetIdeaChip({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_GetIdeaChip> createState() => _GetIdeaChipState();
}

class _GetIdeaChipState extends State<_GetIdeaChip> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AnimatedScale(
      scale: _pressed ? 0.98 : 1,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        child: OutlinedButton.icon(
          onPressed: widget.onTap,
          icon: Icon(Icons.lightbulb_outline_rounded,
              size: 18, color: scheme.secondary),
          label: Text('Get an idea',
              style: theme.textTheme.labelLarge?.copyWith(
                  color: scheme.secondary, fontWeight: FontWeight.w900)),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            minimumSize: const Size(0, 38),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            side: BorderSide(color: scheme.secondary.withValues(alpha: 0.35)),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999)),
            foregroundColor: scheme.secondary,
          ).copyWith(
            overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          ),
        ),
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AnimatedScale(
      scale: _pressed ? 0.96 : 1,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      child: Material(
        color: scheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: widget.onTap,
          onHighlightChanged: (v) => setState(() => _pressed = v),
          splashFactory: NoSplash.splashFactory,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          hoverColor: Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: scheme.primary.withValues(alpha: 0.14)),
            ),
            child: const BrandedAvatarGlyph(size: 22),
          ),
        ),
      ),
    );
  }
}

class _PreferenceBadge extends StatelessWidget {
  const _PreferenceBadge(
      {required this.icon, required this.label, this.isActive = true});

  final IconData icon;
  final String label;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final background =
        isActive ? AppDesignTokens.ctaTerracotta : scheme.surface;
    final contentColor = isActive ? Colors.white : scheme.onSurfaceVariant;
    final borderColor =
        isActive ? Colors.transparent : scheme.outline.withValues(alpha: 0.18);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: contentColor),
          const SizedBox(width: 8),
          Text(label,
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: contentColor, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _ActionCard extends StatefulWidget {
  const _ActionCard({
    required this.title,
    required this.subtitle,
    required this.emoji,
    required this.accent,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String emoji;
  final Color accent;
  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_ActionCard> createState() => _ActionCardState();
}

class _ActionCardState extends State<_ActionCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AnimatedScale(
      scale: _pressed ? 0.985 : 1,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      child: Material(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(HomeDashboardScreen._cardRadius),
        child: InkWell(
          onTap: widget.onTap,
          onHighlightChanged: (v) => setState(() => _pressed = v),
          splashFactory: NoSplash.splashFactory,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          hoverColor: Colors.transparent,
          borderRadius: BorderRadius.circular(HomeDashboardScreen._cardRadius),
          child: Container(
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius:
                  BorderRadius.circular(HomeDashboardScreen._cardRadius),
              border: Border.all(color: scheme.outline.withValues(alpha: 0.10)),
              boxShadow: HomeDashboardScreen._cardShadow,
            ),
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        height: 42,
                        width: 42,
                        decoration: BoxDecoration(
                          color: widget.accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: widget.accent.withValues(alpha: 0.18)),
                        ),
                        child:
                            Icon(widget.icon, color: widget.accent, size: 22),
                      ),
                      const Spacer(),
                      Text(widget.emoji,
                          style: theme.textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w900)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    widget.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      height: 1.15,
                      color: HomeDashboardScreen._deepForest,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.subtitle,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant, height: 1.35),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChefSuggestionSheet extends StatefulWidget {
  const _ChefSuggestionSheet();

  @override
  State<_ChefSuggestionSheet> createState() => _ChefSuggestionSheetState();
}

class _ChefSuggestionSheetState extends State<_ChefSuggestionSheet> {
  final _chefService = ChefService();
  bool _loading = true;
  String? _error;
  String? _text;

  String? _extractDishName(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;

    // Try to pull something like:
    // - "Dish name: ..."
    // - "1) Dish name: ..."
    final lines = trimmed
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (lines.isEmpty) return null;
    final firstLine = lines.first;

    final labeled = RegExp(
            r'^(?:\d+\)|[-•])?\s*(?:dish name|recipe|suggestion)\s*[:\-]\s*(.+)$',
            caseSensitive: false)
        .firstMatch(firstLine);
    if (labeled != null) {
      final value = (labeled.group(1) ?? '').trim();
      return value.isEmpty ? null : value;
    }

    // Otherwise, use the first sentence / clause as a best-effort title.
    final firstSentence = firstLine.split(RegExp(r'[.!?]')).first.trim();
    if (firstSentence.isEmpty) return null;

    // Avoid storing generic pattern-only openers like "You've been on...".
    if (firstSentence.toLowerCase().startsWith("you've been") ||
        firstSentence.toLowerCase().startsWith('you have been')) {
      if (lines.length >= 2) {
        final candidate = lines[1].split(RegExp(r'[.!?]')).first.trim();
        return candidate.isEmpty ? null : candidate;
      }
    }
    return firstSentence;
  }

  String _buildHistoryAwarePrompt(List<RecentlyCookedEntry> history) {
    final entries = history.take(6).toList();
    final lines = <String>[];

    for (final entry in entries) {
      final title = entry.recipe.title.trim();
      final ingredients = (entry.recipe.ingredients)
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .take(5)
          .toList();
      final ingredientsText =
          ingredients.isEmpty ? '' : ' — ${ingredients.join(', ')}';
      lines.add('• $title$ingredientsText');
    }

    final summary = lines.join('\n');
    return 'Here\'s what I\'ve cooked recently:\n$summary\n\nLook for a pattern — a protein, cuisine, or cooking method I keep returning to — and suggest ONE new meal idea that builds on it. Start your reply by naming the pattern in a short clause (e.g. "You\'ve been on a roasted-veg kick —"), then give: (1) dish name, (2) why it fits the pattern, (3) a 5-step fast method, (4) a smart ingredient substitution if needed, (5) a tiny "leftover rescue" tip.';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profile = context.read<UserProfileController>().profile;

    final isPro = await EntitlementService.instance.isPro();
    if (!mounted) return;
    if (!isPro) {
      final todayCount = await UsageCapService.instance
          .getTodayCount(UsageFeature.chefHarrisChat);
      if (!mounted) return;
      if (todayCount >= kChefHarrisChatFreeDailyLimit) {
        await UpgradePromptSheet.show(
          context,
          title: "You've used today's free Chef suggestions",
          message:
              'Free plan includes $kChefHarrisChatFreeDailyLimit Chef Harris suggestion${kChefHarrisChatFreeDailyLimit == 1 ? '' : 's'} a day. Upgrade to Pro for unlimited.',
        );
        if (!mounted) return;
        // If this was the very first load (sheet just opened, nothing to
        // show yet), close the now-otherwise-empty sheet behind it rather
        // than leaving a blank loading state.
        if (_text == null && _error == null) _close();
        return;
      }
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final history = await CookSessionStorageService().loadCookHistory();
      var userQuery = history.length >= 3
          ? _buildHistoryAwarePrompt(history)
          : 'Give me ONE quick Mediterranean-leaning meal idea for tonight that fits my profile. Include: (1) dish name, (2) why it matches me, (3) a 5-step fast method, (4) a smart ingredient substitution if needed, (5) a tiny “leftover rescue” tip.';

      // Usage tracking is unconditional and independent of entitlement
      // (CLAUDE.md roadmap item 11 follow-up, 2026-08-13) — see
      // fridge_clearer_screen.dart for the full rationale. Only the cap
      // CHECK above stays gated on isPro.
      unawaited(
          UsageCapService.instance.increment(UsageFeature.chefHarrisChat));
      // Recipe variety (CLAUDE.md roadmap item 13): `history` above only
      // informs the pattern-matching prompt when there are 3+ entries — it
      // never actually forbids the AI from repeating a past dish. Routes
      // through the single shared `recentDishTitles` mechanism instead of
      // the old separate freeform "don't suggest again" text block that
      // used to live here (two parallel mechanisms drift) — merges
      // persisted cook history with this app session's in-memory
      // RecentGenerationsService, which is what actually carries repeats
      // across multiple suggestion-sheet opens within one sitting.
      final recentDishTitles = [
        ...RecentGenerationsService.instance.recent(),
        ...history.map((e) => e.recipe.title),
      ];
      final res = await _chefService.askChefHarris(
        userQuery: userQuery,
        profile: profile,
        recentDishTitles: recentDishTitles,
      );
      if (!mounted) return;
      final cleaned = res.trim();
      final dish = _extractDishName(cleaned);
      setState(() {
        _text = cleaned;
        _loading = false;
      });

      final toStore = (dish ?? cleaned).trim();
      if (toStore.isNotEmpty) {
        RecentGenerationsService.instance.record(toStore);
      }
    } catch (e, st) {
      debugPrint('Chef suggestion load failed: $e');
      debugPrint('$st');
      if (!mounted) return;
      setState(() {
        _error = 'Couldn\'t get a suggestion right now.';
        _loading = false;
      });
    }
  }

  void _close() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
      ),
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
                  color: scheme.secondary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: scheme.secondary.withValues(alpha: 0.18)),
                ),
                child: Icon(Icons.restaurant_rounded,
                    color: scheme.secondary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Chef Harris Suggestion',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              IconButton(
                onPressed: _close,
                icon: Icon(Icons.close_rounded, color: scheme.onSurfaceVariant),
                style: ButtonStyle(
                  overlayColor: WidgetStatePropertyAll(Colors.transparent),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'One tap. One idea. Zero stress.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          if (_loading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Row(
                children: [
                  SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.4, color: scheme.secondary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Text('Chef Harris is thinking…',
                          style: theme.textTheme.bodyMedium)),
                ],
              ),
            )
          else if (_error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: scheme.errorContainer.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: scheme.error.withValues(alpha: 0.25)),
              ),
              child: Text(_error!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onErrorContainer,
                      fontWeight: FontWeight.w700)),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(
                // Defensive: keep the sheet readable even if we get an unexpectedly long response.
                maxHeight: MediaQuery.of(context).size.height * 0.42,
              ),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border:
                      Border.all(color: scheme.outline.withValues(alpha: 0.12)),
                ),
                child: SingleChildScrollView(
                  child: Text(_text ?? '',
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.5)),
                ),
              ),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _loading ? null : _load,
                  icon: Icon(Icons.refresh_rounded, color: scheme.secondary),
                  label: Text('Try another',
                      style: TextStyle(
                          color: scheme.secondary,
                          fontWeight: FontWeight.w900)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                        color: scheme.secondary.withValues(alpha: 0.45)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18)),
                    foregroundColor: scheme.secondary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _close,
                  icon: const Icon(Icons.check_rounded, color: Colors.white),
                  label: const Text('Got it',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w900)),
                  style: FilledButton.styleFrom(
                    backgroundColor: HomeDashboardScreen._deepForest,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
