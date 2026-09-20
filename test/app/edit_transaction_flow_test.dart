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
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/amount_field.dart';
import 'package:money_app/core/ui/date_chip.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/categories/data/categories_repository_impl.dart';
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';
import 'package:money_app/features/transactions/data/transactions_repository_impl.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';
import 'package:money_app/features/transactions/presentation/edit/edit_transaction_screen.dart';
import 'package:money_app/features/transactions/presentation/quick_add/note_field.dart';

import '../support/fake_id_generator.dart';
import '../support/fixed_clock.dart';
import '../support/in_memory_database.dart';

/// Правка операции на настоящей базе в памяти: «История» -> тап по строке ->
/// экран правки -> «Сохранить». Приложение собрано как `MoneyApp`, только с
/// фиксированными часами (сегодня 20 сентября 2026, 15:30).
late FixedClock _clock;
late AppDatabase _db;
late DriftTransactionsRepository _repo;

final _minus = String.fromCharCode(0x2212);

Future<void> _pumpApp(WidgetTester tester) async {
  _clock = FixedClock(DateTime(2026, 9, 20, 15, 30));
  final settings = AppSettingsController();
  addTearDown(settings.dispose);
  _db = await openAndSeedDatabase(
    openInMemoryDatabase,
    idGenerator: FakeIdGenerator(prefix: 'seed'),
    clock: _clock,
  );
  _repo = DriftTransactionsRepository(_db, clock: _clock);
  // Расход 350 ₽ в «Продуктах» сегодня в 15:30 с комментарием.
  await _repo.add(
    Transaction(
      id: 'tx-1',
      type: TransactionType.expense,
      amount: Money.fromMinor(35000, 'RUB'),
      occurredOn: DateOnly(2026, 9, 20),
      occurredAt: DateTime(2026, 9, 20, 15, 30).toUtc(),
      categoryId: await _categoryId('Продукты'),
      note: 'молоко',
    ),
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

Future<String> _categoryId(String name, {String kind = 'expense'}) async {
  final row = await (_db.select(
    _db.categories,
  )..where((c) => c.name.equals(name) & c.kind.equals(kind))).getSingle();
  return row.id;
}

/// «История» -> тап по строке -> экран правки.
Future<void> _openEdit(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('История'),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('молоко'));
  await tester.pumpAndSettle();
  expect(find.byType(EditTransactionScreen), findsOneWidget);
}

Finder get _amountInput => find.descendant(
  of: find.byType(AmountField),
  matching: find.byType(TextField),
);

Finder get _noteInput => find.descendant(
  of: find.byType(NoteField),
  matching: find.byType(TextField),
);

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
  await tester.pumpAndSettle();
}

Future<TransactionRow> _row() => (_db.select(
  _db.transactions,
)..where((t) => t.id.equals('tx-1'))).getSingle();

Future<void> _finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await _db.close();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
  });

  testWidgets('экран заполнен текущими значениями, тип виден словом и знаком', (
    tester,
  ) async {
    await _pumpApp(tester);
    await _openEdit(tester);

    expect(find.text('Правка расхода'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.remove),
      ),
      findsOneWidget,
    );
    expect(
      tester.widget<TextField>(_amountInput).controller!.text,
      formatMoney(Money.fromMinor(35000, 'RUB'), withCurrencySymbol: false),
    );
    expect(find.text('Сегодня'), findsWidgets);
    expect(find.text('Продукты'), findsOneWidget);
    expect(tester.widget<TextField>(_noteInput).controller!.text, 'молоко');
    await _finish(tester);
  });

  testWidgets(
    'новая сумма доходит до базы; updatedAt новый, id/createdAt/день прежние',
    (tester) async {
      await _pumpApp(tester);
      final before = await _row();
      _clock.advance(const Duration(minutes: 5));
      await _openEdit(tester);

      await tester.enterText(_amountInput, '500,50');
      await _save(tester);

      final after = await _row();
      expect(after.id, 'tx-1');
      expect(after.amountMinor, 50050);
      expect(after.currency, 'RUB');
      expect(after.createdAt, before.createdAt);
      expect(after.updatedAt, greaterThan(before.updatedAt));
      expect(after.type, TransactionType.expense);
      // Дату не трогали: день и момент те же, что были.
      expect(after.occurredOn, before.occurredOn);
      expect(after.occurredAt, before.occurredAt);
      expect(after.categoryId, before.categoryId);
      expect(after.note, 'молоко');

      // Возврат в «Историю», сообщение, строка обновилась сама.
      expect(find.byType(EditTransactionScreen), findsNothing);
      expect(find.text('Изменения сохранены'), findsOneWidget);
      expect(find.text('Отменить'), findsNothing);
      final shown = '$_minus${formatMoney(Money.fromMinor(50050, 'RUB'))}';
      expect(find.text(shown), findsOneWidget);
      await _finish(tester);
    },
  );

  testWidgets('сообщение о сохранении исчезает само через 4 секунды', (
    tester,
  ) async {
    await _pumpApp(tester);
    await _openEdit(tester);
    await tester.enterText(_amountInput, '10');
    await _save(tester);

    expect(find.text('Изменения сохранены'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Изменения сохранены'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Изменения сохранены'), findsNothing);
    await _finish(tester);
  });

  testWidgets('нулевая сумма допустима', (tester) async {
    await _pumpApp(tester);
    await _openEdit(tester);
    await tester.enterText(_amountInput, '0');
    await _save(tester);

    expect((await _row()).amountMinor, 0);
    expect(find.byType(EditTransactionScreen), findsNothing);
    await _finish(tester);
  });

  testWidgets('пустая сумма: ошибка под полем, ничего не записано', (
    tester,
  ) async {
    await _pumpApp(tester);
    final before = await _row();
    await _openEdit(tester);
    await tester.enterText(_amountInput, '');
    await _save(tester);

    expect(find.text('Введите сумму'), findsOneWidget);
    expect(find.byType(EditTransactionScreen), findsOneWidget);
    final after = await _row();
    expect(after.amountMinor, before.amountMinor);
    expect(after.updatedAt, before.updatedAt);
    await _finish(tester);
  });

  testWidgets('смена даты даёт согласованные occurredOn и occurredAt', (
    tester,
  ) async {
    await _pumpApp(tester);
    await _openEdit(tester);
    await tester.tap(find.byType(DateChip));
    await tester.pumpAndSettle();
    await tester.tap(find.text('19'));
    await tester.tap(find.text('ОК'));
    await tester.pumpAndSettle();
    await _save(tester);

    final row = await _row();
    expect(row.occurredOn, DateOnly(2026, 9, 19));
    expect(
      row.occurredAt,
      DateTime(2026, 9, 19, 12).toUtc().millisecondsSinceEpoch,
    );
    final moment = DateTime.fromMillisecondsSinceEpoch(
      row.occurredAt,
      isUtc: true,
    ).toLocal();
    expect(DateOnly.fromDateTime(moment), row.occurredOn);
    // Сумма и категория не тронуты.
    expect(row.amountMinor, 35000);
    // В «Истории» строка переехала под заголовок «Вчера».
    expect(find.text('Вчера'), findsOneWidget);
    await _finish(tester);
  });

  testWidgets('смена категории доходит до базы, показывается новая', (
    tester,
  ) async {
    await _pumpApp(tester);
    await _openEdit(tester);

    await tester.tap(find.text('Категория'));
    await tester.pumpAndSettle();
    expect(find.text('Категория расхода'), findsOneWidget);
    await tester.tap(find.text('Кафе'));
    await tester.pumpAndSettle();

    // Вернулись на правку, категория показана новая.
    expect(find.byType(EditTransactionScreen), findsOneWidget);
    expect(find.text('Кафе'), findsOneWidget);
    await _save(tester);

    final row = await _row();
    expect(row.categoryId, await _categoryId('Кафе'));
    expect(row.subcategoryId, isNull);
    expect(row.amountMinor, 35000);
    await _finish(tester);
  });

  testWidgets('комментарий: новый доходит до базы, пустой даёт null', (
    tester,
  ) async {
    await _pumpApp(tester);
    await _openEdit(tester);
    await tester.enterText(_noteInput, '  сыр ');
    await _save(tester);
    expect((await _row()).note, 'сыр');

    await tester.tap(find.text('сыр'));
    await tester.pumpAndSettle();
    await tester.enterText(_noteInput, '');
    await _save(tester);
    expect((await _row()).note, isNull);
    await _finish(tester);
  });

  testWidgets('выход без сохранения ничего не меняет и не спрашивает', (
    tester,
  ) async {
    await _pumpApp(tester);
    final before = await _row();
    _clock.advance(const Duration(minutes: 5));
    await _openEdit(tester);
    await tester.enterText(_amountInput, '999');
    await tester.enterText(_noteInput, 'другое');

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.byType(EditTransactionScreen), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Изменения сохранены'), findsNothing);
    final after = await _row();
    expect(after.amountMinor, before.amountMinor);
    expect(after.note, before.note);
    expect(after.updatedAt, before.updatedAt);
    await _finish(tester);
  });

  testWidgets(
    'архивная текущая категория: показана по имени, сохраняется без ошибки',
    (tester) async {
      await _pumpApp(tester);
      final food = await _categoryId('Продукты');
      await DriftCategoriesRepository(_db, clock: _clock).archive(food);
      await _openEdit(tester);

      expect(find.text('Продукты'), findsOneWidget);
      await tester.enterText(_amountInput, '77');
      await _save(tester);

      expect(find.byType(EditTransactionScreen), findsNothing);
      final row = await _row();
      expect(row.amountMinor, 7700);
      expect(row.categoryId, food);
      await _finish(tester);
    },
  );

  testWidgets('операцию удалили, пока экран был открыт: понятная ошибка', (
    tester,
  ) async {
    await _pumpApp(tester);
    await _openEdit(tester);
    await tester.runAsync(() => _repo.softDelete('tx-1'));
    await tester.enterText(_amountInput, '10');
    await _save(tester);

    expect(find.text(EditTransactionScreen.goneText), findsOneWidget);
    expect(find.byType(EditTransactionScreen), findsOneWidget);
    expect((await _row()).amountMinor, 35000);
    await _finish(tester);
  });
}
