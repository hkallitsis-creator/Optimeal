import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:optimeal/theme.dart';

/// Simple Mon–Sun picker used by "Plan for Day".
///
/// Returns selected day index (Mon=0 .. Sun=6) via `Navigator.pop(result)`.
class WeekdayPickerSheet extends StatelessWidget {
  const WeekdayPickerSheet({super.key, this.title = 'Pick a day'});

  final String title;

  static const labelsShort = <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const labelsLong = <String>['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: List.generate(7, (i) {
              return ConstrainedBox(
                constraints: const BoxConstraints(minHeight: AppSizing.minTouchTarget),
                child: OutlinedButton(
                  onPressed: () => context.pop(i),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: scheme.surface,
                    foregroundColor: scheme.onSurface,
                    side: BorderSide(color: scheme.tertiary.withValues(alpha: 0.70), width: 1.2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ).copyWith(
                    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
                  ),
                  child: Text(labelsLong[i], style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900)),
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          Text(
            'Tip: You can keep up to 2 meal slots per day.',
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
