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
import 'package:money_app/core/ui/date_chip.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';
import 'package:money_app/features/transactions/data/transactions_repository_impl.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';
import 'package:money_app/features/transactions/presentation/quick_add/note_field.dart';

import '../support/fake_id_generator.dart';
import '../support/fixed_clock.dart';
import '../support/in_memory_database.dart';
import '../support/settle_database.dart';

/// Сквозной путь сохранения на настоящей базе в памяти: «Главная» -> «Расход»
/// -> сумма -> категория -> запись в таблице и сообщение с «Отменить».
///
/// Собирается так же, как `MoneyApp`, только с фиксированными часами и
/// понятными id (`MoneyApp` берёт настоящие часы).
final _clock = FixedClock(DateTime(2026, 9, 20, 15, 30));

late AppDatabase _db;

Future<void> _pumpApp(WidgetTester tester, {double textScale = 1}) async {
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
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
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

/// «Главная» -> кнопка типа -> сумма -> «Далее».
Future<void> _enterAmount(
  WidgetTester tester, {
  required String button,
  required String amount,
}) async {
  await tester.tap(find.text(button));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), amount);
  await tester.tap(find.widgetWithText(FilledButton, 'Далее'));
  await tester.pumpAndSettle();
}

Future<void> _pickCategory(WidgetTester tester, String name) async {
  await tester.tap(find.text(name));
  await settleDatabase(tester);
}

/// Первое значение живого потока последних операций (то, что увидит
/// «История»). `runAsync`: ожидание потока drift в фейковом времени виджет-
/// теста зависает, а в настоящем времени — нет.
Future<List<Transaction>?> _live(WidgetTester tester) => tester.runAsync(
  () => DriftTransactionsRepository(_db, clock: _clock).watchRecent().first,
);

Future<List<TransactionRow>> _rows() => _db.select(_db.transactions).get();

Future<String> _categoryId(String name, {required String kind}) async {
  final row = await (_db.select(
    _db.categories,
  )..where((c) => c.name.equals(name) & c.kind.equals(kind))).getSingle();
  return row.id;
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
    // У каждого теста своя база в памяти, а drift в отладочном режиме
    // предупреждает о нескольких экземплярах одного класса. Здесь это нормально.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
  });

  testWidgets('расход 350 в «Продукты»: запись, сообщение, «Отменить»', (
    tester,
  ) async {
    await _pumpApp(tester);
    await _enterAmount(tester, button: 'Расход', amount: '350');
    await _pickCategory(tester, 'Продукты');

    // Ровно одна запись с правильными полями.
    final rows = await _rows();
    expect(rows, hasLength(1));
    final row = rows.single;
    expect(row.id, 'tx-1');
    expect(row.type, TransactionType.expense);
    expect(row.amountMinor, 35000);
    expect(row.currency, 'RUB');
    expect(row.occurredOn, DateOnly(2026, 9, 20));
    expect(
      row.occurredAt,
      DateTime(2026, 9, 20, 15, 30).toUtc().millisecondsSinceEpoch,
    );
    expect(row.categoryId, await _categoryId('Продукты', kind: 'expense'));
    expect(row.subcategoryId, isNull);
    expect(row.note, isNull);
    expect(row.deletedAt, isNull);
    // День совпадает с локальным днём момента.
    final moment = DateTime.fromMillisecondsSinceEpoch(
      row.occurredAt,
      isUtc: true,
    ).toLocal();
    expect(DateOnly.fromDateTime(moment), row.occurredOn);

    // Мы на «Главной», сообщение называет тип, сумму и категорию.
    expect(find.byType(NavigationBar), findsOneWidget);
    final amount = formatMoney(Money.fromMinor(35000, 'RUB'));
    expect(find.text('Сохранено: расход $amount · Продукты'), findsOneWidget);
    expect(find.text('Отменить'), findsOneWidget);

    // «Отменить»: запись мягко удалена и пропала из живого потока.
    await tester.tap(find.text('Отменить'));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    expect(await _live(tester), isEmpty);
    final after = await _rows();
    expect(after, hasLength(1));
    expect(after.single.deletedAt, isNotNull);

    await tester.pumpWidget(const SizedBox());
    await _db.close();
  });

  testWidgets('сообщение исчезает само через 6 секунд, запись остаётся', (
    tester,
  ) async {
    await _pumpApp(tester);
    await _enterAmount(tester, button: 'Расход', amount: '350');
    await _pickCategory(tester, 'Продукты');
    expect(find.byType(SnackBar), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    expect(find.byType(SnackBar), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    final rows = await _rows();
    expect(rows.single.deletedAt, isNull);

    await tester.pumpWidget(const SizedBox());
    await _db.close();
  });

  testWidgets(
    'второе сохранение подряд: одно сообщение, отмена — своей записи',
    (tester) async {
      await _pumpApp(tester);
      await _enterAmount(tester, button: 'Расход', amount: '350');
      await _pickCategory(tester, 'Продукты');
      expect(find.textContaining('· Продукты'), findsOneWidget);

      // Первое сообщение ещё на экране, но кнопка «Расход» выше него (панель
      // кнопок лежит в слоте над навигацией), поэтому ввод идёт как обычно.
      await _enterAmount(tester, button: 'Расход', amount: '0');
      await _pickCategory(tester, 'Транспорт');

      expect(await _rows(), hasLength(2));
      expect(find.byType(SnackBar), findsOneWidget);
      final zero = formatMoney(Money.zero('RUB'));
      expect(find.text('Сохранено: расход $zero · Транспорт'), findsOneWidget);
      expect(find.textContaining('· Продукты'), findsNothing);

      // «Отменить» убирает вторую запись, первая остаётся живой.
      await tester.tap(find.text('Отменить'));
      await tester.pumpAndSettle();
      expect((await _live(tester))!.map((t) => t.id), ['tx-1']);

      await tester.pumpWidget(const SizedBox());
      await _db.close();
    },
  );

  group('кнопки и сообщение «Сохранено»', () {
    Finder button(String label) => find.widgetWithText(FilledButton, label);

    void smallPhone(WidgetTester tester) {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    testWidgets('кнопки у нижней навигации: отступ 16 dp, не выше', (
      tester,
    ) async {
      smallPhone(tester);
      await _pumpApp(tester);

      final navTop = tester.getRect(find.byType(NavigationBar)).top;
      for (final label in ['Доход', 'Расход']) {
        expect(
          navTop - tester.getRect(button(label)).bottom,
          closeTo(16, 0.5),
          reason: label,
        );
      }

      await tester.pumpWidget(const SizedBox());
      await _db.close();
    });

    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'шрифт ${(scale * 100).round()} %: сообщение целиком выше кнопок, '
        'кнопки нажимаются, «Отменить» доступна 6 секунд',
        (tester) async {
          smallPhone(tester);
          await _pumpApp(tester, textScale: scale);
          await _enterAmount(tester, button: 'Расход', amount: '350');
          await _pickCategory(tester, 'Продукты');

          expect(tester.takeException(), isNull);
          final snack = tester.getRect(find.byType(SnackBar));
          final navTop = tester.getRect(find.byType(NavigationBar)).top;
          for (final label in ['Доход', 'Расход']) {
            final rect = tester.getRect(button(label));
            // Сообщение над кнопками и не заходит на них: кнопки целы, и
            // сообщение стоит над всей панелью, а не под ней.
            expect(snack.bottom, lessThanOrEqualTo(rect.top), reason: label);
            expect(rect.bottom, lessThanOrEqualTo(navTop), reason: label);
          }
          expect(snack.top, greaterThanOrEqualTo(0));

          // «Отменить» видна и через 5 секунд.
          await tester.pump(const Duration(seconds: 5));
          expect(find.text('Отменить'), findsOneWidget);

          // Кнопки нажимаются, пока сообщение на экране.
          await tester.tap(button('Расход'));
          await tester.pumpAndSettle();
          expect(find.text('Новый расход'), findsOneWidget);

          await tester.pumpWidget(const SizedBox());
          await _db.close();
        },
      );
    }

    testWidgets('на другой вкладке кнопок нет, сообщение над навигацией', (
      tester,
    ) async {
      smallPhone(tester);
      await _pumpApp(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Настройки'),
        ),
      );
      await tester.pumpAndSettle();
      expect(button('Расход'), findsNothing);
      expect(button('Доход'), findsNothing);

      ScaffoldMessenger.of(tester.element(find.byType(NavigationBar)))
          .showSnackBar(const SnackBar(content: Text('Проверка')));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byType(SnackBar)).bottom,
        lessThanOrEqualTo(tester.getRect(find.byType(NavigationBar)).top),
      );

      await tester.pumpWidget(const SizedBox());
      await _db.close();
    });
  });
  testWidgets('выбрано «Вчера»: день и момент вчерашние', (tester) async {
    await _pumpApp(tester);
    await tester.tap(find.text('Расход'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DateChip));
    await tester.pumpAndSettle();
    await tester.tap(find.text('19'));
    await tester.tap(find.text('ОК'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '350');
    await tester.tap(find.widgetWithText(FilledButton, 'Далее'));
    await tester.pumpAndSettle();
    await _pickCategory(tester, 'Продукты');

    final row = (await _rows()).single;
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

    await tester.pumpWidget(const SizedBox());
    await _db.close();
  });

  testWidgets('доход с комментарием: тип, комментарий и сообщение', (
    tester,
  ) async {
    await _pumpApp(tester);
    await _enterAmount(tester, button: 'Доход', amount: '1000,50');
    await tester.enterText(
      find.descendant(
        of: find.byType(NoteField),
        matching: find.byType(TextField),
      ),
      '  аванс ',
    );
    await _pickCategory(tester, 'Зарплата');

    final row = (await _rows()).single;
    expect(row.type, TransactionType.income);
    expect(row.amountMinor, 100050);
    expect(row.note, 'аванс');
    expect(row.categoryId, await _categoryId('Зарплата', kind: 'income'));
    final amount = formatMoney(Money.fromMinor(100050, 'RUB'));
    expect(find.text('Сохранено: доход $amount · Зарплата'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await _db.close();
  });
}
