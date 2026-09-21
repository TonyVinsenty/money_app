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
          of: find.byType(ListView),
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
