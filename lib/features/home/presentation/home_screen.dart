import 'package:flutter/material.dart';
import 'package:money_app/core/ui/theme/app_colors.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

/// Главный экран: две крупные кнопки «Доход» и «Расход».
///
/// Экран не знает, куда ведёт нажатие: об этом знает только приложение
/// (`lib/app`), которое передаёт [onAddTransaction]. Так фича `home` не
/// зависит от маршрутов и других экранов (ADR 0002).
class HomeScreen extends StatelessWidget {
  const HomeScreen({required this.onAddTransaction, super.key});

  final void Function(TransactionType type) onAddTransaction;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    // Текст и знак на цветной кнопке берём цветом поверхности темы: в светлой
    // теме это почти белый на тёмно-зелёном/тёмно-красном, в тёмной — тёмный
    // на светлом. Контраст проверяет тест.
    final onAccent = Theme.of(context).colorScheme.surface;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Шаг 2.26: сюда встанет диаграмма расходов и итог месяца.
          const Spacer(),
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
