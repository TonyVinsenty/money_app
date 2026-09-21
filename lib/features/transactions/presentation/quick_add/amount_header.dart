import 'package:flutter/material.dart';
import 'package:money_app/core/format/day_label.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/format/money_spoken.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';

/// Введённая сумма крупно (знак, число, валюта) и под ней день операции.
/// Общая шапка экранов выбора категории и подкатегории.
class AmountHeader extends StatelessWidget {
  const AmountHeader({
    required this.amount,
    required this.day,
    required this.today,
    required this.isIncome,
    required this.color,
    super.key,
  });

  final Money amount;
  final DateOnly day;
  final DateOnly today;
  final bool isIncome;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final sign = isIncome ? '+' : String.fromCharCode(0x2212);
    final style = Theme.of(context).textTheme.displaySmall
        ?.copyWith(color: color, fontWeight: FontWeight.w600);
    final word = isIncome ? 'Доход' : 'Расход';
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Column(
        children: [
          Semantics(
            label: '$word ${spokenMoney(amount)}',
            child: ExcludeSemantics(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('$sign${formatMoney(amount)}', style: style),
              ),
            ),
          ),
          // День операции: «Сегодня», «Вчера» или дата. Скринридер читает его
          // отдельной строкой.
          const SizedBox(height: 4),
          Text(
            dayLabel(day, today: today),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
