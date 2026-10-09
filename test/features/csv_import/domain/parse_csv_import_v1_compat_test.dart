import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/features/csv_import/domain/parse_csv_import.dart';

import '../../../../tool/make_test_dataset.dart';
import '../../../support/fixed_clock.dart';

/// Сторож совместимости (ADR 0010, п. 10): v1-файл тестового набора
/// разбирается ровно так же, как до этапа 5. Отпечаток посчитан по всем
/// полям строк разбора на коде до шага 5.17.
const _rows = 295;
const _signature = 5389056857857216748;

/// FNV-1a, 64 бита: стабильный отпечаток текста (строка `hashCode` не годится).
int _fnv(String text) {
  var hash = 0xcbf29ce484222325;
  for (final unit in text.codeUnits) {
    hash = ((hash ^ unit) * 0x100000001b3) & 0x7fffffffffffffff;
  }
  return hash;
}

void main() {
  test('v1-файл тестового набора разбирается как до этапа 5', () {
    final bytes = File(testDatasetPath).readAsBytesSync();
    final parsed = parseCsvImport(
      bytes,
      clock: FixedClock(DateTime.utc(2026, 10, 7, 12)),
    );
    expect(parsed, isA<CsvImportParsed>());
    parsed as CsvImportParsed;
    expect(parsed.errors, isEmpty);
    expect(parsed.rows, hasLength(_rows));
    final text = parsed.rows
        .map(
          (r) => [
            r.line,
            r.day,
            r.occurredAt.toIso8601String(),
            r.type.name,
            r.amount.minorUnits,
            r.amount.currency,
            r.categoryName,
            r.subcategoryName,
            r.note,
            r.transactionId,
            r.categoryId,
            r.subcategoryId,
          ].join('|'),
        )
        .join('\n');
    expect(_fnv(text), _signature);
  });
}
