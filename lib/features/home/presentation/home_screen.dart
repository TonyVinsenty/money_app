import 'package:flutter/material.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/font_scale.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/home/presentation/month_chart_card.dart';
import 'package:money_app/features/home/presentation/month_summary_card.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';

/// Главный экран: итоги расходов и доходов за месяц и диаграмма по категориям.
///
/// Кнопки «Доход» и «Расход» сюда не входят: они лежат в HomeActionBar над
/// нижней панелью, которую ставит каркас приложения (иначе сообщение SnackBar
/// закрывало бы их).
///
/// Экран не знает, куда ведут нажатия и откуда берутся суммы: об этом знает
/// только приложение (`lib/app`), которое передаёт [onOpenCategory] и потоки.
/// Так фича `home` не зависит от маршрутов, репозиториев и других экранов
/// (ADR 0002).
class HomeScreen extends StatelessWidget {
  const HomeScreen({
    required this.monthExpenses,
    required this.monthIncome,
    required this.monthTransactions,
    required this.categories,
    required this.month,
    required this.onOpenCategory,
    this.isCurrentMonth = true,
    this.onPreviousMonth,
    this.onNextMonth,
    super.key,
  });

  /// Показан текущий месяц (для текста пустой диаграммы).
  final bool isCurrentMonth;

  /// Стрелки переключателя месяца; `null` — стрелка недоступна. Откуда берётся
  /// месяц, экран не знает: это решает приложение (`lib/app`, ADR 0002).
  final VoidCallback? onPreviousMonth;
  final VoidCallback? onNextMonth;

  /// Выбраны категории на диаграмме или в легенде (id одной категории или
  /// группы): приложение показывает их расходы за [month] в «Истории».
  final ValueChanged<Set<String>> onOpenCategory;

  /// Итог расходов за [month]. Поток должен быть один и тот же между
  /// перерисовками (его создаёт вызывающий), иначе подписка начнётся заново.
  final Stream<Money> monthExpenses;

  /// Итог доходов за [month]; те же правила, что у [monthExpenses].
  final Stream<Money> monthIncome;

  /// Операции за [month] для диаграммы (те же правила про поток).
  final Stream<List<Transaction>> monthTransactions;

  /// Все категории, включая архивные: из них берутся названия в легенде.
  final Stream<List<Category>> categories;

  /// Любой день показываемого месяца: из него берётся название месяца.
  final DateOnly month;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Снизу отступа нет: он есть у панели кнопок под экраном.
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      // Середина прокручивается: при крупном шрифте на маленьком экране она
      // уступает место панели кнопок, а не вызывает переполнение.
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Кольцо как можно крупнее, но не выше видимой области (итоги выше
          // при этом прокручиваются).
          final ring = chartRingSize(
            viewportWidth: constraints.maxWidth,
            viewportHeight: constraints.maxHeight,
            textScale: fontScaleOf(context),
          );
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: MonthSummaryCard(
                    expenses: monthExpenses,
                    income: monthIncome,
                    month: month,
                    onPreviousMonth: onPreviousMonth,
                    onNextMonth: onNextMonth,
                  ),
                ),
              ),
              // Карточка кольца занимает остаток высоты до панели кнопок; если
              // содержимое выше остатка, она растёт и середина прокручивается.
              SliverFillRemaining(
                hasScrollBody: false,
                child: MonthChartCard(
                  transactions: monthTransactions,
                  categories: categories,
                  month: month,
                  isCurrentMonth: isCurrentMonth,
                  ringSize: ring,
                  onOpenCategory: onOpenCategory,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
