import 'package:flutter/material.dart';

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

/// Значок по ключу; неизвестный ключ — «Другое».
AccountIconOption accountIconFor(String key) {
  for (final option in accountIconOptions) {
    if (option.key == key) return option;
  }
  return accountIconOptions.last;
}
