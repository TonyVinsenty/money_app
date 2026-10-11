import 'package:flutter/material.dart';
import 'package:money_app/core/ui/card_header.dart';
import 'package:money_app/core/ui/theme/app_spacing.dart';

/// Карточка раздела (вкладка «Баланс»; design-style.md, 8.1-8.4): рамка и
/// радиус 16 как у карточек «Главной», внутри `CardHeader` и содержимое.
class SectionCard extends StatelessWidget {
  const SectionCard({
    required this.title,
    required this.children,
    this.trailing,
    this.titleKey,
    super.key,
  });

  final String title;

  /// Не больше одного действия справа в заголовке (значок, меню или их ряд).
  final Widget? trailing;
  final Key? titleKey;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card.outlined(
      // Внешний отступ Card по умолчанию 4 dp: обнуляем, как на «Главной».
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.borderL,
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CardHeader(title, trailing: trailing, key: titleKey),
            ...children,
          ],
        ),
      ),
    );
  }
}
