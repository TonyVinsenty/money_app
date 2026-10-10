import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:money_app/features/recurring/domain/recurring_repository.dart';
import 'package:money_app/features/recurring/presentation/recurring_texts.dart';

/// Плашка «К оплате» на «Главной» (ADR 0011, п. 6, Р10). Записей нет - нулевая
/// высота, раскладка экрана прежняя. Тап вызывает [onTap] (приложение
/// переключает вкладку на «Баланс»).
class DueBanner extends StatelessWidget {
  const DueBanner({required this.dues, required this.onTap, super.key});

  /// Общий источник записей «К оплате»; его держит приложение (`lib/app`).
  final ValueListenable<List<RecurringDue>> dues;
  final VoidCallback onTap;

  static const bannerKey = ValueKey('due-banner');

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<RecurringDue>>(
      valueListenable: dues,
      builder: (context, list, _) {
        if (list.isEmpty) return const SizedBox.shrink();
        final scheme = Theme.of(context).colorScheme;
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Semantics(
            button: true,
            label: dueBannerSemantics(list),
            onTap: onTap,
            excludeSemantics: true,
            child: Material(
              key: bannerKey,
              color: scheme.secondaryContainer,
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.event_available_outlined,
                          color: scheme.onSecondaryContainer,
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: _text(context, list, scheme)),
                        Icon(
                          Icons.chevron_right,
                          color: scheme.onSecondaryContainer,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Один платёж: сокращается название, сумма в хвосте видна всегда. Несколько
  /// платежей: короткий текст «К оплате: 3 платежа».
  Widget _text(
    BuildContext context,
    List<RecurringDue> list,
    ColorScheme scheme,
  ) {
    final style = Theme.of(context).textTheme.bodyLarge
        ?.copyWith(color: scheme.onSecondaryContainer);
    if (list.length != 1) {
      return Text(
        dueBannerText(list),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }
    final payment = list.single.payment;
    return LayoutBuilder(
      builder: (context, constraints) => Row(
        children: [
          Flexible(
            child: Text(
              dueBannerHead(payment),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
          // Сумма не обрезается: в самом тесном случае она лишь уменьшается.
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.6),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(dueBannerTail(payment), style: style),
            ),
          ),
        ],
      ),
    );
  }
}
