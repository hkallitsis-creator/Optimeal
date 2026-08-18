import 'package:flutter/material.dart';

import 'package:optimeal/theme/app_design_tokens.dart';

class CulinaryMasterclassScreen extends StatelessWidget {
  const CulinaryMasterclassScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: AppDesignTokens.backgroundSage,
      appBar: AppBar(
        title: const Text('Culinary Masterclass & Avatar Video Guides'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.school_rounded, size: 56, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text(
                'Coming soon',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Technique videos, culinary guides, and avatar-led walkthroughs will live here.',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.5),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
