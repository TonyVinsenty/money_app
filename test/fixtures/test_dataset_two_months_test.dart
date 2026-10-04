import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/csv/csv_codec.dart';
import 'package:money_app/features/export/domain/transactions_export.dart';

/// Тестовый набор за сентябрь и октябрь 2026 (без личных данных, суммы и
/// названия выдуманы). Файл читается тем же кодеком, что пишет экспорт.

const _datasetPath = 'test/fixtures/test_dataset_two_months.csv';

/// Суммы в копейках (модуль, без знака). Зафиксированы: если файл поправят
/// вручную, тест это заметит.
const _septemberExpensesMinor = 12803388; // 128 033,88
const _septemberIncomeMinor = 10294900; // 102 949,00
const _octoberExpensesMinor = 3401287; // 34 012,87
const _octoberIncomeMinor = 9045700; // 90 457,00

final _dateShape = RegExp(r'^\d{2}\.\d{2}\.\d{4}$');

/// Разбор `350,00` или `-350,00` в копейки (без знака).
int _minorOf(String text) {
  final unsigned = text.startsWith('-') ? text.substring(1) : text;
  final parts = unsigned.split(',');
  expect(parts, hasLength(2), reason: 'сумма "$text"');
  expect(parts[1], hasLength(2), reason: 'сумма "$text"');
  return int.parse(parts[0]) * 100 + int.parse(parts[1]);
}

/// Разбор `ДД.ММ.ГГГГ`.
DateTime _dateOf(String text) {
  final parts = text.split('.');
  expect(parts, hasLength(3), reason: 'дата "$text"');
  return DateTime(
    int.parse(parts[2]),
    int.parse(parts[1]),
    int.parse(parts[0]),
  );
}

void main() {
  final table = decodeCsv(File(_datasetPath).readAsStringSync());
  final header = table.first;
  final rows = table.sublist(1);

  group('тестовый набор test_dataset_two_months.csv', () {
    test('заголовки совпадают с форматом экспорта', () {
      expect(header, transactionsExportHeaders);
    });

    test('в каждой строке 11 колонок', () {
      for (final row in rows) {
        expect(row, hasLength(11), reason: row.join(' | '));
      }
    });

    test('операций от 120 до 180', () {
      expect(rows.length, inInclusiveRange(120, 180));
    });

    test('все даты в сентябре или октябре 2026 и не позже 4 октября', () {
      final lastDay = DateTime(2026, 10, 4);
      for (final row in rows) {
        expect(_dateShape.hasMatch(row[0]), isTrue, reason: row[0]);
        final day = _dateOf(row[0]);
        expect(day.year, 2026, reason: row[0]);
        expect([9, 10], contains(day.month), reason: row[0]);
        expect(day.isAfter(lastDay), isFalse, reason: row[0]);
      }
    });

    test('у расходов минус, у доходов и нулевого расхода минуса нет', () {
      for (final row in rows) {
        final type = row[1];
        final amount = row[2];
        if (type == 'Расход') {
          if (amount == '0,00') continue;
          expect(amount.startsWith('-'), isTrue, reason: amount);
        } else {
          expect(type, 'Доход', reason: row.join(' | '));
          expect(amount.startsWith('-'), isFalse, reason: amount);
        }
      }
    });

    test('ровно один расход на 0,00', () {
      final zeroes = rows.where((row) => row[2] == '0,00').toList();
      expect(zeroes, hasLength(1));
      expect(zeroes.single[1], 'Расход');
    });

    test('все id операций уникальны', () {
      final ids = rows.map((row) => row[7]).toSet();
      expect(ids, hasLength(rows.length));
    });

    test('сумма расходов и доходов по месяцам совпадает с зафиксированной', () {
      int sumOf(String type, int month) => rows
          .where((row) => row[1] == type && _dateOf(row[0]).month == month)
          .fold(0, (total, row) => total + _minorOf(row[2]));

      expect(sumOf('Расход', 9), _septemberExpensesMinor);
      expect(sumOf('Доход', 9), _septemberIncomeMinor);
      expect(sumOf('Расход', 10), _octoberExpensesMinor);
      expect(sumOf('Доход', 10), _octoberIncomeMinor);
    });

    test(
      'есть комментарии с точкой с запятой, кавычкой и переносом строки',
      () {
        final notes = rows.map((row) => row[6]).toList();
        expect(notes.any((note) => note.contains(';')), isTrue);
        expect(notes.any((note) => note.contains('"')), isTrue);
        expect(notes.any((note) => note.contains('\n')), isTrue);
        expect(notes, contains('ужин в "Чайхане"'));
        expect(notes, contains('молоко; хлеб'));
        expect(notes, contains('список:\nхлеб, сыр'));
      },
    );

    test('все операции в рублях', () {
      expect(rows.map((row) => row[3]).toSet(), {'RUB'});
    });
  });
}
