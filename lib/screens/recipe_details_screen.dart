import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:optimeal/screens/one_pan_cooking_roadmap_screen.dart';
import 'package:optimeal/services/saved_recipes_service.dart';
import 'package:optimeal/theme/app_design_tokens.dart';
import 'package:optimeal/widgets/home_glyph_button.dart';
import 'package:optimeal/widgets/recipe_provenance_badges.dart';
import 'package:optimeal/widgets/save_recipe_bookmark_button.dart';
import '../theme.dart';

class RecipeDetailsScreen extends StatelessWidget {
  const RecipeDetailsScreen({super.key, this.recipe, this.service});

  /// The recipe to show. Passed as go_router's `extra` — see
  /// `AppRoutes.recipe`. Null keeps the pre-existing static demo body, which
  /// is what the bare `/recipe` route has always rendered; nothing else in
  /// the app reaches that path.
  final CookModeRecipePayload? recipe;

  /// Injectable for tests. Defaults to the shared singleton.
  final SavedRecipesService? service;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final payload = recipe;

    return Scaffold(
      backgroundColor: isDark
          ? DarkModeColors.darkBackground
          : LightModeColors.lightBackground,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 250,
            pinned: true,
            backgroundColor: theme.colorScheme.primaryContainer,
            foregroundColor: theme.colorScheme.onSurface,
            // Depth-2 (reached only through another screen): back plus the
            // quiet home glyph, now that the bottom nav bar is gone.
            leadingWidth: kBackWithHomeLeadingWidth,
            leading: BackWithHomeLeading(
              back: IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: (isDark
                            ? DarkModeColors.darkSurface
                            : LightModeColors.lightSurface)
                        .withValues(alpha: 0.80),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.arrow_back),
                ),
                onPressed: () => context.pop(),
              ),
            ),
            // The universal bookmark, quiet, in the app bar. Only present
            // when there is a real recipe to save.
            actions: [
              if (payload != null)
                SaveRecipeBookmarkButton(recipe: payload, service: service),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Hero(
                tag: 'meal_card',
                child: Container(
                  color: theme.colorScheme.primaryContainer
                      .withValues(alpha: 0.30),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Food Image
                      Image.asset(
                        'assets/images/Gourmet_Dish_transparent_1784568266545.png', // Fallback or dynamic
                        fit: BoxFit.contain,
                        height: 200,
                      ),
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          height: 80,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                isDark
                                    ? DarkModeColors.darkBackground
                                    : LightModeColors.lightBackground,
                                (isDark
                                        ? DarkModeColors.darkBackground
                                        : LightModeColors.lightBackground)
                                    .withValues(alpha: 0.0),
                              ],
                            ),
                          ),
                        ),
                      )
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (payload != null)
            SliverToBoxAdapter(child: _RecipeBody(recipe: payload))
          else
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Cook Mode',
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.tertiary,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '45 MIN',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onTertiary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Follow the optimized timeline for maximum efficiency.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),

                    const SizedBox(height: 40),

                    // Prep Phase Section
                    Row(
                      children: [
                        Icon(Icons.content_cut,
                            color: theme.colorScheme.primary),
                        const SizedBox(width: 12),
                        Text(
                          'Phase 1: Prep & Knife Work',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: isDark
                            ? DarkModeColors.darkSurface
                            : LightModeColors.lightSurface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color:
                              theme.colorScheme.primary.withValues(alpha: 0.30),
                        ),
                      ),
                      child: Column(
                        children: [
                          _buildPrepRule(
                              context,
                              'Mise en Place',
                              'Gather all ingredients before making a single cut.',
                              Icons.shopping_basket_outlined),
                          const Divider(height: 24),
                          _buildPrepRule(
                              context,
                              'Uniform Dicing (3cm)',
                              'Cut sweet potatoes and carrots into exact 3cm cubes for even roasting.',
                              Icons.grid_on_outlined),
                          const Divider(height: 24),
                          _buildPrepRule(
                              context,
                              'Protein Prep',
                              'Pat dry and season protein 10 minutes prior to cooking.',
                              Icons.set_meal_outlined),
                        ],
                      ),
                    ),

                    const SizedBox(height: 40),

                    // The One-Pan Timeline Section
                    Row(
                      children: [
                        Icon(Icons.access_time,
                            color: theme.colorScheme.tertiary),
                        const SizedBox(width: 12),
                        Text(
                          'Phase 2: The One-Pan Timeline',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    _buildTimelineItem(
                      context,
                      time: '0:00',
                      title: 'Preheat & Roast Veggies',
                      description:
                          'Oven at 220°C. Place the 3cm diced vegetables on the left side of the baking tray.',
                      isFirst: true,
                      isActive: true,
                    ),
                    _buildTimelineItem(
                      context,
                      time: '0:15',
                      title: 'Sear Protein',
                      description:
                          'While veggies roast, sear protein on a skillet for 2 mins each side for crust.',
                      isActive: false,
                    ),
                    _buildTimelineItem(
                      context,
                      time: '0:20',
                      title: 'Combine on Tray',
                      description:
                          'Move seared protein to the right side of the tray in the oven. Everything finishes together.',
                      isActive: false,
                    ),
                    _buildTimelineItem(
                      context,
                      time: '0:35',
                      title: 'Rest & Plate',
                      description:
                          'Remove from oven. Let protein rest for 5 mins while plating vegetables.',
                      isLast: true,
                      isActive: false,
                    ),

                    const SizedBox(height: 60),
                  ],
                ),
              ),
            )
        ],
      ),
    );
  }

  Widget _buildPrepRule(
      BuildContext context, String title, String desc, IconData icon) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.50),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: theme.colorScheme.primary),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                desc,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTimelineItem(
    BuildContext context, {
    required String time,
    required String title,
    required String description,
    bool isFirst = false,
    bool isLast = false,
    bool isActive = false,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final dotColor =
        isActive ? theme.colorScheme.tertiary : theme.colorScheme.outline;
    final lineColor = theme.colorScheme.outline.withValues(alpha: 0.30);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Time column
          SizedBox(
            width: 50,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                Text(
                  time,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: isActive
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.onSurfaceVariant,
                    fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
          // Line and dot
          SizedBox(
            width: 30,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned(
                  top: isFirst ? 20 : 0,
                  bottom: isLast ? null : 0,
                  height: isLast ? 20 : null,
                  child: Container(
                    width: 2,
                    color: lineColor,
                  ),
                ),
                Positioned(
                  top: 18,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: isActive
                          ? dotColor
                          : (isDark
                              ? DarkModeColors.darkBackground
                              : LightModeColors.lightBackground),
                      border: Border.all(
                        color: dotColor,
                        width: 2,
                      ),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 30.0),
              child: Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark
                      ? DarkModeColors.darkSurface
                      : LightModeColors.lightSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: isActive
                      ? Border.all(
                          color: theme.colorScheme.tertiary
                              .withValues(alpha: 0.50))
                      : null,
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color: theme.colorScheme.tertiary
                                .withValues(alpha: 0.10),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          )
                        ]
                      : [],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isActive
                            ? theme.colorScheme.tertiary
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      description,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The real recipe body, shown whenever [RecipeDetailsScreen.recipe] is
/// provided. Enough to answer "what is this and can I cook it": title,
/// provenance, ingredients, and the steps as generated. Deliberately plain —
/// Cook Mode is where the guided experience lives.
class _RecipeBody extends StatelessWidget {
  const _RecipeBody({required this.recipe});

  final CookModeRecipePayload recipe;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isFridgeRescue = recipe.origin?.isRescueEligible ?? false;
    final description = recipe.description?.trim() ?? '';
    final gear = recipe.kitchenGear ?? const <String>[];

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            recipe.title,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              height: 1.15,
              color: AppDesignTokens.deepForest,
            ),
          ),
          if (isFridgeRescue) ...[
            const SizedBox(height: 10),
            const ProvenanceLeafBadge(),
          ],
          if (description.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              description,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppDesignTokens.textCharcoal.withValues(alpha: 0.78),
                height: 1.45,
              ),
            ),
          ],
          const SizedBox(height: 28),
          _DetailsSection(
            // SIGNED-CONTENT PLACEHOLDER
            title: 'Ingredients',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final ingredient in recipe.ingredients)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 7, right: 10),
                          child: Container(
                            height: 5,
                            width: 5,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppDesignTokens.ctaTerracotta
                                  .withValues(alpha: 0.85),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(ingredient,
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(height: 1.4)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (gear.isNotEmpty) ...[
            const SizedBox(height: 24),
            _DetailsSection(
              // SIGNED-CONTENT PLACEHOLDER
              title: 'Kitchen gear',
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final item in gear)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppDesignTokens.surfaceIvory,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                            color: AppDesignTokens.textCharcoal
                                .withValues(alpha: 0.14)),
                      ),
                      child: Text(item,
                          style: theme.textTheme.labelMedium
                              ?.copyWith(fontWeight: FontWeight.w700)),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          _DetailsSection(
            // SIGNED-CONTENT PLACEHOLDER
            title: 'Steps',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < recipe.steps.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${i + 1}. ${recipe.steps[i].title}',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: AppDesignTokens.deepForest,
                          ),
                        ),
                        const SizedBox(height: 4),
                        for (final bullet in recipe.steps[i].bullets)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              bullet,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: AppDesignTokens.textCharcoal
                                    .withValues(alpha: 0.78),
                                height: 1.4,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailsSection extends StatelessWidget {
  const _DetailsSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.labelMedium?.copyWith(
            color: AppDesignTokens.deepForest.withValues(alpha: 0.75),
            fontWeight: FontWeight.w900,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}
