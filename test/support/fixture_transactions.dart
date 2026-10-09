import 'dart:io';

import 'package:money_app/core/csv/csv_codec.dart';
import 'package:money_app/core/money/parse_amount.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

import 'csv_v1_compat.dart';

/// Путь к тестовому набору за сентябрь и октябрь 2026 (формат экспорта).
const fixtureDatasetPath = 'test/fixtures/test_dataset_two_months.csv';

/// Читает тестовый набор и превращает каждую строку в [Transaction].
///
/// Это данные для тестов, поэтому помощник лежит в `test/`, а не в `lib/`.
/// Разбор CSV — тем же [decodeCsv], что пишет экспорт. Суммы — через
/// [parseAmount], то есть целыми копейками, без `double`.
List<Transaction> loadFixtureTransactions() {
  final rows = decodeCsv(File(fixtureDatasetPath).readAsStringSync());
  if (rows.isEmpty || rows.first.join('|') != csvV1Headers.join('|')) {
    throw StateError('Тестовый набор не совпадает с форматом экспорта');
  }
  return [for (final row in rows.skip(1)) _transactionOf(row)];
}

/// Одна строка набора: `ДД.ММ.ГГГГ;Тип;Сумма;Валюта;...;ID;...;время UTC`.
Transaction _transactionOf(List<String> row) {
  if (row.length != csvV1Headers.length) {
    throw FormatException('В строке ${row.length} колонок: ${row.join(';')}');
  }
  final amountText = row[2];
  // Знак берётся из колонки «Тип», поэтому минус снимаем до разбора.
  final unsigned = amountText.startsWith('-')
      ? amountText.substring(1)
      : amountText;
  final parsed = parseAmount(unsigned, currency: row[3]);
  if (parsed is! AmountParsed) {
    throw FormatException('Не разобрана сумма "$amountText"');
  }
  final subcategoryId = row[9];
  return Transaction(
    id: row[7],
    type: _typeOf(row[1]),
    amount: parsed.amount,
    occurredOn: _dayOf(row[0]),
    occurredAt: DateTime.parse(row[10]),
    categoryId: row[8],
    subcategoryId: subcategoryId.isEmpty ? null : subcategoryId,
    note: row[6],
  );
}

TransactionType _typeOf(String text) {
  switch (text) {
    case 'Доход':
      return TransactionType.income;
    case 'Расход':
      return TransactionType.expense;
  }
  throw FormatException('Неизвестный тип "$text"');
}

/// Разбор `ДД.ММ.ГГГГ` в календарный день.
DateOnly _dayOf(String text) {
  final parts = text.split('.');
  if (parts.length != 3) {
    throw FormatException('Неверная дата "$text"');
  }
  return DateOnly(
    int.parse(parts[2]),
    int.parse(parts[1]),
    int.parse(parts[0]),
  );
}
