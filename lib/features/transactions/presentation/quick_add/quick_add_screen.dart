import 'package:flutter/material.dart';
import 'package:money_app/core/ui/amount_field.dart';
import 'package:money_app/core/ui/theme/app_colors.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

/// Экран быстрого ввода операции.
///
/// Тип операции виден тремя способами сразу, чтобы его нельзя было спутать:
/// словом («Новый расход»), цветом (цвет расхода/дохода из темы) и знаком
/// («−» или «+» перед заголовком и перед суммой).
class QuickAddScreen extends StatefulWidget {
  const QuickAddScreen({required this.type, super.key});

  final TransactionType type;

  static const incomeTitle = 'Новый доход';
  static const expenseTitle = 'Новый расход';

  /// Подпись видимой кнопки над клавиатурой. На iOS у числовой клавиатуры нет
  /// кнопки «Готово», поэтому продолжить нужно чем-то ещё.
  static const nextLabel = 'Далее';

  @override
  State<QuickAddScreen> createState() => _QuickAddScreenState();
}

class _QuickAddScreenState extends State<QuickAddScreen> {
  final _amount = AmountFieldController();

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  /// Попытка продолжить: и кнопка, и клавиша на клавиатуре идут через
  /// [AmountFieldController.submit]. Переход к выбору категории — шаг 2.23.
  void _next() {
    _amount.submit();
  }

  @override
  Widget build(BuildContext context) {
    final isIncome = widget.type == TransactionType.income;
    final accent = isIncome
        ? context.appColors.income
        : context.appColors.expense;
    final title = isIncome
        ? QuickAddScreen.incomeTitle
        : QuickAddScreen.expenseTitle;

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
      // Тело сжимается, когда появляется клавиатура, поэтому кнопка «Далее»
      // внизу всегда оказывается прямо над ней.
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    AmountField(
                      controller: _amount,
                      isIncome: isIncome,
                      autofocus: true,
                      // Клавиша «Далее» на клавиатуре уже делает submit();
                      // переход к категориям (шаг 2.23) появится здесь.
                    ),
                    // Шаги 2.22-2.25: здесь появятся дата, категория и
                    // комментарий.
                    const SizedBox(height: 24),
                    const Text('Здесь появится ввод суммы'),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _next,
                  child: const Text(QuickAddScreen.nextLabel),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
