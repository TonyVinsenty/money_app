import 'package:money_app/core/money/parse_amount.dart';

/// Ошибка всего файла: дальше его не разбираем. Текстов для пользователя
/// здесь нет, их подбирает экран по типу ошибки.
sealed class CsvFileFailure {
  const CsvFileFailure();
}

/// Файл не в UTF-8 (например, Excel сохранил в кодировке Windows).
final class CsvNotUtf8 extends CsvFileFailure {
  const CsvNotUtf8();
}

/// Нарушена разметка CSV (кавычки, переносы). [message] — для разработчика.
final class CsvMalformed extends CsvFileFailure {
  const CsvMalformed(this.message);

  final String message;
}

/// В файле нет ни одного символа.
final class CsvEmptyFile extends CsvFileFailure {
  const CsvEmptyFile();
}

/// Нет обязательных колонок; [columns] — их имена как в экспорте.
final class CsvMissingColumns extends CsvFileFailure {
  const CsvMissingColumns(this.columns);

  final List<String> columns;
}

/// Колонка [column] встречается в заголовках больше одного раза.
final class CsvDuplicateColumn extends CsvFileFailure {
  const CsvDuplicateColumn(this.column);

  final String column;
}

/// Какая из колонок `ID …` испорчена.
enum CsvIdColumn { transaction, category, subcategory }

/// Ошибка одной строки. [line] — номер строки как в Excel (заголовки — 1),
/// [value] — исходное значение поля (для дубля ID — сам ID).
sealed class CsvRowError {
  const CsvRowError(this.line, this.value);

  final int line;
  final String value;
}

/// Дата не `Д.М.ГГГГ` или такого дня нет в календаре.
final class CsvInvalidDate extends CsvRowError {
  const CsvInvalidDate(super.line, super.value);
}

/// Дата позже сегодняшней.
final class CsvFutureDate extends CsvRowError {
  const CsvFutureDate(super.line, super.value);
}

/// Тип не `Расход` и не `Доход`.
final class CsvInvalidType extends CsvRowError {
  const CsvInvalidType(super.line, super.value);
}

/// Сумма не разобралась; [failure] — причина из `parseAmount`.
final class CsvInvalidAmount extends CsvRowError {
  const CsvInvalidAmount(super.line, super.value, this.failure);

  final AmountParseFailure failure;
}

/// Минус у дохода: минус допустим только у расхода.
final class CsvNegativeIncome extends CsvRowError {
  const CsvNegativeIncome(super.line, super.value);
}

/// Валюта не пустая и не `RUB`.
final class CsvUnsupportedCurrency extends CsvRowError {
  const CsvUnsupportedCurrency(super.line, super.value);
}

/// Категория пустая.
final class CsvEmptyCategory extends CsvRowError {
  const CsvEmptyCategory(super.line, super.value);
}

/// Категория длиннее лимита имени.
final class CsvCategoryTooLong extends CsvRowError {
  const CsvCategoryTooLong(super.line, super.value);
}

/// Подкатегория длиннее лимита имени.
final class CsvSubcategoryTooLong extends CsvRowError {
  const CsvSubcategoryTooLong(super.line, super.value);
}

/// Комментарий длиннее лимита.
final class CsvNoteTooLong extends CsvRowError {
  const CsvNoteTooLong(super.line, super.value);
}

/// Значение в колонке `ID …` не похоже на UUID.
final class CsvInvalidId extends CsvRowError {
  const CsvInvalidId(super.line, super.value, this.column);

  final CsvIdColumn column;
}

/// Тот же `ID операции` уже встречался выше в файле.
final class CsvDuplicateTransactionId extends CsvRowError {
  const CsvDuplicateTransactionId(super.line, super.value);
}
