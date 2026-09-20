import 'package:flutter/material.dart';
import 'package:money_app/core/format/date_format.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/format/money_spoken.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/theme/app_colors.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

/// Запас внизу «Главной» под сообщение SnackBar («Сохранено: расход 350,00 ₽ ·
/// Продукты · Отменить»), dp. Сообщение на узком телефоне (360 dp) занимает
/// около 108 dp: текст в три строки рядом с «Отменить». Кнопки лежат прямо над
/// нижней панелью, и без запаса сообщение закрывало бы кнопку «Расход» на
/// 6 секунд: следующий расход нельзя было бы ввести сразу.
const double _snackBarReserve = 112;

/// Главный экран: итог расходов за месяц и две крупные кнопки «Доход» и
/// «Расход».
///
/// Экран не знает, куда ведёт нажатие и откуда берутся суммы: об этом знает
/// только приложение (`lib/app`), которое передаёт [onAddTransaction] и поток
/// [monthExpenses]. Так фича `home` не зависит от маршрутов, репозиториев и
/// других экранов (ADR 0002).
class HomeScreen extends StatelessWidget {
  const HomeScreen({
    required this.onAddTransaction,
    required this.monthExpenses,
    required this.month,
    super.key,
  });

  final void Function(TransactionType type) onAddTransaction;

  /// Итог расходов за [month]. Поток должен быть один и тот же между
  /// перерисовками (его создаёт вызывающий), иначе подписка начнётся заново.
  final Stream<Money> monthExpenses;

  /// Любой день показываемого месяца: из него берётся название месяца.
  final DateOnly month;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    // Текст и знак на цветной кнопке берём цветом поверхности темы: в светлой
    // теме это почти белый на тёмно-зелёном/тёмно-красном, в тёмной — тёмный
    // на светлом. Контраст проверяет тест.
    final onAccent = Theme.of(context).colorScheme.surface;
    // Сообщение при крупном шрифте переносится на несколько строк и растёт,
    // поэтому запас растёт вместе со шрифтом (но не бесконечно).
    final reserve = MediaQuery.textScalerOf(context)
        .scale(_snackBarReserve)
        .clamp(_snackBarReserve, 160.0);

    return Padding(
      // Снизу отступа нет: его роль играет запас под SnackBar.
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        children: [
          // Верхняя часть прокручивается: при крупном шрифте на маленьком
          // экране она уступает место кнопкам, а не вызывает переполнение.
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _MonthExpenses(stream: monthExpenses, month: month),
                  // Этап 4: сюда встанет круговая диаграмма расходов по
                  // категориям (место под неё оставлено здесь, под итогом).
                ],
              ),
            ),
          ),
          // Кнопки внизу, в зоне большого пальца. «Расход» самый нижний:
          // им пользуются чаще всего.
          _TypeButton(
            label: 'Доход',
            semanticsLabel: 'Добавить доход',
            icon: Icons.add,
            background: colors.income,
            foreground: onAccent,
            onPressed: () => onAddTransaction(TransactionType.income),
          ),
          const SizedBox(height: 12),
          _TypeButton(
            label: 'Расход',
            semanticsLabel: 'Добавить расход',
            icon: Icons.remove,
            background: colors.expense,
            foreground: onAccent,
            onPressed: () => onAddTransaction(TransactionType.expense),
          ),
          // Запас под SnackBar: кнопки остаются выше сообщения.
          SizedBox(height: reserve),
        ],
      ),
    );
  }
}

/// Итог расходов месяца, пустое состояние или сообщение об ошибке.
class _MonthExpenses extends StatelessWidget {
  const _MonthExpenses({required this.stream, required this.month});

  final Stream<Money> stream;
  final DateOnly month;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.headlineSmall;
    return StreamBuilder<Money>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Text(
            'Не удалось посчитать расходы за месяц',
            textAlign: TextAlign.center,
            style: style,
          );
        }
        final total = snapshot.data;
        // Первого значения ещё нет: не показываем ничего, а не «расходов нет».
        // Пустое состояние означает «спросили базу, и там ноль».
        if (total == null) return const SizedBox.shrink();
        if (total.minorUnits == 0) {
          return Text(
            'В этом месяце расходов ещё нет',
            textAlign: TextAlign.center,
            style: style,
          );
        }
        final name = formatMonthName(month);
        // Скринридеру суммы читаем словами, а не «12 345,00 ₽» с символом.
        return Semantics(
          label: 'Расходы за $name: ${spokenMoney(total)}',
          excludeSemantics: true,
          child: Text(
            'Расходы за $name: ${formatMoney(total)}',
            textAlign: TextAlign.center,
            style: style,
          ),
        );
      },
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
        label: Text(label),
        style: FilledButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          // Высота не меньше 56 dp, при крупном шрифте кнопка растёт сама.
          minimumSize: const Size.fromHeight(56),
          textStyle: Theme.of(context).textTheme.titleMedium,
        ),
      ),
    );
  }
}
