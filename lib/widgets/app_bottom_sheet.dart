import 'package:flutter/material.dart';

import 'package:optimeal/theme.dart';

/// Shared helper for consistent modal bottom sheet behavior across the app.
///
/// Design goals:
/// - Always dismissible via backdrop tap
/// - Always draggable to dismiss
/// - Consistent dimmed barrier color
/// - No full-screen gesture wrappers that could absorb backdrop taps
class AppBottomSheet {
  static Future<T?> show<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool isScrollControlled = false,
    bool useRootNavigator = true,
    bool showDragHandle = false,
    ShapeBorder? shape,
    Color? backgroundColor,
  }) {
    final theme = Theme.of(context);
    return showModalBottomSheet<T>(
      context: context,
      useRootNavigator: useRootNavigator,
      isDismissible: true,
      enableDrag: true,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      isScrollControlled: isScrollControlled,
      showDragHandle: showDragHandle,
      shape: shape ?? RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
      backgroundColor: backgroundColor ?? theme.colorScheme.surface,
      builder: builder,
    );
  }
}
