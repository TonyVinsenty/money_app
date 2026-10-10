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
enum CsvIdColumn {
  transaction,
  category,
  subcategory,
  account,
  transferAccount,
}

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

/// Тип не `Расход`, `Доход`, `Начальный остаток` и не `Перевод`.
final class CsvInvalidType extends CsvRowError {
  const CsvInvalidType(super.line, super.value);
}

/// Сумма не разобралась; [failure] — причина из `parseAmount`.
///
/// [currencyCode] и [currencyDigits] — валюта строки и её знаки после запятой
/// (для текстов про лишние цифры и предел суммы). [digitsFromFile] — знаки
/// взяты из самой суммы, потому что валюта своя и новая.
final class CsvInvalidAmount extends CsvRowError {
  const CsvInvalidAmount(
    super.line,
    super.value,
    this.failure, {
    this.currencyCode = 'RUB',
    this.currencyDigits = 2,
    this.digitsFromFile = false,
  });

  final AmountParseFailure failure;
  final String currencyCode;
  final int currencyDigits;
  final bool digitsFromFile;
}

/// Минус у дохода: минус допустим только у расхода и начального остатка.
final class CsvNegativeIncome extends CsvRowError {
  const CsvNegativeIncome(super.line, super.value);
}

/// У дохода или расхода валюта не обычная валюта каталога (и не пусто).
final class CsvUnsupportedCurrency extends CsvRowError {
  const CsvUnsupportedCurrency(super.line, super.value);
}

/// У `Начальный остаток` код валюты не подходит под правило кода
/// (3–10 латинских букв и цифр, первая — буква).
final class CsvInvalidCurrencyCode extends CsvRowError {
  const CsvInvalidCurrencyCode(super.line, super.value);
}

/// Имя счёта длиннее лимита.
final class CsvAccountTooLong extends CsvRowError {
  const CsvAccountTooLong(super.line, super.value);
}

/// У `Начальный остаток` не указан `Счёт`.
final class CsvOpeningBalanceNoAccount extends CsvRowError {
  const CsvOpeningBalanceNoAccount(super.line, super.value);
}

/// У `Начальный остаток` заполнена `Категория` ([value]) — колонки съехали.
final class CsvOpeningBalanceWithCategory extends CsvRowError {
  const CsvOpeningBalanceWithCategory(super.line, super.value);
}

/// Второй `Начальный остаток` на тот же счёт; [value] — имя счёта,
/// [firstLine] — строка первого остатка.
final class CsvDuplicateOpeningBalance extends CsvRowError {
  const CsvDuplicateOpeningBalance(super.line, super.value, this.firstLine);

  final int firstLine;
}

/// Валюта строки ([value], пустая — `RUB`) не совпадает с валютой счёта.
final class CsvAccountCurrencyMismatch extends CsvRowError {
  const CsvAccountCurrencyMismatch(
    super.line,
    super.value,
    this.accountName,
    this.accountCurrency,
  );

  final String accountName;
  final String accountCurrency;
}

/// `ID счёта` ([value]) не найден в базе, а имя счёта в строке не указано.
final class CsvAccountIdNotFound extends CsvRowError {
  const CsvAccountIdNotFound(super.line, super.value);
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

/// `ID категории` указывает на категорию другого вида, чем `Тип` строки.
final class CsvCategoryKindMismatch extends CsvRowError {
  const CsvCategoryKindMismatch(super.line, super.value);
}

/// `ID категории` указывает на подкатегорию.
final class CsvCategoryIdIsSubcategory extends CsvRowError {
  const CsvCategoryIdIsSubcategory(super.line, super.value);
}

/// `ID подкатегории` указывает на категорию верхнего уровня или на
/// подкатегорию другой категории.
final class CsvSubcategoryWrongParent extends CsvRowError {
  const CsvSubcategoryWrongParent(super.line, super.value);
}

/// В строке больше непустых ячеек, чем колонок в заголовке. [value] —
/// разделитель файла (`;` или `,`): от него зависит подсказка.
final class CsvExtraCells extends CsvRowError {
  const CsvExtraCells(super.line, super.value);
}

/// У `Перевод` не указан `Счёт` (откуда): ни имени, ни ID.
final class CsvTransferNoAccount extends CsvRowError {
  const CsvTransferNoAccount(super.line, super.value);
}

/// У `Перевод` не указан `Счёт зачисления` (куда): ни имени, ни ID.
final class CsvTransferNoToAccount extends CsvRowError {
  const CsvTransferNoToAccount(super.line, super.value);
}

/// У `Перевод` счёт и счёт зачисления совпадают (по имени или по ID).
final class CsvTransferSameAccount extends CsvRowError {
  const CsvTransferSameAccount(super.line, super.value);
}

/// У `Перевод` сумма 0 ([value] — как в файле).
final class CsvTransferZeroAmount extends CsvRowError {
  const CsvTransferZeroAmount(super.line, super.value);
}

/// У `Перевод` заполнена `Категория` ([value]) — колонки съехали.
final class CsvTransferWithCategory extends CsvRowError {
  const CsvTransferWithCategory(super.line, super.value);
}

/// `ID счёта зачисления` ([value]) не найден в базе, а имени счёта нет.
final class CsvTransferToAccountIdNotFound extends CsvRowError {
  const CsvTransferToAccountIdNotFound(super.line, super.value);
}

/// Перевод в своей валюте [value], которой нет ни у одного счёта и для
/// которой в файле нет строки `Начальный остаток`: знаки не известны.
final class CsvTransferCurrencyNoOpeningBalance extends CsvRowError {
  const CsvTransferCurrencyNoOpeningBalance(super.line, super.value);
}
