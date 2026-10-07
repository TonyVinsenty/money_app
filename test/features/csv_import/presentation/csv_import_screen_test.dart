import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/csv_import/domain/csv_import_store.dart';
import 'package:money_app/features/csv_import/domain/parse_csv_import.dart';
import 'package:money_app/features/csv_import/domain/plan_csv_import.dart';
import 'package:money_app/features/csv_import/presentation/csv_import_screen.dart';
import 'package:money_app/features/csv_import/presentation/csv_import_texts.dart';

import '../../../support/fake_id_generator.dart';
import '../../../support/fixed_clock.dart';

const _header = 'Дата;Тип;Сумма;Категория;Подкатегория;ID операции';

/// Настоящий план поверх заданных категорий и id операций; запись — в память.
class _PlanningStore implements CsvImportStore {
  _PlanningStore({this.categories = const [], this.liveIds = const {}});

  final List<Category> categories;
  final Set<String> liveIds;
  Exception? writeError;
  final List<CsvImportPlan> written = [];

  @override
  Future<CsvImportPlan> prepare(List<ParsedCsvRow> rows) async => planCsvImport(
    rows: rows,
    categories: categories,
    liveTransactionIds: liveIds,
    deletedTransactionIds: const {},
    ids: FakeIdGenerator(prefix: 'new'),
  );

  @override
  Future<void> write(CsvImportPlan plan) async {
    final error = writeError;
    if (error != null) throw error;
    written.add(plan);
  }
}

final _food = Category.topLevel(
  id: 'food',
  kind: CategoryKind.expense,
  name: 'Еда',
  iconKey: 'restaurant',
  sortOrder: 0,
);

/// Открывает экран кнопкой поверх пустой страницы; результат экрана — в
/// возвращённом списке (пусто, пока экран не закрыт).
Future<List<int?>> _open(
  WidgetTester tester, {
  required String csv,
  required CsvImportStore store,
  List<int>? bytes,
}) async {
  final results = <int?>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            final result = await Navigator.of(context).push<int>(
              MaterialPageRoute(
                builder: (_) => CsvImportScreen(
                  path: '/tmp/import.csv',
                  clock: FixedClock(DateTime(2026, 10, 7, 12)),
                  store: store,
                  categories: Stream.value([_food]),
                  readBytes: (_) async => bytes ?? utf8.encode(csv),
                ),
              ),
            );
            results.add(result);
          },
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return results;
}

void main() {
  testWidgets('файл без ошибок: предпросмотр, «Загрузить» закрывает экран', (
    tester,
  ) async {
    final store = _PlanningStore(categories: [_food]);
    final results = await _open(
      tester,
      store: store,
      csv:
          '$_header\n'
          '01.10.2026;Расход;350;Еда;Кафе;\n'
          '02.10.2026;Доход;1000;Кэшбэк;;\n',
    );

    expect(find.text('Будут добавлены 2 операции'), findsOneWidget);
    expect(find.text(csvImportNewCategoriesTitle), findsOneWidget);
    expect(find.text('Расходы: Еда → Кафе'), findsOneWidget);
    expect(find.text('Доходы: Кэшбэк'), findsOneWidget);

    await tester.tap(find.text(csvImportLoadButton));
    await tester.pumpAndSettle();

    expect(store.written.single.transactions, hasLength(2));
    expect(results, [2]);
  });

  testWidgets('«Отмена» закрывает экран без записи', (tester) async {
    final store = _PlanningStore();
    final results = await _open(
      tester,
      store: store,
      csv: '$_header\n01.10.2026;Расход;350;Еда;;\n',
    );

    await tester.tap(find.text(csvImportCancelButton));
    await tester.pumpAndSettle();

    expect(store.written, isEmpty);
    expect(results, [null]);
  });

  testWidgets('ошибки в файле: список «Строка N», кнопки «Загрузить» нет', (
    tester,
  ) async {
    await _open(
      tester,
      store: _PlanningStore(),
      csv:
          '$_header\n'
          '01.10.2026;Расход;12.3.4;Еда;;\n'
          '01.10.2026;Покупка;10;Еда;;\n',
    );

    expect(find.text(csvImportErrorsIntro), findsOneWidget);
    expect(
      find.text('Строка 2: сумма «12.3.4» — слишком много запятых или точек'),
      findsOneWidget,
    );
    expect(find.textContaining('Строка 3: тип «Покупка»'), findsOneWidget);
    expect(find.text(csvImportLoadButton), findsNothing);
    expect(find.text(csvImportCloseButton), findsOneWidget);
  });

  testWidgets('больше 20 ошибок: первые 20 и «… и ещё K»', (tester) async {
    final rows = List.filled(23, '01.10.2026;Расход;abc;Еда;;').join('\n');
    await _open(tester, store: _PlanningStore(), csv: '$_header\n$rows\n');

    await tester.scrollUntilVisible(find.text('… и ещё 3'), 200);
    expect(find.text('… и ещё 3'), findsOneWidget);
    expect(find.textContaining('Строка 21:'), findsOneWidget);
    expect(find.textContaining('Строка 22:'), findsNothing);
  });

  testWidgets('всё уже загружено: «Нечего добавлять» и счётчик пропусков', (
    tester,
  ) async {
    const id = '0190f0a0-0000-7000-8000-000000000001';
    final results = await _open(
      tester,
      store: _PlanningStore(liveIds: {id}),
      csv: '$_header\n01.10.2026;Расход;350;Еда;;$id\n',
    );

    expect(find.text(csvImportNothingToAddMessage), findsOneWidget);
    expect(find.text(csvImportSkippedExisting(1)), findsOneWidget);
    expect(find.text(csvImportLoadButton), findsNothing);

    await tester.tap(find.text(csvImportCloseButton));
    await tester.pumpAndSettle();
    expect(results, [null]);
  });

  testWidgets('только заголовки — «В файле нет операций»', (tester) async {
    await _open(tester, store: _PlanningStore(), csv: '$_header\n');

    expect(find.text(csvImportNoRowsMessage), findsOneWidget);
  });

  testWidgets('файл не в UTF-8 — подсказка, как сохранить', (tester) async {
    await _open(
      tester,
      store: _PlanningStore(),
      csv: '',
      bytes: [0xC4, 0xE0, 0xF2, 0xE0], // «Дата» в Windows-1251
    );

    expect(find.textContaining('не в той кодировке'), findsOneWidget);
    expect(find.text(csvImportLoadButton), findsNothing);
  });

  testWidgets('файл не прочитался — понятный текст', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CsvImportScreen(
          path: '/tmp/import.csv',
          clock: FixedClock(DateTime(2026, 10, 7, 12)),
          store: _PlanningStore(),
          categories: Stream.value(const []),
          readBytes: (_) async => throw const FormatException('нет файла'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(csvImportReadFailedMessage), findsOneWidget);
  });

  testWidgets('ошибка записи: текст, экран остаётся, повтор возможен', (
    tester,
  ) async {
    final store = _PlanningStore()..writeError = Exception('диск полон');
    final results = await _open(
      tester,
      store: store,
      csv: '$_header\n01.10.2026;Расход;350;Еда;;\n',
    );

    await tester.tap(find.text(csvImportLoadButton));
    await tester.pumpAndSettle();

    expect(find.text(csvImportWriteFailedMessage), findsOneWidget);
    expect(results, isEmpty);

    store.writeError = null;
    await tester.tap(find.text(csvImportLoadButton));
    await tester.pumpAndSettle();
    expect(results, [1]);
  });
}
