import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/csv/csv_codec.dart';
import 'package:money_app/core/errors/data_corrupted_exception.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/features/categories/domain/categories_repository.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/export/data/transactions_exporter.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';
import 'package:money_app/features/transactions/domain/transactions_repository.dart';

import '../../../support/fixed_clock.dart';

/// Фейк операций: отдаёт заранее заданный список или бросает ошибку.
class _Transactions extends Fake implements TransactionsRepository {
  _Transactions({this.items = const [], this.error});

  final List<Transaction> items;
  final Exception? error;

  @override
  Future<List<Transaction>> findAllLive() async {
    final error = this.error;
    if (error != null) throw error;
    return items;
  }
}

/// Фейк категорий: только `watchAll`, как нужно экспорту.
class _Categories extends Fake implements CategoriesRepository {
  _Categories(this.items);

  final List<Category> items;

  @override
  Stream<List<Category>> watchAll() => Stream.value(items);
}

final _cafe = Category.topLevel(
  id: 'cat',
  kind: CategoryKind.expense,
  name: 'Кафе',
  iconKey: 'icon',
  sortOrder: 0,
);

final _oneTx = Transaction(
  id: 'id-1',
  type: TransactionType.expense,
  amount: Money.fromMinor(35000, 'RUB'),
  occurredOn: DateOnly(2026, 10, 4),
  occurredAt: DateTime.utc(2026, 10, 4, 9, 15),
  categoryId: 'cat',
);

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('zuno_export_test_');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  TransactionsExporter exporter({
    required TransactionsRepository transactions,
    List<Category> categories = const [],
  }) {
    return TransactionsExporter(
      transactions: transactions,
      categories: _Categories(categories),
      clock: FixedClock(DateTime(2026, 10, 4, 18)),
      directoryProvider: () async => dir,
    );
  }

  test('записывает файл с именем по дате и BOM в начале', () async {
    final path = await exporter(
      transactions: _Transactions(items: [_oneTx]),
      categories: [_cafe],
    ).exportToTempFile();

    expect(path, endsWith('zuno-export-2026-10-04.csv'));
    final bytes = File(path).readAsBytesSync();
    // UTF-8 BOM: EF BB BF.
    expect(bytes.sublist(0, 3), [0xEF, 0xBB, 0xBF]);
    final rows = decodeCsv(utf8.decode(bytes));
    expect(rows, hasLength(2));
    // Расход: минус ASCII-дефисом перед суммой (ADR 0006, п. 1).
    expect(rows[1][2], '-350,00');
    expect(rows[1][4], 'Кафе');
  });

  test('испорченная строка: DataCorruptedException и файл не создан', () async {
    final exp = exporter(
      transactions: _Transactions(
        error: const DataCorruptedException('Transaction row "x" is corrupted'),
      ),
      categories: [_cafe],
    );

    await expectLater(
      exp.exportToTempFile(),
      throwsA(isA<DataCorruptedException>()),
    );
    expect(dir.listSync(), isEmpty);
  });

  test('операция без категории: ошибка и файл не создан', () async {
    final exp = exporter(
      transactions: _Transactions(items: [_oneTx]),
      categories: const [],
    );

    await expectLater(
      exp.exportToTempFile(),
      throwsA(isA<DataCorruptedException>()),
    );
    expect(dir.listSync(), isEmpty);
  });
}
