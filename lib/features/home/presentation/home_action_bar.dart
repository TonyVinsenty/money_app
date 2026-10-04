import 'package:flutter/material.dart';
import 'package:money_app/core/ui/theme/app_colors.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

/// Высота кнопок «Доход» и «Расход», dp (с запасом сверх минимума 48).
const double _buttonHeight = 64;

/// Панель с двумя крупными кнопками «Доход» и «Расход» в одном ряду.
///
/// Каркас приложения ставит её прямо над нижней панелью навигации, в том же
/// слоте `bottomNavigationBar`: Flutter кладёт SnackBar над этим слотом целиком,
/// поэтому сообщение «Сохранено...» не закрывает кнопки, и следующий расход
/// можно вводить сразу. Что делает нажатие, решает приложение ([onAddTransaction]).
class HomeActionBar extends StatelessWidget {
  const HomeActionBar({required this.onAddTransaction, super.key});

  final void Function(TransactionType type) onAddTransaction;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    // Кнопки в одном ряду, в зоне большого пальца: «Доход» слева, «Расход»
    // справа (ближе к правой руке, им пользуются чаще). Отступ снизу 16 dp до
    // панели навигации.
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
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
