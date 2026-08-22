import 'package:flutter/foundation.dart';

/// Which recipe overviews (`RecipeDetailsScreen`) are currently mounted, by
/// normalized recipe key (`SavedRecipesService.recipeKeyFor`).
///
/// # Why this exists (audit H-2)
///
/// Cook Mode's back arrow used `pushReplacement(AppRoutes.recipe)`
/// unconditionally — chosen so a round trip could never stack Cook Modes. But
/// when the overview itself launched the cook, the replacement stacked
/// **overviews** instead: `[…, overview(old), overview(new)]`, with the lower
/// one stale (audit H-1). The rule is now: **never two overviews of one recipe
/// on the stack** — if an overview for this recipe is already mounted below
/// Cook Mode, back POPS to it; otherwise (generation Cook Now, planner Cook,
/// resume banner — launches with no overview underneath) back REPLACES Cook
/// Mode with a fresh one, exactly as before.
///
/// # Why a registry rather than router introspection
///
/// go_router's imperative match list does not expose a lower route's `extra`
/// in a version-stable way. A mount registry is trivially true by
/// construction: an overview registers its recipe key in `initState` and
/// removes exactly one occurrence in `dispose`, so "is an overview for this
/// recipe mounted right now" is answerable without touching the router at
/// all. Pages below the top of a go_router stack stay mounted, which is what
/// makes mounted-ness the right proxy for "is on the stack below me".
///
/// This is UI-stack bookkeeping, not data — deliberately its own file so
/// neither screen has to import the other (they would cycle).
abstract final class OverviewRouteRegistry {
  static final List<String> _mountedRecipeKeys = <String>[];

  /// Called by the overview's `initState`. Duplicate keys are legal while a
  /// transition overlaps two instances; each registration is matched by
  /// exactly one [unregister].
  static void register(String recipeKey) => _mountedRecipeKeys.add(recipeKey);

  /// Called by the overview's `dispose`. Removes one occurrence only.
  static void unregister(String recipeKey) =>
      _mountedRecipeKeys.remove(recipeKey);

  /// True while any overview instance for [recipeKey] is mounted.
  static bool hasMountedFor(String recipeKey) =>
      _mountedRecipeKeys.contains(recipeKey);

  /// Test seam. Not called by app code.
  @visibleForTesting
  static void resetForTest() => _mountedRecipeKeys.clear();
}
