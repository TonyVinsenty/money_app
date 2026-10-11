import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Кнопка диалога-подтверждения для `AlertDialog.adaptive` (ADR 0013, п. 6):
/// на iPhone — системная `CupertinoDialogAction`, на Android — прежние
/// Material-кнопки.
///
/// [destructive] — действие, которое удаляет или стирает: красное на обеих
/// платформах. [primary] — главное действие: на iPhone жирное, на Android
/// залитая кнопка (`FilledButton`).
class AdaptiveDialogAction extends StatelessWidget {
  const AdaptiveDialogAction({
    required this.onPressed,
    required this.label,
    this.destructive = false,
    this.primary = false,
    super.key,
  });

  final VoidCallback onPressed;
  final String label;
  final bool destructive;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (theme.platform == TargetPlatform.iOS) {
      return CupertinoDialogAction(
        onPressed: onPressed,
        isDestructiveAction: destructive,
        isDefaultAction: primary,
        child: Text(label),
      );
    }
    if (primary && !destructive) {
      return FilledButton(onPressed: onPressed, child: Text(label));
    }
    return TextButton(
      style: destructive
          ? TextButton.styleFrom(foregroundColor: theme.colorScheme.error)
          : null,
      onPressed: onPressed,
      child: Text(label),
    );
  }
}
