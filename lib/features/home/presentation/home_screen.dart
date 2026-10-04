import 'package:flutter/material.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/theme/app_colors.dart';
import 'package:money_app/features/home/presentation/chart_placeholder.dart';
import 'package:money_app/features/home/presentation/month_summary_card.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

/// Запас внизу «Главной» под сообщение SnackBar («Сохранено: расход 350,00 ₽ ·
/// Продукты · Отменить»), dp. Сообщение на узком телефоне (360 dp) занимает
/// около 108 dp: текст в три строки рядом с «Отменить». Кнопки лежат прямо над
/// нижней панелью, и без запаса сообщение закрывало бы кнопку «Расход» на
/// 6 секунд: следующий расход нельзя было бы ввести сразу.
const double _snackBarReserve = 112;

/// Минимальная высота заглушки под диаграмму, dp. Нужна, когда при крупном
/// шрифте итоги занимают почти весь экран: заглушка не сжимается в ноль.
const double _chartMinHeight = 120;

/// Высота кнопок «Доход» и «Расход», dp (с запасом сверх минимума 48).
const double _buttonHeight = 64;

/// Главный экран: итоги расходов и доходов за месяц, заглушка под будущую
/// диаграмму и две крупные кнопки «Доход» и «Расход» в одном ряду.
///
/// Экран не знает, куда ведёт нажатие и откуда берутся суммы: об этом знает
/// только приложение (`lib/app`), которое передаёт [onAddTransaction] и потоки
/// [monthExpenses] и [monthIncome]. Так фича `home` не зависит от маршрутов, репозиториев и
/// других экранов (ADR 0002).
class HomeScreen extends StatelessWidget {
  const HomeScreen({
    required this.onAddTransaction,
    required this.monthExpenses,
    required this.monthIncome,
    required this.month,
    super.key,
  });

  final void Function(TransactionType type) onAddTransaction;

  /// Итог расходов за [month]. Поток должен быть один и тот же между
  /// перерисовками (его создаёт вызывающий), иначе подписка начнётся заново.
  final Stream<Money> monthExpenses;

  /// Итог доходов за [month]; те же правила, что у [monthExpenses].
  final Stream<Money> monthIncome;

  /// Любой день показываемого месяца: из него берётся название месяца.
  final DateOnly month;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    // Сообщение при крупном шрифте переносится на несколько строк и растёт,
    // поэтому запас растёт вместе со шрифтом (но не бесконечно).
    final reserve = MediaQuery.textScalerOf(context)
        .scale(_snackBarReserve)
        .clamp(_snackBarReserve, 160.0);

    return Padding(
      // Снизу отступа нет: его роль играет запас под SnackBar.
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        // Растягиваем на всю ширину: иначе блок итогов сжимается по тексту и
        // встаёт по центру, а строки не прижимаются к левому краю.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Верхняя часть прокручивается: при крупном шрифте на маленьком
          // экране она уступает место кнопкам, а не вызывает переполнение.
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                // Минимум — высота всей области: заглушка растягивается на
                // свободную середину. Если контент выше, он прокручивается.
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  // IntrinsicHeight даёт колонке её естественную высоту, и
                  // Expanded внутри заполняет остаток.
                  child: IntrinsicHeight(
                    child: Column(
                      // Карточки и заглушку растягиваем на всю ширину, иначе
                      // они сжимаются по тексту.
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Расход — заливкой (главный показатель), доход — рамкой.
                        MonthSummaryCard(
                          key: const ValueKey('month-summary-expense'),
                          type: TransactionType.expense,
                          total: monthExpenses,
                          month: month,
                        ),
                        const SizedBox(height: 8),
                        MonthSummaryCard(
                          key: const ValueKey('month-summary-income'),
                          type: TransactionType.income,
                          total: monthIncome,
                          month: month,
                        ),
                        const SizedBox(height: 16),
                        // Заглушка занимает всю свободную середину. Этап 4:
                        // здесь встанет круговая диаграмма расходов.
                        Expanded(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: _chartMinHeight,
                            ),
                            child: ChartPlaceholder(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Кнопки в одном ряду, в зоне большого пальца: «Доход» слева,
          // «Расход» справа (ближе к правой руке, им пользуются чаще).
          Row(
            children: [
              Expanded(
                child: _TypeButton(
                  label: 'Доход',
                  semanticsLabel: 'Добавить доход',
                  icon: Icons.add,
                  background: colors.incomeAction,
                  foreground: colors.onIncomeAction,
                  onPressed: () => onAddTransaction(TransactionType.income),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _TypeButton(
                  label: 'Расход',
                  semanticsLabel: 'Добавить расход',
                  icon: Icons.remove,
                  background: colors.expenseAction,
                  foreground: colors.onExpenseAction,
                  onPressed: () => onAddTransaction(TransactionType.expense),
                ),
              ),
            ],
          ),
          // Запас под SnackBar: кнопки остаются выше сообщения.
          SizedBox(height: reserve),
        ],
      ),
    );
  }
}

class _TypeButton extends StatelessWidget {
  const _TypeButton({
    required this.label,
    required this.semanticsLabel,
    required this.icon,
    required this.background,
    required this.foreground,
    required this.onPressed,
  });

  final String label;
  final String semanticsLabel;
  final IconData icon;
  final Color background;
  final Color foreground;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    // excludeSemantics убирает из дерева для скринридера всё внутри (слово и
    // иконку), чтобы он прочитал только «Добавить расход», а не два раза.
    // Нажатие поэтому задано на самом узле.
    return Semantics(
      label: semanticsLabel,
      button: true,
      onTap: onPressed,
      excludeSemantics: true,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        // Подпись уменьшается, только если не влезает в половину ряда (очень
        // узкий экран): при обычном шрифте и на 360 dp она не меняется.
        label: FittedBox(fit: BoxFit.scaleDown, child: Text(label)),
        style: FilledButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          // Высота не меньше 64 dp, при крупном шрифте кнопка растёт сама.
          minimumSize: const Size.fromHeight(_buttonHeight),
          // Боковой отступ меньше обычного, чтобы две кнопки помещались в ряд.
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: Theme.of(context).textTheme.titleMedium,
        ),
      ),
    );
  }
}
