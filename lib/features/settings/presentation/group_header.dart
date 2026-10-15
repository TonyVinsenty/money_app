import 'package:flutter/material.dart';
import 'package:money_app/core/ui/theme/app_spacing.dart';

/// Подзаголовок группы (design-style.md, 8.4): `titleSmall`, 600, цвет
/// акцента, слева, отступ сверху 24. Для скринридера — заголовок.
class GroupHeader extends StatelessWidget {
  const GroupHeader(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.l,
        AppSpacing.xl,
        AppSpacing.l,
        AppSpacing.s,
      ),
      child: Semantics(
        header: true,
        child: Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }
}
