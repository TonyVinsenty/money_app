/// Итог загрузки из CSV: что добавлено в приложение. Экран загрузки закрывается
/// с этим значением, «Настройки» по нему пишут сообщение.
final class CsvImportResult {
  const CsvImportResult({required this.transactions, this.accounts = 0});

  /// Сколько операций добавлено.
  final int transactions;

  /// Сколько счетов создано.
  final int accounts;

  @override
  bool operator ==(Object other) =>
      other is CsvImportResult &&
      other.transactions == transactions &&
      other.accounts == accounts;

  @override
  int get hashCode => Object.hash(transactions, accounts);

  @override
  String toString() =>
      'CsvImportResult(transactions: $transactions, accounts: $accounts)';
}
