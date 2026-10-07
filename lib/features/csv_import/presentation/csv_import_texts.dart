import 'package:intl/intl.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/format/percent_format.dart';
import 'package:money_app/core/money/currency.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/money/parse_amount.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/categories/domain/category_rules.dart';
import 'package:money_app/features/csv_import/domain/csv_import_failures.dart';
import 'package:money_app/features/export/domain/transactions_export.dart';
import 'package:money_app/features/transactions/domain/transaction_rules.dart';

/// Тексты экрана загрузки из CSV (шаг i.15). Здесь же — как превратить ошибки
/// разбора и плана в понятные пользователю строки.

const csvImportTitle = 'Загрузка из CSV';
const csvImportCheckingLabel = 'Проверяем файл…';
const csvImportWritingLabel = 'Загружаем…';
const csvImportLoadButton = 'Загрузить';
const csvImportCancelButton = 'Отмена';
const csvImportCloseButton = 'Закрыть';

const csvImportReadFailedMessage =
    'Не удалось прочитать файл. Попробуйте выбрать его ещё раз';
const csvImportWriteFailedMessage =
    'Не удалось загрузить. Ничего не добавлено, попробуйте ещё раз';
const csvImportErrorsIntro =
    'В файле есть ошибки, поэтому ничего не загружено. '
    'Исправьте их в файле и загрузите его снова.';
const csvImportNoRowsMessage =
    'В файле нет операций: есть только строка с названиями колонок';
const csvImportNothingToAddMessage =
    'Нечего добавлять: все операции из файла уже есть в приложении';
const csvImportNewCategoriesTitle = 'Будут созданы категории';

/// Сколько ошибок строк показывать; остальные — одной строкой «… и ещё K».
const csvImportShownErrorsLimit = 20;

/// Самое длинное значение поля, которое цитируем в ошибке целиком.
const _quotedMaxLength = 30;

final NumberFormat _countFormat = NumberFormat.decimalPattern('ru');

/// Число с разделителем разрядов: «1 234».
String formatCount(int n) => _countFormat.format(n);

String csvImportMoreErrors(int count) => '… и ещё ${formatCount(count)}';

/// «Будет добавлена 1 операция», «Будут добавлены 2 операции»,
/// «Будет добавлено 5 операций».
String csvImportWillAdd(int count) {
  final verb = pluralRu(
    count,
    'Будет добавлена',
    'Будут добавлены',
    'Будет добавлено',
  );
  final noun = pluralRu(count, 'операция', 'операции', 'операций');
  return '$verb ${formatCount(count)} $noun';
}

String csvImportSkippedExisting(int count) =>
    'Пропущено (уже есть в приложении): ${formatCount(count)}';

String csvImportSkippedDeleted(int count) =>
    'Пропущено (удалены в приложении): ${formatCount(count)}';

/// Новые категории одного вида для предпросмотра: заголовок вида и строки.
typedef CsvImportCategoryGroup = ({String title, List<String> lines});

/// Список новых категорий: сначала расходы, потом доходы. Одна строка на
/// категорию верхнего уровня, по алфавиту: «Кафе: Кофе, Обед» (родитель уже
/// есть, новые только подкатегории), «Хобби (новая): Кисти, Краски»,
/// «Аптека (новая)». Родителя ищем среди новых категорий и среди
/// [existing]. Вида без новых категорий в списке нет.
List<CsvImportCategoryGroup> csvImportNewCategoryGroups(
  List<Category> toCreate,
  List<Category> existing,
) {
  final names = {
    for (final c in existing) c.id: c.name,
    for (final c in toCreate) c.id: c.name,
  };
  int byName(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());
  final groups = <CsvImportCategoryGroup>[];
  for (final (kind, title) in [
    (CategoryKind.expense, 'Расходы'),
    (CategoryKind.income, 'Доходы'),
  ]) {
    // id категории верхнего уровня → новая ли она и её новые подкатегории.
    final isNew = <String, bool>{};
    final subs = <String, List<String>>{};
    for (final c in toCreate) {
      if (c.kind != kind) continue;
      final topId = c.parentId ?? c.id;
      isNew[topId] = (isNew[topId] ?? false) || c.parentId == null;
      if (c.parentId != null) (subs[topId] ??= []).add(c.name);
    }
    final lines = [
      for (final topId in isNew.keys)
        _newCategoryLine(
          names[topId] ?? '?',
          isNew: isNew[topId]!,
          subs: (subs[topId] ?? [])..sort(byName),
        ),
    ]..sort(byName);
    if (lines.isNotEmpty) groups.add((title: title, lines: lines));
  }
  return groups;
}

String _newCategoryLine(
  String name, {
  required bool isNew,
  required List<String> subs,
}) {
  final head = isNew ? '$name (новая)' : name;
  return subs.isEmpty ? head : '$head: ${subs.join(', ')}';
}

/// Ошибка всего файла: что случилось и что сделать.
String csvFileFailureMessage(CsvFileFailure failure) => switch (failure) {
  CsvNotUtf8() =>
    'Файл сохранён не в той кодировке. В Excel сохраните его заново: '
        '«Файл» → «Сохранить как» → тип «CSV UTF-8 (разделитель - запятая)»',
  CsvMalformed() =>
    'Не получилось разобрать файл: похоже, в нём не закрыта кавычка. '
        'Откройте его в таблице и сохраните заново как CSV',
  CsvEmptyFile() => 'Файл пустой',
  CsvMissingColumns(:final columns) =>
    '${columns.length == 1 ? 'Нет обязательной колонки' : 'Нет обязательных колонок:'} '
        '${columns.map((c) => '«$c»').join(', ')}. '
        'В первой строке файла должны быть названия колонок, как в экспорте Zuno',
  CsvDuplicateColumn(:final column) =>
    'Колонка «$column» встречается в первой строке дважды. Оставьте одну',
};

/// Ошибка строки: «Строка 15: сумма «12.3.4» — не число».
String csvRowErrorMessage(CsvRowError error) =>
    'Строка ${error.line}: ${_rowErrorText(error)}';

String _rowErrorText(CsvRowError error) {
  final value = _quoted(error.value);
  return switch (error) {
    CsvInvalidDate() =>
      value == null
          ? 'не указана дата'
          : 'дата $value — нужна настоящая дата в виде ДД.ММ.ГГГГ',
    CsvFutureDate() => 'дата $value ещё не наступила',
    CsvInvalidType() =>
      value == null
          ? 'не указан тип'
          : 'тип $value — нужен «Расход» или «Доход»',
    CsvInvalidAmount(:final failure) =>
      value == null
          ? 'не указана сумма'
          : 'сумма $value — ${_amountReason(failure)}',
    CsvNegativeIncome() =>
      'сумма $value — минус можно ставить только у расхода',
    CsvUnsupportedCurrency() =>
      'валюта $value — пока поддерживаются только рубли: '
          '$rubCurrencyCode или пусто',
    CsvEmptyCategory() => 'не указана категория',
    CsvCategoryTooLong() => 'категория длиннее $categoryNameMaxLength символов',
    CsvSubcategoryTooLong() =>
      'подкатегория длиннее $categoryNameMaxLength символов',
    CsvNoteTooLong() =>
      'комментарий длиннее $transactionNoteMaxLength символов',
    CsvInvalidId(:final column) =>
      'в колонке «${_idColumnName(column)}» не ID. Очистите эту ячейку',
    CsvDuplicateTransactionId() =>
      '«$csvColumnTransactionId» повторяется: такой уже есть выше в файле',
    CsvCategoryKindMismatch() =>
      '«$csvColumnCategoryId» указывает на категорию другого типа '
          '(доход вместо расхода или наоборот). Очистите эту ячейку',
    CsvCategoryIdIsSubcategory() =>
      '«$csvColumnCategoryId» указывает на подкатегорию. Очистите эту ячейку',
    CsvSubcategoryWrongParent() =>
      '«$csvColumnSubcategoryId» указывает на подкатегорию другой категории. '
          'Очистите эту ячейку',
    CsvExtraCells(:final value) =>
      value == ','
          ? 'ячеек больше, чем колонок. Похоже, сумма или текст с запятой '
                'без кавычек: нужно "350,50"'
          : 'ячеек больше, чем колонок. Похоже, в тексте есть «;» '
                'без кавычек вокруг ячейки',
  };
}

/// Короткая причина для суммы. Тексты ввода суммы (`amountFailureMessage`)
/// говорят о поле и кнопках экрана, здесь нужны короче и про файл.
String _amountReason(AmountParseFailure failure) => switch (failure) {
  AmountParseFailure.empty => 'нет цифр',
  AmountParseFailure.notANumber => 'не число',
  AmountParseFailure.negative => 'лишний минус',
  AmountParseFailure.tooManyDecimals => 'больше двух цифр после запятой',
  AmountParseFailure.tooManySeparators => 'слишком много запятых или точек',
  AmountParseFailure.tooLarge =>
    'слишком большая (не больше ${formatMoney(Money.fromMajorParts(maxInputMajorUnits, 0, rubCurrencyCode))})',
};

String _idColumnName(CsvIdColumn column) => switch (column) {
  CsvIdColumn.transaction => csvColumnTransactionId,
  CsvIdColumn.category => csvColumnCategoryId,
  CsvIdColumn.subcategory => csvColumnSubcategoryId,
};

/// Значение в кавычках-ёлочках; длинное обрезается с «…»; пустое — `null`.
String? _quoted(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  final runes = trimmed.runes.toList();
  final short = runes.length <= _quotedMaxLength
      ? trimmed
      : '${String.fromCharCodes(runes.take(_quotedMaxLength))}…';
  return '«$short»';
}
