import 'package:money_app/core/csv/csv_codec.dart';
import 'package:money_app/core/errors/data_corrupted_exception.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/clock.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

/// Чистая сборка CSV-экспорта по ADR 0006: без Flutter, без базы и без файлов.
///
/// Здесь только правила формата: заголовки, порядок колонок и строк, вид
/// суммы и даты. Чтение из базы и запись файла — в `features/export/data`.

/// Заголовки колонок в принятом порядке. Импорт ищет колонки по заголовку,
/// поэтому эти строки менять нельзя (ADR 0006, п. 2).
const List<String> transactionsExportHeaders = [
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

// Имена колонок: общие для экспорта и импорта (ADR 0006, п. 2).
const String csvColumnDate = 'Дата';
const String csvColumnType = 'Тип';
const String csvColumnAmount = 'Сумма';
const String csvColumnCurrency = 'Валюта';
const String csvColumnCategory = 'Категория';
const String csvColumnSubcategory = 'Подкатегория';
const String csvColumnNote = 'Комментарий';
const String csvColumnTransactionId = 'ID операции';
const String csvColumnCategoryId = 'ID категории';
const String csvColumnSubcategoryId = 'ID подкатегории';
const String csvColumnOccurredAtUtc = 'Время операции (UTC)';

/// Текст CSV-файла экспорта: заголовки, затем операции от старых к новым.
///
/// [categories] — все не удалённые категории, включая архивные: по ним берутся
/// имена. Если у операции нет категории или подкатегории в этом списке, бросает
/// [DataCorruptedException]: файл не формируется, строки не пропускаются.
String buildTransactionsCsv({
  required List<Transaction> transactions,
  required List<Category> categories,
}) {
  return encodeCsv(
    buildTransactionsCsvRows(
      transactions: transactions,
      categories: categories,
    ),
  );
}

/// Строки таблицы экспорта (первая строка — заголовки), без кодирования.
List<List<String>> buildTransactionsCsvRows({
  required List<Transaction> transactions,
  required List<Category> categories,
}) {
  final byId = {for (final category in categories) category.id: category};
  final sorted = [...transactions]..sort(_byOccurrence);
  return [
    transactionsExportHeaders,
    for (final transaction in sorted) _rowOf(transaction, byId),
  ];
}

/// Имя файла: `zuno-export-ГГГГ-ММ-ДД.csv`, дата — локальный день из [clock].
String exportFileName(Clock clock) {
  // DateOnly.toString() уже даёт вид ГГГГ-ММ-ДД.
  return 'zuno-export-${clock.today()}.csv';
}

/// Сумма для Excel: `350,00` из 35000 копеек. Только целая арифметика.
String formatCsvAmount(Money amount) {
  final minor = amount.minorUnits;
  if (minor < 0) {
    throw ArgumentError.value(minor, 'amount', 'must not be negative');
  }
  final major = minor ~/ 100;
  final cents = (minor % 100).toString().padLeft(2, '0');
  return '$major,$cents';
}

/// Дата `ДД.ММ.ГГГГ`, например `04.10.2026`.
String formatCsvDate(DateOnly day) {
  final dd = day.day.toString().padLeft(2, '0');
  final mm = day.month.toString().padLeft(2, '0');
  final yyyy = day.year.toString().padLeft(4, '0');
  return '$dd.$mm.$yyyy';
}

List<String> _rowOf(Transaction transaction, Map<String, Category> byId) {
  final category = byId[transaction.categoryId];
  if (category == null) {
    throw DataCorruptedException(
      'Transaction "${transaction.id}" refers to a missing category '
      '"${transaction.categoryId}"',
    );
  }
  final subcategoryId = transaction.subcategoryId;
  var subcategoryName = '';
  if (subcategoryId != null) {
    final subcategory = byId[subcategoryId];
    if (subcategory == null) {
      throw DataCorruptedException(
        'Transaction "${transaction.id}" refers to a missing subcategory '
        '"$subcategoryId"',
      );
    }
    subcategoryName = subcategory.name;
  }
  return [
    formatCsvDate(transaction.occurredOn),
    _typeText(transaction.type),
    _amountText(transaction),
    transaction.amount.currency,
    category.name,
    subcategoryName,
    transaction.note ?? '',
    transaction.id,
    transaction.categoryId,
    subcategoryId ?? '',
    transaction.occurredAt.toUtc().toIso8601String(),
  ];
}

/// Сумма в колонке «Сумма»: у расхода перед числом обычный дефис `-`
/// (Excel читает `-350,00` как число). Доход и нулевой расход — без знака:
/// `-0,00` выглядит как ошибка. ADR 0006, п. 1.
String _amountText(Transaction transaction) {
  final text = formatCsvAmount(transaction.amount);
  final isExpense = transaction.type == TransactionType.expense;
  if (isExpense && !transaction.amount.isZero) {
    return '-$text';
  }
  return text;
}

String _typeText(TransactionType type) {
  switch (type) {
    case TransactionType.income:
      return 'Доход';
    case TransactionType.expense:
      return 'Расход';
  }
}

/// Порядок ADR 0006, п. 4: день, затем момент, затем id.
int _byOccurrence(Transaction a, Transaction b) {
  final byDay = a.occurredOn.compareTo(b.occurredOn);
  if (byDay != 0) return byDay;
  final byMoment = a.occurredAt.compareTo(b.occurredAt);
  if (byMoment != 0) return byMoment;
  return a.id.compareTo(b.id);
}
