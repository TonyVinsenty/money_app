/// Данные в хранилище испорчены: их нельзя превратить в сущность.
///
/// Например, в базе лежит категория с неизвестным видом или подкатегория,
/// чей родитель не найден. Репозитории превращают такие случаи в эту
/// ошибку, чтобы верхние слои не разбирали детали хранилища.
final class DataCorruptedException implements Exception {
  const DataCorruptedException(this.message, {this.cause});

  /// Описание проблемы по-английски.
  final String message;

  /// Исходная ошибка, если она есть (например, `CategoryRuleException`).
  final Object? cause;

  @override
  String toString() {
    final cause = this.cause;
    return cause == null
        ? 'DataCorruptedException: $message'
        : 'DataCorruptedException: $message (cause: $cause)';
  }
}
