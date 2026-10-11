import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/app/app.dart';
import 'package:money_app/app/app_routes.dart';
import 'package:money_app/app/app_scope.dart' show AppScopeHost;
import 'package:money_app/app/app_shell.dart';
import 'package:money_app/app/app_tabs.dart';
import 'package:money_app/app/browse_scope.dart';
import 'package:money_app/app/open_and_seed_database.dart';
import 'package:money_app/core/database/app_database.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/analytics/presentation/operations_section.dart';
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';
import 'package:money_app/features/transactions/data/transactions_repository_impl.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';
import 'package:money_app/features/transactions/presentation/edit/edit_transaction_screen.dart';

import '../support/fake_id_generator.dart';
import '../support/fixed_clock.dart';
import '../support/in_memory_database.dart';

/// «Аналитика» -> «Операции» -> тап по строке -> правка (настоящая база в
/// памяти, сегодня 20 сентября 2026).
late AppDatabase _db;
late DriftTransactionsRepository _repo;

Future<void> _pumpApp(WidgetTester tester) async {
  final clock = FixedClock(DateTime(2026, 9, 20, 15, 30));
  final settings = AppSettingsController();
  addTearDown(settings.dispose);
  _db = await openAndSeedDatabase(
    openInMemoryDatabase,
    idGenerator: FakeIdGenerator(prefix: 'seed'),
    clock: clock,
  );
  addTearDown(_db.close);
  _repo = DriftTransactionsRepository(_db, clock: clock);
  final category =
      await (_db.select(
            _db.categories,
          )..where((c) => c.name.equals('Продукты') & c.kind.equals('expense')))
          .getSingle();
  for (final (id, minor, note) in [
    ('big', 900000, 'холодильник'),
    ('small', 10000, 'молоко'),
  ]) {
    await _repo.add(
      Transaction(
        id: id,
        type: TransactionType.expense,
        amount: Money.fromMinor(minor, 'RUB'),
        occurredOn: DateOnly(2026, 9, 18),
        occurredAt: DateTime(2026, 9, 18, 12).toUtc(),
        categoryId: category.id,
        note: note,
      ),
    );
  }
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
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
        clock: clock,
        idGenerator: FakeIdGenerator(prefix: 'tx'),
        child: BrowseHost(child: AppShell(tabs: defaultAppTabs)),
      ),
    ),
  );
  await tester.pump();
  await tester.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Аналитика'),
    ),
  );
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.widgetWithText(Tab, 'Операции'));
  await tester.tap(find.widgetWithText(Tab, 'Операции'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
  });

  testWidgets('«Крупные расходы»: по убыванию, касание открывает правку', (
    tester,
  ) async {
    await _pumpApp(tester);

    expect(find.text('Крупные расходы'), findsOneWidget);
    final big = find.byKey(OperationsSection.rowKey('big'));
    final small = find.byKey(OperationsSection.rowKey('small'));
    expect(big, findsOneWidget);
    expect(tester.getTopLeft(big).dy, lessThan(tester.getTopLeft(small).dy));

    await tester.tap(big);
    await tester.pumpAndSettle();
    expect(find.byType(EditTransactionScreen), findsOneWidget);
    expect(find.text('холодильник'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('удаление в правке: строка исчезла из «Крупных»', (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.byKey(OperationsSection.rowKey('big')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithIcon(IconButton, Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(find.byType(EditTransactionScreen), findsNothing);
    expect(find.byKey(OperationsSection.rowKey('big')), findsNothing);
    expect(find.byKey(OperationsSection.rowKey('small')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
