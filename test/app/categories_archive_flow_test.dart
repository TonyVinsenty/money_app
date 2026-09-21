import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/app/app.dart';
import 'package:money_app/app/app_routes.dart';
import 'package:money_app/app/app_scope.dart' show AppScopeHost;
import 'package:money_app/app/app_shell.dart';
import 'package:money_app/app/app_tabs.dart';
import 'package:money_app/app/open_and_seed_database.dart';
import 'package:money_app/core/database/app_database.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/categories/presentation/categories_screen.dart';
import 'package:money_app/features/categories/presentation/category_form_screen.dart';
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';
import 'package:money_app/features/transactions/data/transactions_repository_impl.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';
import 'package:money_app/features/transactions/presentation/quick_add/category_picker_screen.dart';

import '../support/fake_id_generator.dart';
import '../support/fixed_clock.dart';
import '../support/in_memory_database.dart';

/// Сквозной путь на настоящей базе в памяти: «Настройки» -> «Категории» ->
/// «В архив» -> сетка быстрого ввода без категории, «История» с ней.
final _clock = FixedClock(DateTime(2026, 9, 20, 15, 30));

late AppDatabase _db;

Future<void> _pumpApp(WidgetTester tester) async {
  final settings = AppSettingsController();
  addTearDown(settings.dispose);
  _db = await openAndSeedDatabase(
    openInMemoryDatabase,
    idGenerator: FakeIdGenerator(prefix: 'seed'),
    clock: _clock,
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      locale: MoneyApp.appLocale,
      supportedLocales: MoneyApp.supportedLocales,
      localizationsDelegates: MoneyApp.localizationsDelegates,
      onGenerateRoute: onGenerateAppRoute,
      home: AppScopeHost(
        database: _db,
        settings: settings,
        clock: _clock,
        idGenerator: FakeIdGenerator(prefix: 'tx'),
        child: AppShell(tabs: defaultAppTabs),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _openTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

/// Форма ждёт первое значение потока drift (порядок новой категории): в
/// фейковом времени виджет-теста оно не приходит, поэтому даём базе немного
/// настоящего времени.
Future<void> _waitForDatabase(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 200)),
  );
  await tester.pumpAndSettle();
}

Future<String> _expenseCategoryId(String name) async {
  final row = await (_db.select(
    _db.categories,
  )..where((c) => c.name.equals(name) & c.kind.equals('expense'))).getSingle();
  return row.id;
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
  });

  testWidgets('создание и переименование категории на настоящей базе', (
    tester,
  ) async {
    await _pumpApp(tester);
    Future<void> scrollTo(Finder target) => tester.scrollUntilVisible(
      target,
      200,
      scrollable: find.descendant(
        of: find.byType(ReorderableListView),
        matching: find.byType(Scrollable),
      ),
    );

    await _openTab(tester, 'Настройки');
    await tester.tap(find.text(categoriesScreenTitle));
    await tester.pumpAndSettle();

    // Создание: форма открывается по именованному маршруту, id из генератора.
    await tester.tap(find.text(categoriesAddAction));
    await tester.pumpAndSettle();
    expect(find.text(categoryFormCreateTitle), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Тренажёрка');
    await tester.tap(find.text(categoryFormSaveLabel));
    await _waitForDatabase(tester);
    expect(find.text(categoryFormCreateTitle), findsNothing);
    await scrollTo(find.text('Тренажёрка'));
    expect(find.text('Тренажёрка'), findsOneWidget);

    // Переименование.
    await tester.tap(find.byTooltip(categoriesRenameLabel('Тренажёрка')));
    await tester.pumpAndSettle();
    expect(find.text(categoryFormRenameTitle), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Бассейн');
    await tester.tap(find.text(categoryFormSaveLabel));
    await _waitForDatabase(tester);
    await scrollTo(find.text('Бассейн'));
    expect(find.text('Бассейн'), findsOneWidget);
    expect(find.text('Тренажёрка'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await _db.close();
  });

  testWidgets(
    'порядок, заданный перетаскиванием, виден в сетке быстрого ввода',
    (tester) async {
      await _pumpApp(tester);
      final food = await _expenseCategoryId('Продукты');

      await _openTab(tester, 'Настройки');
      await tester.tap(find.text(categoriesScreenTitle));
      await tester.pumpAndSettle();

      // Ручку «Продуктов» тянем на строку вниз: «Кафе» становится первой.
      final handle = find.descendant(
        of: find.byKey(ValueKey<String>(food)),
        matching: find.byIcon(Icons.drag_handle),
      );
      final gesture = await tester.startGesture(tester.getCenter(handle));
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();
      await gesture.moveBy(const Offset(0, 40));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      await _waitForDatabase(tester);
      expect(
        tester.getTopLeft(find.text('Кафе')).dy,
        lessThan(tester.getTopLeft(find.text('Продукты')).dy),
      );

      // Записано в базу: порядок в самой таблице тоже новый.
      final rows =
          await (_db.select(_db.categories)
                ..where((c) => c.kind.equals('expense') & c.parentId.isNull())
                ..orderBy([(c) => OrderingTerm.asc(c.sortOrder)]))
              .get();
      expect(rows.take(2).map((c) => c.name), ['Кафе', 'Продукты']);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await _openTab(tester, 'Главная');
      await tester.tap(find.text('Расход'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '350');
      await tester.tap(find.widgetWithText(FilledButton, 'Далее'));
      await tester.pumpAndSettle();
      expect(find.byType(CategoryPickerScreen), findsOneWidget);

      // Плитки идут слева направо, затем вниз: «Кафе» левее «Продуктов».
      final cafe = tester.getTopLeft(find.text('Кафе'));
      final products = tester.getTopLeft(find.text('Продукты'));
      expect(cafe.dy, products.dy);
      expect(cafe.dx, lessThan(products.dx));

      await tester.pumpWidget(const SizedBox());
      await _db.close();
    },
  );

  testWidgets(
    'архивная категория пропадает из сетки, но остаётся в «Истории»',
    (tester) async {
      await _pumpApp(tester);
      final cafe = await _expenseCategoryId('Кафе');
      await DriftTransactionsRepository(_db, clock: _clock).add(
        Transaction(
          id: 'tx-cafe',
          type: TransactionType.expense,
          amount: Money.fromMinor(12000, 'RUB'),
          occurredOn: DateOnly(2026, 9, 20),
          occurredAt: DateTime(2026, 9, 20, 12).toUtc(),
          categoryId: cafe,
        ),
      );

      // «Настройки» -> «Категории» -> «В архив» у «Кафе».
      await _openTab(tester, 'Настройки');
      await tester.tap(find.text(categoriesScreenTitle));
      await tester.pumpAndSettle();
      expect(find.text('Кафе'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byKey(ValueKey<String>(cafe)),
          matching: find.byType(TextButton),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Кафе'), findsNothing);
      // Раздел архива внизу длинного списка: до него нужно прокрутить.
      await tester.scrollUntilVisible(
        find.text(categoriesArchiveTitle(1)),
        200,
        scrollable: find.descendant(
          of: find.byType(ReorderableListView),
          matching: find.byType(Scrollable),
        ),
      );
      expect(find.text(categoriesArchiveTitle(1)), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      // «История»: операция цела, имя категории на месте.
      await _openTab(tester, 'История');
      expect(find.text('Кафе'), findsOneWidget);

      // Быстрый ввод: в сетке остальные категории, «Кафе» нет.
      await _openTab(tester, 'Главная');
      await tester.tap(find.text('Расход'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '350');
      await tester.tap(find.widgetWithText(FilledButton, 'Далее'));
      await tester.pumpAndSettle();
      expect(find.byType(CategoryPickerScreen), findsOneWidget);
      expect(find.text('Продукты'), findsOneWidget);
      expect(find.text('Кафе'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await _db.close();
    },
  );
}
