import 'package:flutter/material.dart';

import 'package:optimeal/theme/app_design_tokens.dart';

/// Placeholder for the "My recipes" destination on the Home hub's tile
/// shelf. The real screen (saved recipes + feedback, CLAUDE.md Roadmap item
/// 21) ships in a later build — this exists so the tile and its route are
/// live and reachable now rather than dangling.
///
/// Depth-1 (opened directly from Home), so it carries a back button only —
/// no home glyph. See the depth rule in CLAUDE.md's navigation section.
class MyRecipesScreen extends StatelessWidget {
  const MyRecipesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppDesignTokens.backgroundSage,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text('My recipes'), // SIGNED-CONTENT PLACEHOLDER
        centerTitle: false,
      ),
      body: Center(
        child: Text(
          'My recipes', // SIGNED-CONTENT PLACEHOLDER
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: AppDesignTokens.deepForest,
          ),
        ),
      ),
    );
  }
}
