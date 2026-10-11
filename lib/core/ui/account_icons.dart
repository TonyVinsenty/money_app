import 'package:flutter/material.dart';
import 'package:money_app/core/ui/avatar_glyph.dart';

/// Один значок счёта: ключ (его хранит база), иконка и подпись для человека.
class AccountIconOption {
  const AccountIconOption(this.key, this.icon, this.label);

  /// Ключ в базе. Менять нельзя: счета уже записаны с этими ключами.
  final String key;
  final IconData icon;
  final String label;
}

/// Ключ значка «Другое»: на него падает любой неизвестный ключ.
const String otherAccountIconKey = 'other';

/// Постоянный набор значков счетов. Порядок — порядок в форме выбора.
const List<AccountIconOption> accountIconOptions = [
  AccountIconOption('card', Icons.credit_card, 'Карта'),
  AccountIconOption('cash', Icons.payments, 'Наличные'),
  AccountIconOption('wallet', Icons.account_balance_wallet, 'Кошелёк'),
  AccountIconOption('bank', Icons.account_balance, 'Банк'),
  AccountIconOption('piggy', Icons.savings, 'Копилка'),
  AccountIconOption('deposit', Icons.lock_clock, 'Вклад'),
  AccountIconOption('credit', Icons.request_quote, 'Кредит'),
  AccountIconOption(otherAccountIconKey, Icons.more_horiz, 'Другое'),
];

/// Значок счёта: иконка по ключу, а для «Другое» - первая буква названия
/// (см. `avatarGlyph`). Скрыт от скринридера: подпись даёт строка вокруг.
class AccountIconView extends StatelessWidget {
  const AccountIconView(
    this.iconKey, {
    super.key,
    this.name,
    this.size,
    this.color,
  });

  final String iconKey;
  final String? name;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final side = size ?? iconTheme.size ?? 24.0;
    final tint = color ?? iconTheme.color;
    final known = accountIconOptions.any((o) => o.key == iconKey);
    final glyph = avatarGlyph(
      known ? iconKey : otherAccountIconKey,
      name,
      otherKey: otherAccountIconKey,
    );
    if (glyph == null) {
      return ExcludeSemantics(
        child: Icon(accountIconFor(iconKey).icon, size: size, color: color),
      );
    }
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: side,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            glyph,
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              fontSize: side * 0.8,
              height: 1,
              fontWeight: FontWeight.bold,
              color: tint,
            ),
          ),
        ),
      ),
    );
  }
}

/// Значок по ключу; неизвестный ключ — «Другое».
AccountIconOption accountIconFor(String key) {
  for (final option in accountIconOptions) {
    if (option.key == key) return option;
  }
  return accountIconOptions.last;
}
