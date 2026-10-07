import 'dart:convert';

import 'package:money_app/core/csv/csv_codec.dart';
import 'package:money_app/core/money/currency.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/money/parse_amount.dart';
import 'package:money_app/core/time/clock.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/features/categories/domain/category_rules.dart';
import 'package:money_app/features/csv_import/domain/csv_import_failures.dart';
import 'package:money_app/features/export/domain/transactions_export.dart';
import 'package:money_app/features/transactions/domain/occurrence.dart';
import 'package:money_app/features/transactions/domain/transaction_rules.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

/// Одна строка файла, прошедшая все проверки.
final class ParsedCsvRow {
  const ParsedCsvRow({
    required this.line,
    required this.day,
    required this.occurredAt,
    required this.type,
    required this.amount,
    required this.categoryName,
    required this.subcategoryName,
    required this.note,
    required this.transactionId,
    required this.categoryId,
    required this.subcategoryId,
  });

  /// Номер строки как в Excel (заголовки — 1).
  final int line;
  final DateOnly day;

  /// Момент в UTC, согласованный с [day].
  final DateTime occurredAt;
  final TransactionType type;
  final Money amount;
  final String categoryName;

  /// `null`, если подкатегории нет.
  final String? subcategoryName;
  final String? note;
  final String? transactionId;
  final String? categoryId;
  final String? subcategoryId;
}

/// Итог разбора файла.
sealed class CsvImportParseResult {
  const CsvImportParseResult();
}

/// Файл не разобрать целиком.
final class CsvImportFileFailed extends CsvImportParseResult {
  const CsvImportFileFailed(this.failure);

  final CsvFileFailure failure;
}

/// Файл прочитан: [rows] — хорошие строки, [errors] — все найденные ошибки.
/// Если [errors] не пуст, загружать нельзя ничего (ADR 0009, п. 6).
final class CsvImportParsed extends CsvImportParseResult {
  const CsvImportParsed({required this.rows, required this.errors});

  final List<ParsedCsvRow> rows;
  final List<CsvRowError> errors;
}

const List<String> _requiredColumns = [
  csvColumnDate,
  csvColumnType,
  csvColumnAmount,
  csvColumnCategory,
];

final RegExp _datePattern = RegExp(r'^(\d{1,2})\.(\d{1,2})\.(\d{4})$');
final RegExp _uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// Разбирает байты CSV-файла по правилам ADR 0009, п. 6. Ничего не пишет.
///
/// [clock] — «сейчас»: день из него — сегодня (дата позже — ошибка строки),
/// а сегодняшняя дата без времени в файле получает момент `clock.now()`.
CsvImportParseResult parseCsvImport(List<int> bytes, {required Clock clock}) {
  final String text;
  try {
    text = utf8.decode(bytes);
  } on FormatException {
    return const CsvImportFileFailed(CsvNotUtf8());
  }
  final body = text.startsWith('\uFEFF') ? text.substring(1) : text;
  if (body.isEmpty) return const CsvImportFileFailed(CsvEmptyFile());

  final firstLine = body.split('\n').first;
  final separator = firstLine.contains(';') || !firstLine.contains(',')
      ? ';'
      : ',';
  final List<List<String>> table;
  try {
    table = decodeCsv(body, separator: separator);
  } on FormatException catch (e) {
    return CsvImportFileFailed(CsvMalformed(e.message));
  }

  final headers = table.first.map((h) => h.trim().toLowerCase()).toList();
  final known = {for (final h in transactionsExportHeaders) h.toLowerCase(): h};
  final columns = <String, int>{};
  for (var i = 0; i < headers.length; i++) {
    final name = known[headers[i]];
    if (name == null) continue;
    if (columns.containsKey(name)) {
      return CsvImportFileFailed(CsvDuplicateColumn(name));
    }
    columns[name] = i;
  }
  final missing = _requiredColumns.where((c) => !columns.containsKey(c));
  if (missing.isNotEmpty) {
    return CsvImportFileFailed(CsvMissingColumns(missing.toList()));
  }

  final rows = <ParsedCsvRow>[];
  final errors = <CsvRowError>[];
  final seenIds = <String>{};
  for (var i = 1; i < table.length; i++) {
    final record = table[i];
    if (record.every((f) => f.trim().isEmpty)) continue;
    String field(String column) {
      final index = columns[column];
      return index == null || index >= record.length ? '' : record[index];
    }

    final row = _parseRow(i + 1, field, clock, seenIds, errors);
    if (row != null) rows.add(row);
  }
  return CsvImportParsed(rows: rows, errors: errors);
}

/// Разбирает одну строку; ошибки дописывает в [errors]. Вернёт строку,
/// только если ошибок в ней нет.
ParsedCsvRow? _parseRow(
  int line,
  String Function(String column) field,
  Clock clock,
  Set<String> seenIds,
  List<CsvRowError> errors,
) {
  final today = clock.today();
  final before = errors.length;

  final dateText = field(csvColumnDate).trim();
  final day = _parseDay(dateText);
  if (day == null) {
    errors.add(CsvInvalidDate(line, dateText));
  } else if (day > today) {
    errors.add(CsvFutureDate(line, dateText));
  }

  final typeText = field(csvColumnType).trim();
  final type = switch (typeText.toLowerCase()) {
    'расход' => TransactionType.expense,
    'доход' => TransactionType.income,
    _ => null,
  };
  if (type == null) errors.add(CsvInvalidType(line, typeText));

  final amountText = field(csvColumnAmount).trim();
  final hasMinus =
      amountText.startsWith('-') || amountText.startsWith('\u2212');
  final amountResult = parseAmount(
    hasMinus ? amountText.substring(1) : amountText,
  );
  Money? amount;
  switch (amountResult) {
    case AmountParsed(amount: final parsed):
      amount = parsed;
    case AmountParseFailed(:final failure):
      errors.add(CsvInvalidAmount(line, amountText, failure));
  }
  if (hasMinus && type == TransactionType.income) {
    errors.add(CsvNegativeIncome(line, amountText));
  }

  final currency = field(csvColumnCurrency).trim();
  if (currency.isNotEmpty && currency != rubCurrencyCode) {
    errors.add(CsvUnsupportedCurrency(line, currency));
  }

  final category = field(csvColumnCategory).trim();
  if (category.isEmpty) {
    errors.add(CsvEmptyCategory(line, category));
  } else if (category.runes.length > categoryNameMaxLength) {
    errors.add(CsvCategoryTooLong(line, category));
  }
  final subcategory = field(csvColumnSubcategory).trim();
  if (subcategory.runes.length > categoryNameMaxLength) {
    errors.add(CsvSubcategoryTooLong(line, subcategory));
  }

  final note = normalizeTransactionNote(field(csvColumnNote));
  if (note != null && note.runes.length > transactionNoteMaxLength) {
    errors.add(CsvNoteTooLong(line, note));
  }

  final transactionId = _parseId(
    line,
    field(csvColumnTransactionId),
    CsvIdColumn.transaction,
    errors,
  );
  if (transactionId != null && !seenIds.add(transactionId.toLowerCase())) {
    errors.add(CsvDuplicateTransactionId(line, transactionId));
  }
  final categoryId = _parseId(
    line,
    field(csvColumnCategoryId),
    CsvIdColumn.category,
    errors,
  );
  final subcategoryId = _parseId(
    line,
    field(csvColumnSubcategoryId),
    CsvIdColumn.subcategory,
    errors,
  );

  if (errors.length > before || day == null || type == null || amount == null) {
    return null;
  }
  return ParsedCsvRow(
    line: line,
    day: day,
    occurredAt: _momentOf(day, field(csvColumnOccurredAtUtc), clock),
    type: type,
    amount: amount,
    categoryName: category,
    subcategoryName: subcategory.isEmpty ? null : subcategory,
    note: note,
    transactionId: transactionId,
    categoryId: categoryId,
    subcategoryId: subcategoryId,
  );
}

/// `Д.М.ГГГГ` (день и месяц — одна или две цифры); несуществующий день — `null`.
DateOnly? _parseDay(String text) {
  final match = _datePattern.firstMatch(text);
  if (match == null) return null;
  try {
    return DateOnly(
      int.parse(match.group(3)!),
      int.parse(match.group(2)!),
      int.parse(match.group(1)!),
    );
  } on ArgumentError {
    return null;
  }
}

/// Пустое значение — `null`; не UUID — ошибка в [errors] и `null`.
String? _parseId(
  int line,
  String raw,
  CsvIdColumn column,
  List<CsvRowError> errors,
) {
  final value = raw.trim();
  if (value.isEmpty) return null;
  if (!_uuidPattern.hasMatch(value)) {
    errors.add(CsvInvalidId(line, value, column));
    return null;
  }
  return value;
}

/// Момент из файла, если это ISO-момент UTC того же местного дня; иначе
/// момент из даты по правилу ручного ввода задним числом (`Occurrence`).
/// Испорченное время — не ошибка.
DateTime _momentOf(DateOnly day, String raw, Clock clock) {
  final parsed = DateTime.tryParse(raw.trim());
  if (parsed != null && parsed.isUtc && DateOnly.fromDateTime(parsed) == day) {
    return parsed;
  }
  return Occurrence.onDay(day, clock: clock).occurredAt;
}
