/// Итог загрузки из CSV: что добавлено в приложение. Экран загрузки закрывается
/// с этим значением, «Настройки» по нему пишут сообщение.
final class CsvImportResult {
  const CsvImportResult({
    required this.transactions,
    this.accounts = 0,
    this.transfers = 0,
    this.recurring = 0,
  });

  /// Сколько регулярных платежей добавлено.
  final int recurring;

  /// Сколько операций добавлено.
  final int transactions;

  /// Сколько счетов создано.
  final int accounts;

  /// Сколько переводов добавлено.
  final int transfers;

  @override
  bool operator ==(Object other) =>
      other is CsvImportResult &&
      other.transactions == transactions &&
      other.accounts == accounts &&
      other.transfers == transfers &&
      other.recurring == recurring;

  @override
  int get hashCode => Object.hash(transactions, accounts, transfers, recurring);

  @override
  String toString() =>
      'CsvImportResult(transactions: $transactions, accounts: $accounts, '
      'transfers: $transfers, recurring: $recurring)';
}
