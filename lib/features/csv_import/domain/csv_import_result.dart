/// Итог загрузки из CSV: что добавлено в приложение. Экран загрузки закрывается
/// с этим значением, «Настройки» по нему пишут сообщение.
final class CsvImportResult {
  const CsvImportResult({
    required this.transactions,
    this.accounts = 0,
    this.transfers = 0,
  });

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
      other.transfers == transfers;

  @override
  int get hashCode => Object.hash(transactions, accounts, transfers);

  @override
  String toString() =>
      'CsvImportResult(transactions: $transactions, accounts: $accounts, '
      'transfers: $transfers)';
}
