import 'package:flutter/material.dart';
import 'package:money_app/core/time/clock.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/amount_field.dart';
import 'package:money_app/core/ui/date_chip.dart';
import 'package:money_app/core/ui/theme/app_colors.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

/// Экран быстрого ввода операции.
///
/// Тип операции виден тремя способами сразу, чтобы его нельзя было спутать:
/// словом («Новый расход»), цветом (цвет расхода/дохода из темы) и знаком
/// («−» или «+» перед заголовком и перед суммой).
class QuickAddScreen extends StatefulWidget {
  const QuickAddScreen({required this.type, required this.clock, super.key});

  final TransactionType type;

  /// Источник «сегодня» для плашки даты. Приходит из `AppServices.clock` через
  /// маршрут (`lib/app`): фича не знает про `AppScope`, а в тестах сюда
  /// подставляются фиксированные часы.
  final Clock clock;

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

  /// «Сегодня» на момент открытия экрана. Если экран простоит открытым через
  /// полночь, «сегодня» и выбранный день намеренно не обновляются: ввод
  /// занимает секунды, а при сохранении (шаг 2.25) момент всё равно берётся из
  /// часов через `Occurrence.onDay`.
  late final DateOnly _today;

  /// Выбранный день операции. При сохранении (шаг 2.25) из него и из часов
  /// выводятся обе величины операции: `Occurrence.onDay(_day, clock: ...)`.
  late DateOnly _day;

  @override
  void initState() {
    super.initState();
    _today = widget.clock.today();
    _day = _today;
  }

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
                    const SizedBox(height: 8),
                    DateChip(
                      value: _day,
                      today: _today,
                      onChanged: (day) => setState(() => _day = day),
                    ),
                    // Шаги 2.23-2.25: здесь появятся категория и комментарий.
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
