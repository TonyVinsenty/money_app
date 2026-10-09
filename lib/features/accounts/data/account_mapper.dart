import 'package:drift/drift.dart';
import 'package:money_app/core/database/app_database.dart';
import 'package:money_app/core/errors/data_corrupted_exception.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/accounts/domain/account_rules.dart';

/// Превращает строку базы в доменный [Account].
///
/// Нарушение правил (пустое имя, плохая валюта и т. п.) превращается в
/// [DataCorruptedException] с id строки и причиной в `cause`.
Account accountFromRow(AccountRow row) {
  try {
    final archivedAt = row.archivedAt;
    return Account(
      id: row.id,
      name: row.name,
      iconKey: row.iconKey,
      openingBalance: Money.fromMinor(row.openingBalanceMinor, row.currency),
      sortOrder: row.sortOrder,
      currencyDigits: row.currencyDigits,
      archivedAt: archivedAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(archivedAt, isUtc: true),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        row.createdAt,
        isUtc: true,
      ),
    );
  } catch (error) {
    if (error is AccountRuleException ||
        error is FormatException ||
        error is ArgumentError) {
      throw DataCorruptedException(
        'Account row "${row.id}" is corrupted: $error',
        cause: error,
      );
    }
    rethrow;
  }
}

/// Набор колонок для вставки нового счёта; времена приходят из `Clock`.
AccountsCompanion accountToCompanion(
  Account account, {
  required DateTime createdAt,
  required DateTime updatedAt,
}) {
  return AccountsCompanion.insert(
    id: account.id,
    name: account.name,
    iconKey: account.iconKey,
    currency: account.openingBalance.currency,
    currencyDigits: account.currencyDigits,
    openingBalanceMinor: account.openingBalance.minorUnits,
    sortOrder: account.sortOrder,
    createdAt: createdAt.toUtc().millisecondsSinceEpoch,
    updatedAt: updatedAt.toUtc().millisecondsSinceEpoch,
    archivedAt: Value(account.archivedAt?.toUtc().millisecondsSinceEpoch),
  );
}
