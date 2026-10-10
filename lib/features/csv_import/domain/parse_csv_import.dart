import 'dart:convert';

import 'package:money_app/core/csv/csv_codec.dart';
import 'package:money_app/core/money/currency.dart';
import 'package:money_app/core/money/currency_catalog.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/money/parse_amount.dart';
import 'package:money_app/core/time/clock.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/features/accounts/domain/account_rules.dart';
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
    this.accountName,
    this.accountId,
    this.categoryIconKey,
    this.subcategoryIconKey,
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

  /// Имя счёта из колонки `Счёт`; `null`, если ячейка пуста (нет колонки).
  final String? accountName;
  final String? accountId;

  /// Ключи значков как в файле (обрезаны по краям); `null` — значка нет.
  final String? categoryIconKey;
  final String? subcategoryIconKey;
}

/// Строка `Начальный остаток`, прошедшая все проверки (ADR 0010, п. 10).
final class ParsedOpeningBalance {
  const ParsedOpeningBalance({
    required this.line,
    required this.day,
    required this.occurredAt,
    required this.accountName,
    required this.accountId,
    required this.amount,
    required this.customDigits,
  });

  final int line;
  final DateOnly day;

  /// Момент создания счёта в UTC, согласованный с [day].
  final DateTime occurredAt;
  final String accountName;
  final String? accountId;

  /// Остаток со знаком (долг — отрицательный), в валюте строки.
  final Money amount;

  /// Для кода валюты не из каталога — число цифр после запятой в сумме
  /// (0–8); для валюты каталога `null` (знаки берутся из каталога).
  final int? customDigits;
}

/// Строка `Перевод`, прошедшая все проверки (ADR 0010, п. 10). Счёт задан
/// именем, ID или обоими; существование счетов проверяет план.
final class ParsedTransfer {
  const ParsedTransfer({
    required this.line,
    required this.day,
    required this.occurredAt,
    required this.fromAccountName,
    required this.fromAccountId,
    required this.toAccountName,
    required this.toAccountId,
    required this.amount,
    required this.customDigits,
    required this.note,
    required this.transferId,
  });

  final int line;
  final DateOnly day;

  /// Момент в UTC, согласованный с [day].
  final DateTime occurredAt;

  /// Имя счёта «откуда»; `null`, если ячейка пуста (тогда есть ID).
  final String? fromAccountName;
  final String? fromAccountId;

  /// Имя счёта «куда»; `null`, если ячейка пуста (тогда есть ID).
  final String? toAccountName;
  final String? toAccountId;

  /// Сумма больше нуля, в валюте строки.
  final Money amount;

  /// Для кода валюты не из каталога — число цифр после запятой в сумме
  /// (0–8); для валюты каталога `null`.
  final int? customDigits;
  final String? note;

  /// `ID операции` из файла; `null`, если ячейка пуста.
  final String? transferId;
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
  const CsvImportParsed({
    required this.rows,
    required this.errors,
    this.openingBalances = const [],
    this.transfers = const [],
  });

  /// Доходы и расходы.
  final List<ParsedCsvRow> rows;

  /// Строки `Начальный остаток`.
  final List<ParsedOpeningBalance> openingBalances;

  /// Строки `Перевод`.
  final List<ParsedTransfer> transfers;
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
  final openingBalances = <ParsedOpeningBalance>[];
  final transfers = <ParsedTransfer>[];
  final errors = <CsvRowError>[];
  final seenIds = <String>{};
  for (var i = 1; i < table.length; i++) {
    final record = table[i];
    if (record.every((f) => f.trim().isEmpty)) continue;
    // Лишние непустые ячейки: значение «уехало» (например, `350,50` без
    // кавычек в файле с `,`). Угадывать, где какое поле, нельзя.
    if (record.skip(headers.length).any((f) => f.trim().isNotEmpty)) {
      errors.add(CsvExtraCells(i + 1, separator));
      continue;
    }
    String field(String column) {
      final index = columns[column];
      return index == null || index >= record.length ? '' : record[index];
    }

    final typeText = field(csvColumnType).trim().toLowerCase();
    if (typeText == csvTypeOpeningBalance.toLowerCase()) {
      final balance = _parseOpeningBalance(i + 1, field, clock, errors);
      if (balance != null) openingBalances.add(balance);
      continue;
    }
    if (typeText == csvTypeTransfer.toLowerCase()) {
      final transfer = _parseTransfer(i + 1, field, clock, seenIds, errors);
      if (transfer != null) transfers.add(transfer);
      continue;
    }
    final row = _parseRow(i + 1, field, clock, seenIds, errors);
    if (row != null) rows.add(row);
  }
  return CsvImportParsed(
    rows: rows,
    errors: errors,
    openingBalances: openingBalances,
    transfers: transfers,
  );
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

  // \u0412\u0430\u043b\u044e\u0442\u0430 \u0441\u0442\u0440\u043e\u043a\u0438: \u043f\u0443\u0441\u0442\u043e \u2014 \u0440\u0443\u0431\u043b\u044c, \u0438\u043d\u0430\u0447\u0435 \u043e\u0431\u044b\u0447\u043d\u0430\u044f \u0432\u0430\u043b\u044e\u0442\u0430 \u043a\u0430\u0442\u0430\u043b\u043e\u0433\u0430 (\u043f. 16.11).
  final currencyText = field(csvColumnCurrency).trim();
  final currencyCode = currencyText.isEmpty
      ? rubCurrencyCode
      : currencyText.toUpperCase();
  final currencyInfo = catalogCurrency(currencyCode);
  final currencyOk =
      currencyInfo != null && currencyInfo.kind == CurrencyKind.fiat;
  if (!currencyOk) errors.add(CsvUnsupportedCurrency(line, currencyText));

  final amountText = field(csvColumnAmount).trim();
  final hasMinus =
      amountText.startsWith('-') || amountText.startsWith('\u2212');
  Money? amount;
  // \u0411\u0435\u0437 \u043f\u043e\u043d\u044f\u0442\u043d\u043e\u0439 \u0432\u0430\u043b\u044e\u0442\u044b \u0437\u043d\u0430\u043a\u043e\u0432 \u043f\u043e\u0441\u043b\u0435 \u0437\u0430\u043f\u044f\u0442\u043e\u0439 \u043d\u0435 \u0437\u043d\u0430\u0435\u043c: \u0441\u0443\u043c\u043c\u0443 \u043d\u0435 \u0440\u0430\u0437\u0431\u0438\u0440\u0430\u0435\u043c.
  if (currencyOk) {
    final amountResult = parseAmount(
      hasMinus ? amountText.substring(1) : amountText,
      currency: currencyCode,
      currencyInfo: currencyInfo,
    );
    switch (amountResult) {
      case AmountParsed(amount: final parsed):
        amount = parsed;
      case AmountParseFailed(:final failure):
        errors.add(
          CsvInvalidAmount(
            line,
            amountText,
            failure,
            currencyCode: currencyCode,
            currencyDigits: currencyInfo.digits,
          ),
        );
    }
  }
  if (hasMinus && type == TransactionType.income) {
    errors.add(CsvNegativeIncome(line, amountText));
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

  final account = field(csvColumnAccount).trim();
  if (account.runes.length > accountNameMaxLength) {
    errors.add(CsvAccountTooLong(line, account));
  }
  final accountId = _parseId(
    line,
    field(csvColumnAccountId),
    CsvIdColumn.account,
    errors,
  );
  // Значки ошибок не дают никогда (ADR 0010, п. 17).
  final categoryIcon = field(csvColumnCategoryIcon).trim();
  final subcategoryIcon = field(csvColumnSubcategoryIcon).trim();

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
    accountName: account.isEmpty ? null : account,
    accountId: accountId,
    categoryIconKey: categoryIcon.isEmpty ? null : categoryIcon,
    subcategoryIconKey: subcategoryIcon.isEmpty ? null : subcategoryIcon,
  );
}

/// Цифры после запятой в сумме без пробелов и знака: `12,3456` — 4, `12` — 0.
/// Не похоже на число — 0 (ошибку тогда даст `parseAmount`). Не больше 8:
/// дальше разбор сам скажет «слишком много знаков».
final RegExp _decimalsPattern = RegExp(r'^[0-9]*[.,]([0-9]*)$');
final RegExp _spaces = RegExp('[\\s\u00A0\u202F]');

int _digitsInAmount(String amountWithoutMinus) {
  final match = _decimalsPattern.firstMatch(
    amountWithoutMinus.replaceAll(_spaces, ''),
  );
  final count = match?.group(1)!.length ?? 0;
  return count > 8 ? 8 : count;
}

/// Строка `Начальный остаток`: счёт обязателен, категория пуста, минус можно.
ParsedOpeningBalance? _parseOpeningBalance(
  int line,
  String Function(String column) field,
  Clock clock,
  List<CsvRowError> errors,
) {
  final before = errors.length;

  final dateText = field(csvColumnDate).trim();
  final day = _parseDay(dateText);
  if (day == null) {
    errors.add(CsvInvalidDate(line, dateText));
  } else if (day > clock.today()) {
    errors.add(CsvFutureDate(line, dateText));
  }

  // Валюта: пусто — рубль, код каталога или код своей валюты (п. 16.3, 16.11).
  final currencyText = field(csvColumnCurrency).trim();
  final currencyCode = currencyText.isEmpty
      ? rubCurrencyCode
      : currencyText.toUpperCase();
  final catalogInfo = catalogCurrency(currencyCode);
  final currencyOk = catalogInfo != null || isValidCurrencyCode(currencyCode);
  if (!currencyOk) errors.add(CsvInvalidCurrencyCode(line, currencyText));

  final amountText = field(csvColumnAmount).trim();
  final hasMinus =
      amountText.startsWith('-') || amountText.startsWith('\u2212');
  final unsigned = hasMinus ? amountText.substring(1) : amountText;
  Money? amount;
  int? customDigits;
  if (currencyOk) {
    final info =
        catalogInfo ??
        currencyInfoFor(currencyCode, digits: _digitsInAmount(unsigned));
    if (catalogInfo == null) customDigits = info.digits;
    switch (parseAmount(unsigned, currency: currencyCode, currencyInfo: info)) {
      case AmountParsed(amount: final parsed):
        amount = hasMinus ? -parsed : parsed;
      case AmountParseFailed(:final failure):
        errors.add(
          CsvInvalidAmount(
            line,
            amountText,
            failure,
            currencyCode: currencyCode,
            currencyDigits: info.digits,
            digitsFromFile: catalogInfo == null,
          ),
        );
    }
  }

  final account = field(csvColumnAccount).trim();
  if (account.isEmpty) {
    errors.add(CsvOpeningBalanceNoAccount(line, account));
  } else if (account.runes.length > accountNameMaxLength) {
    errors.add(CsvAccountTooLong(line, account));
  }
  final category = field(csvColumnCategory).trim();
  if (category.isNotEmpty) {
    errors.add(CsvOpeningBalanceWithCategory(line, category));
  }
  final accountId = _parseId(
    line,
    field(csvColumnAccountId),
    CsvIdColumn.account,
    errors,
  );

  if (errors.length > before || day == null || amount == null) return null;
  return ParsedOpeningBalance(
    line: line,
    day: day,
    occurredAt: _momentOf(day, field(csvColumnOccurredAtUtc), clock),
    accountName: account,
    accountId: accountId,
    amount: amount,
    customDigits: customDigits,
  );
}

/// Строка `Перевод`: оба счёта обязательны (имя или ID) и разные, сумма
/// больше нуля, категория пуста, минус нельзя. Валюта — как у остатка.
ParsedTransfer? _parseTransfer(
  int line,
  String Function(String column) field,
  Clock clock,
  Set<String> seenIds,
  List<CsvRowError> errors,
) {
  final before = errors.length;

  final dateText = field(csvColumnDate).trim();
  final day = _parseDay(dateText);
  if (day == null) {
    errors.add(CsvInvalidDate(line, dateText));
  } else if (day > clock.today()) {
    errors.add(CsvFutureDate(line, dateText));
  }

  final currencyText = field(csvColumnCurrency).trim();
  final currencyCode = currencyText.isEmpty
      ? rubCurrencyCode
      : currencyText.toUpperCase();
  final catalogInfo = catalogCurrency(currencyCode);
  final currencyOk = catalogInfo != null || isValidCurrencyCode(currencyCode);
  if (!currencyOk) errors.add(CsvInvalidCurrencyCode(line, currencyText));

  final amountText = field(csvColumnAmount).trim();
  final hasMinus =
      amountText.startsWith('-') || amountText.startsWith('\u2212');
  final unsigned = hasMinus ? amountText.substring(1) : amountText;
  Money? amount;
  int? customDigits;
  if (currencyOk) {
    final info =
        catalogInfo ??
        currencyInfoFor(currencyCode, digits: _digitsInAmount(unsigned));
    if (catalogInfo == null) customDigits = info.digits;
    switch (parseAmount(unsigned, currency: currencyCode, currencyInfo: info)) {
      case AmountParsed(amount: final parsed):
        amount = parsed;
        if (hasMinus) {
          errors.add(CsvNegativeIncome(line, amountText));
        } else if (parsed.isZero) {
          errors.add(CsvTransferZeroAmount(line, amountText));
        }
      case AmountParseFailed(:final failure):
        errors.add(
          CsvInvalidAmount(
            line,
            amountText,
            failure,
            currencyCode: currencyCode,
            currencyDigits: info.digits,
            digitsFromFile: catalogInfo == null,
          ),
        );
    }
  }

  final fromName = field(csvColumnAccount).trim();
  final toName = field(csvColumnTransferAccount).trim();
  if (fromName.runes.length > accountNameMaxLength) {
    errors.add(CsvAccountTooLong(line, fromName));
  }
  if (toName.runes.length > accountNameMaxLength) {
    errors.add(CsvAccountTooLong(line, toName));
  }
  final fromId = _parseId(
    line,
    field(csvColumnAccountId),
    CsvIdColumn.account,
    errors,
  );
  final toId = _parseId(
    line,
    field(csvColumnTransferAccountId),
    CsvIdColumn.transferAccount,
    errors,
  );
  // Пустая ячейка ID, которая не прошла проверку UUID, уже дала свою ошибку:
  // «не указан счёт» говорим только когда пусты и имя, и сырая ячейка ID.
  final fromGiven =
      fromName.isNotEmpty || field(csvColumnAccountId).trim().isNotEmpty;
  final toGiven =
      toName.isNotEmpty || field(csvColumnTransferAccountId).trim().isNotEmpty;
  if (!fromGiven) errors.add(CsvTransferNoAccount(line, fromName));
  if (!toGiven) errors.add(CsvTransferNoToAccount(line, toName));
  // Имена сравниваем, только если ID нет хотя бы у одного счёта: два разных
  // ID с одним именем (архивный и переименованный) - разные счета.
  final sameName =
      (fromId == null || toId == null) &&
      fromName.isNotEmpty &&
      fromName.toLowerCase() == toName.toLowerCase();
  final sameId = fromId != null && fromId.toLowerCase() == toId?.toLowerCase();
  if (sameName || sameId) {
    errors.add(CsvTransferSameAccount(line, sameName ? fromName : fromId!));
  }

  final category = field(csvColumnCategory).trim();
  if (category.isNotEmpty) {
    errors.add(CsvTransferWithCategory(line, category));
  }

  final note = normalizeTransactionNote(field(csvColumnNote));
  if (note != null && note.runes.length > transactionNoteMaxLength) {
    errors.add(CsvNoteTooLong(line, note));
  }
  final transferId = _parseId(
    line,
    field(csvColumnTransactionId),
    CsvIdColumn.transaction,
    errors,
  );
  if (transferId != null && !seenIds.add(transferId.toLowerCase())) {
    errors.add(CsvDuplicateTransactionId(line, transferId));
  }

  if (errors.length > before || day == null || amount == null) return null;
  return ParsedTransfer(
    line: line,
    day: day,
    occurredAt: _momentOf(day, field(csvColumnOccurredAtUtc), clock),
    fromAccountName: fromName.isEmpty ? null : fromName,
    fromAccountId: fromId,
    toAccountName: toName.isEmpty ? null : toName,
    toAccountId: toId,
    amount: amount,
    customDigits: customDigits,
    note: note,
    transferId: transferId,
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
