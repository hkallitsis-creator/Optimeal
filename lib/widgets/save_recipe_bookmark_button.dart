import 'package:flutter/material.dart';

import 'package:optimeal/screens/one_pan_cooking_roadmap_screen.dart';
import 'package:optimeal/services/saved_recipes_service.dart';
import 'package:optimeal/theme/app_design_tokens.dart';

/// The universal save affordance. One icon, one mechanism, everywhere:
/// **filled = saved, outline = not saved**, tap toggles.
///
/// State comes from [SavedRecipesService.watchSavedRecipes], which re-emits
/// after every mutation on the shared singleton — so toggling the bookmark on
/// one surface updates it on every other open surface with no plumbing. That
/// is the whole reason this widget subscribes rather than taking a bool.
///
/// Deliberately quiet: no label, no background container, no copy nagging the
/// user to save. It is present, not a prompt.
///
/// Stateful purely to hold the subscription: [SavedRecipesService.watchSavedRecipes]
/// hands back a NEW stream per call, so calling it from `build` would
/// resubscribe on every emission and spin forever. Every consumer of that
/// method has to cache the stream the same way.
class SaveRecipeBookmarkButton extends StatefulWidget {
  const SaveRecipeBookmarkButton({
    super.key,
    required this.recipe,
    this.service,
    this.size = 22,
    this.color,
  });

  /// The recipe this bookmark saves or unsaves. Its title is the identity —
  /// see [SavedRecipesService.recipeKeyFor].
  final CookModeRecipePayload recipe;

  /// Injectable for tests. Defaults to the shared singleton, which is what
  /// makes cross-surface consistency work in the real app.
  final SavedRecipesService? service;

  final double size;

  /// Defaults to deep forest. Overridden only where the bookmark sits on a
  /// surface that would swallow it.
  final Color? color;

  @override
  State<SaveRecipeBookmarkButton> createState() =>
      _SaveRecipeBookmarkButtonState();
}

class _SaveRecipeBookmarkButtonState extends State<SaveRecipeBookmarkButton> {
  late Stream<List<SavedRecipe>> _saved;

  SavedRecipesService get _service =>
      widget.service ?? SavedRecipesService.instance;

  @override
  void initState() {
    super.initState();
    _saved = _service.watchSavedRecipes();
  }

  @override
  void didUpdateWidget(covariant SaveRecipeBookmarkButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service != widget.service) {
      _saved = _service.watchSavedRecipes();
    }
  }

  @override
  Widget build(BuildContext context) {
    final key = SavedRecipesService.recipeKeyFor(widget.recipe.title);
    final tint = widget.color ?? AppDesignTokens.deepForest;

    return StreamBuilder<List<SavedRecipe>>(
      stream: _saved,
      builder: (context, snapshot) {
        final saved =
            (snapshot.data ?? const []).any((s) => s.recipeKey == key);
        return IconButton(
          onPressed: () =>
              saved ? _service.unsave(key) : _service.save(widget.recipe),
          visualDensity: VisualDensity.compact,
          // SIGNED-CONTENT PLACEHOLDER
          tooltip: saved ? 'Saved' : 'Save',
          icon: Icon(
            saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
            size: widget.size,
            color: tint,
          ),
        );
      },
    );
  }
}
