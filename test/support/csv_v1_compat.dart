import 'package:money_app/core/csv/csv_codec.dart';
import 'package:money_app/features/export/domain/transactions_export.dart';

/// Заголовки формата v1 (ADR 0006, 11 колонок): так записан тестовый набор.
const List<String> csvV1Headers = [
  csvColumnDate,
  csvColumnType,
  csvColumnAmount,
  csvColumnCurrency,
  csvColumnCategory,
  csvColumnSubcategory,
  csvColumnNote,
  csvColumnTransactionId,
  csvColumnCategoryId,
  csvColumnSubcategoryId,
  csvColumnOccurredAtUtc,
];

/// Номера колонок v2 (с нуля).
const int csvV2IconColumn = 15;
const int csvV2SubcategoryIconColumn = 16;

/// v1-файл в виде v2 без значков: вставлены пустые колонки счёта
/// (`Счёт`, `Счёт зачисления`, `ID счёта`, `ID счёта зачисления`), колонок
/// значков (16-17) нет. С этим сравнивается экспорт после [stripIconColumns].
String v1AsV2WithoutIcons(String v1Text) {
  final rows = decodeCsv(v1Text);
  final headers = [...transactionsExportHeaders.sublist(0, csvV2IconColumn)];
  return encodeCsv([
    headers,
    for (final row in rows.skip(1))
      [...row.sublist(0, 7), '', '', ...row.sublist(7, 11), '', ''],
  ]);
}

/// Экспорт v2 без колонок 16-17 (для сравнения с [v1AsV2WithoutIcons]).
String stripIconColumns(String v2Text) {
  return encodeCsv([
    for (final row in decodeCsv(v2Text)) row.sublist(0, csvV2IconColumn),
  ]);
}

/// Значки из экспорта v2: пары (категория, подкатегория) по строкам файла
/// без заголовка.
List<(String, String)> iconColumns(String v2Text) {
  return [
    for (final row in decodeCsv(v2Text).skip(1))
      (row[csvV2IconColumn], row[csvV2SubcategoryIconColumn]),
  ];
}
