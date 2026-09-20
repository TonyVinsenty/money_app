import 'package:flutter/material.dart';
import 'package:money_app/core/ui/theme/app_colors.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

/// Экран быстрого ввода операции.
///
/// Тип операции виден тремя способами сразу, чтобы его нельзя было спутать:
/// словом («Новый расход»), цветом (цвет расхода/дохода из темы) и знаком
/// («−» или «+» перед заголовком).
class QuickAddScreen extends StatelessWidget {
  const QuickAddScreen({required this.type, super.key});

  final TransactionType type;

  static const incomeTitle = 'Новый доход';
  static const expenseTitle = 'Новый расход';

  @override
  Widget build(BuildContext context) {
    final isIncome = type == TransactionType.income;
    final accent = isIncome
        ? context.appColors.income
        : context.appColors.expense;
    final title = isIncome ? incomeTitle : expenseTitle;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Знак — для глаз; скринридеру он не нужен, слово читается в
            // заголовке.
            ExcludeSemantics(
              child: Icon(isIncome ? Icons.add : Icons.remove, color: accent),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                title,
                style: TextStyle(color: accent, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
      // Шаги 2.19-2.25: здесь появятся сумма, дата, категория и комментарий.
      body: const Center(child: Text('Здесь появится ввод суммы')),
    );
  }
}
