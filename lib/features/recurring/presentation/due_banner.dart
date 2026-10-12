import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:money_app/core/ui/font_scale.dart';
import 'package:money_app/core/ui/masked_amount.dart';
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

  /// Ключ текста суммы одного платежа (для тестов раскладки).
  static const amountKey = ValueKey('due-banner-amount');

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
            label: dueBannerSemantics(
              list,
              hidden: AmountsVisibility.hiddenOf(context),
            ),
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

  /// Текст плашки ничего не обрезает: название переносится на сколько угодно
  /// строк. Один платёж: сумма в хвосте строки, при крупном шрифте - под
  /// названием. Несколько платежей: короткий текст «К оплате: 3 платежа».
  Widget _text(
    BuildContext context,
    List<RecurringDue> list,
    ColorScheme scheme,
  ) {
    final style = Theme.of(context).textTheme.bodyLarge
        ?.copyWith(color: scheme.onSecondaryContainer);
    final hidden = AmountsVisibility.hiddenOf(context);
    if (list.length != 1) {
      return Text(dueBannerText(list, hidden: hidden), style: style);
    }
    final payment = list.single.payment;
    final head = Text(dueBannerHead(payment), style: style);
    if (useTwoLineRows(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          head,
          // Сумма в полный размер; уменьшается только сумма шире строки
          // (иначе число разорвалось бы).
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              dueBannerAmount(payment, hidden: hidden),
              key: amountKey,
              style: style,
            ),
          ),
        ],
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) => Row(
        children: [
          Flexible(child: head),
          // Сумма не обрезается: в самом тесном случае она лишь уменьшается.
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.6),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                dueBannerTail(payment, hidden: hidden),
                key: amountKey,
                style: style,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
