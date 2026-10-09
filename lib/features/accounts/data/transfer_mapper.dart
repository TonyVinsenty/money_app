import 'package:money_app/core/database/app_database.dart';
import 'package:money_app/core/errors/data_corrupted_exception.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/features/accounts/domain/transfer.dart';
import 'package:money_app/features/accounts/domain/transfer_rules.dart';

/// Превращает строку базы в доменный [Transfer]; нарушение правил
/// превращается в [DataCorruptedException] с id строки.
Transfer transferFromRow(TransferRow row) {
  try {
    return Transfer(
      id: row.id,
      fromAccountId: row.fromAccountId,
      toAccountId: row.toAccountId,
      amount: Money.fromMinor(row.amountMinor, row.currency),
      occurredOn: row.occurredOn,
      occurredAt: DateTime.fromMillisecondsSinceEpoch(
        row.occurredAt,
        isUtc: true,
      ),
      note: row.note,
    );
  } catch (error) {
    if (error is TransferRuleException ||
        error is FormatException ||
        error is ArgumentError) {
      throw DataCorruptedException(
        'Transfer row "${row.id}" is corrupted: $error',
        cause: error,
      );
    }
    rethrow;
  }
}
