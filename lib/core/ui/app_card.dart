import 'package:flutter/material.dart';
import 'package:money_app/core/ui/theme/app_spacing.dart';

/// Общая «карточка в рамке» (D32): контур `outlineVariant`, радиус 16, поля
/// 16, внешний отступ нулевой (отступ экрана задаёт родитель).
class AppCard extends StatelessWidget {
  const AppCard({
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.l),
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Card.outlined(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.borderL,
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}
