import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/app/app_routes.dart';
import 'package:money_app/app/app_scope.dart';
import 'package:money_app/app/app_tabs.dart';
import 'package:money_app/features/csv_import/domain/parse_csv_import.dart';
import 'package:money_app/features/csv_import/domain/plan_csv_import.dart';
import 'package:money_app/features/csv_import/presentation/csv_import_screen.dart';
import 'package:money_app/features/csv_import/presentation/csv_import_texts.dart';
import 'package:money_app/features/csv_import/presentation/pick_csv_file.dart';
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';
import 'package:money_app/features/settings/presentation/settings_screen.dart';

import '../support/fake_id_generator.dart';
import '../support/fakes.dart';
import '../support/fixed_clock.dart';

/// Вкладка «Настройки» с настоящими маршрутами, фейковым окном выбора файла и
/// фейковой записью. Чтение файла настоящее: копия лежит во временном каталоге.
Future<void> _pump(
  WidgetTester tester, {
  required PickFile pickFile,
  required PlannedCsvImportStore store,
}) async {
  final settings = AppSettingsController();
  addTearDown(settings.dispose);
  final categories = InMemoryCategoriesRepository(const []);
  addTearDown(categories.dispose);
  await tester.pumpWidget(
    MaterialApp(
      onGenerateRoute: onGenerateAppRoute,
      home: AppScope(
        services: fakeAppServices(
          settings: settings,
          categories: categories,
          clock: FixedClock(DateTime(2026, 10, 7, 12)),
          csvImport: store,
        ),
        child: Scaffold(body: SettingsTab(pickFile: pickFile)),
      ),
    ),
  );
}

const _emptyPlan = CsvImportPlan(
  transactions: [],
  skippedExisting: 0,
  skippedDeleted: 0,
  categoriesToCreate: [],
  errors: [],
);

void main() {
  late Directory dir;
  late File copy;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('zuno_import_test');
    copy = File('${dir.path}/import.csv')
      ..writeAsStringSync(
        'Дата;Тип;Сумма;Категория\n01.10.2026;Расход;350;Еда\n',
      );
  });
  tearDown(() => dir.deleteSync(recursive: true));

  testWidgets('отмена выбора: экран не открывается, сообщения нет', (
    tester,
  ) async {
    await _pump(
      tester,
      pickFile: () async => null,
      store: PlannedCsvImportStore(_emptyPlan),
    );
    await tester.tap(find.text(importCsvItemLabel));
    await tester.pumpAndSettle();

    expect(find.byType(CsvImportScreen), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('файл выбран: предпросмотр → «Загрузить» → итог, копия удалена', (
    tester,
  ) async {
    final store = PlannedCsvImportStore(_planFor(copy));
    await _pump(tester, pickFile: () async => copy.path, store: store);

    await tester.tap(find.text(importCsvItemLabel));
    await tester.pumpAndSettle();
    expect(find.byType(CsvImportScreen), findsOneWidget);
    expect(store.preparedRows, hasLength(1));
    expect(find.text('Будет добавлена 1 операция'), findsOneWidget);

    await tester.tap(find.text(csvImportLoadButton));
    await tester.pumpAndSettle();

    expect(find.byType(CsvImportScreen), findsNothing);
    expect(store.written, hasLength(1));
    expect(find.text('Загружена 1 операция'), findsOneWidget);
    expect(copy.existsSync(), isFalse);
  });

  testWidgets('«Отмена» на предпросмотре: без сообщения, копия удалена', (
    tester,
  ) async {
    final store = PlannedCsvImportStore(_planFor(copy));
    await _pump(tester, pickFile: () async => copy.path, store: store);

    await tester.tap(find.text(importCsvItemLabel));
    await tester.pumpAndSettle();
    await tester.tap(find.text(csvImportCancelButton));
    await tester.pumpAndSettle();

    expect(store.written, isEmpty);
    expect(find.byType(SnackBar), findsNothing);
    expect(copy.existsSync(), isFalse);
  });

  testWidgets('окно выбора не открылось: SnackBar «Не удалось открыть файл»', (
    tester,
  ) async {
    await _pump(
      tester,
      pickFile: () async => throw const PickFileException(pickErrorBusy),
      store: PlannedCsvImportStore(_emptyPlan),
    );
    await tester.tap(find.text(importCsvItemLabel));
    await tester.pumpAndSettle();

    expect(find.text(importOpenFailedMessage), findsOneWidget);
  });
}

/// Настоящий план по содержимому файла (база пустая).
CsvImportPlan _planFor(File file) {
  final parsed = parseCsvImport(
    file.readAsBytesSync(),
    clock: FixedClock(DateTime(2026, 10, 7, 12)),
  ) as CsvImportParsed;
  return planCsvImport(
    rows: parsed.rows,
    categories: const [],
    liveTransactionIds: const {},
    deletedTransactionIds: const {},
    ids: FakeIdGenerator(),
    isKnownIconKey: (_) => true,
  );
}
