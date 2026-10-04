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
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';
import 'package:money_app/features/transactions/data/transactions_repository_impl.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

import '../support/fake_id_generator.dart';
import '../support/fixed_clock.dart';
import '../support/in_memory_database.dart';
import '../support/settle_database.dart';

/// Итог расходов месяца на «Главной» на настоящей базе в памяти: поток из
/// репозитория, границы месяца, доходы и чужие месяцы, обновление без
/// ручного «обновить».
late AppDatabase _db;
late FixedClock _clock;

/// Пустое состояние расходов: «Пока нет» внутри карточки расходов.
final _empty = find.descendant(
  of: find.byKey(const ValueKey('month-summary-expense')),
  matching: find.text('Пока нет'),
);

/// Текст внутри карточки итога: в центре кольца диаграммы бывает та же сумма
/// (баланс), поэтому ищем только в карточках итогов.
Finder _inExpense(String text) => find.descendant(
  of: find.byKey(const ValueKey('month-summary-expense')),
  matching: find.text(text),
);

Finder _inIncome(String text) => find.descendant(
  of: find.byKey(const ValueKey('month-summary-income')),
  matching: find.text(text),
);

/// Сумма расходов со знаком «минус» (U+2212). Подпись «Расходы за месяц» стоит
/// отдельной строкой, её проверяем отдельно.
String _total(int minor) =>
    '\u2212${formatMoney(Money.fromMinor(minor, 'RUB'))}';

/// Собирает приложение как `MoneyApp`. [seed] выполняется после открытия базы,
/// но до первого кадра: так «Главная» с самого начала видит данные.
Future<void> _pumpApp(
  WidgetTester tester, {
  DateTime? now,
  Future<void> Function()? seed,
}) async {
  _clock = FixedClock(now ?? DateTime(2026, 9, 20, 15, 30));
  final settings = AppSettingsController();
  addTearDown(settings.dispose);
  _db = await openAndSeedDatabase(
    openInMemoryDatabase,
    idGenerator: FakeIdGenerator(prefix: 'seed'),
    clock: _clock,
  );
  await seed?.call();
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

Future<String> _categoryId(String name, TransactionType type) async {
  final kind = type == TransactionType.income ? 'income' : 'expense';
  final row = await (_db.select(
    _db.categories,
  )..where((c) => c.name.equals(name) & c.kind.equals(kind))).getSingle();
  return row.id;
}

/// Кладёт операцию прямо в базу (в любой день, в том числе будущий: форма
/// такое не позволяет, а границы месяца проверить надо).
Future<void> _put(
  String id,
  TransactionType type,
  int minor,
  DateOnly day,
) async {
  final categoryName = type == TransactionType.income ? 'Зарплата' : 'Продукты';
  await DriftTransactionsRepository(_db, clock: _clock).add(
    Transaction(
      id: id,
      type: type,
      amount: Money.fromMinor(minor, 'RUB'),
      occurredOn: day,
      occurredAt: DateTime(day.year, day.month, day.day, 12).toUtc(),
      categoryId: await _categoryId(categoryName, type),
    ),
  );
}

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

  testWidgets('операций нет: пустое состояние', (tester) async {
    await _pumpApp(tester);
    await tester.pumpAndSettle();

    expect(_empty, findsOneWidget);
    expect(find.text('Расходы за сентябрь'), findsOneWidget);
    await _finish(tester);
  });

  testWidgets('итог есть с первого показа: пустое состояние не мигает', (
    tester,
  ) async {
    await _pumpApp(
      tester,
      seed: () =>
          _put('a', TransactionType.expense, 1234500, DateOnly(2026, 9, 5)),
    );

    // Кадр за кадром до появления итога: «расходов нет» не должно мелькнуть.
    var shown = false;
    for (var i = 0; i < 20 && !shown; i++) {
      expect(_empty, findsNothing, reason: 'кадр $i');
      shown = _inExpense(_total(1234500)).evaluate().isNotEmpty;
      if (!shown) await tester.pump(const Duration(milliseconds: 10));
    }
    expect(shown, isTrue);
    expect(_empty, findsNothing);
    await _finish(tester);
  });

  testWidgets(
    'в итог входят только расходы текущего месяца, границы включены',
    (tester) async {
      await _pumpApp(
        tester,
        seed: () async {
          await _put(
            'e1',
            TransactionType.expense,
            10000,
            DateOnly(2026, 9, 1),
          );
          await _put(
            'e2',
            TransactionType.expense,
            20000,
            DateOnly(2026, 9, 30),
          );
          await _put(
            'e3',
            TransactionType.expense,
            5000,
            DateOnly(2026, 9, 15),
          );
          // Не входят: соседние месяцы и доход.
          await _put('x1', TransactionType.expense, 700, DateOnly(2026, 8, 31));
          await _put('x2', TransactionType.expense, 900, DateOnly(2026, 10, 1));
          await _put(
            'x3',
            TransactionType.income,
            999900,
            DateOnly(2026, 9, 15),
          );
        },
      );
      await tester.pumpAndSettle();

      expect(_inExpense(_total(35000)), findsOneWidget);
      expect(_empty, findsNothing);
      await _finish(tester);
    },
  );

  testWidgets('месяц в заголовке идёт от часов: октябрь', (tester) async {
    await _pumpApp(
      tester,
      now: DateTime(2026, 10, 1, 0, 5),
      seed: () async {
        await _put('e1', TransactionType.expense, 900, DateOnly(2026, 10, 1));
        await _put('x1', TransactionType.expense, 700, DateOnly(2026, 9, 30));
      },
    );
    await tester.pumpAndSettle();

    expect(find.text('Расходы за октябрь'), findsOneWidget);
    expect(_inExpense(_total(900)), findsOneWidget);
    await _finish(tester);
  });

  testWidgets('только доход: расходов ещё нет', (tester) async {
    await _pumpApp(
      tester,
      seed: () =>
          _put('i1', TransactionType.income, 500000, DateOnly(2026, 9, 3)),
    );
    await tester.pumpAndSettle();

    expect(_empty, findsOneWidget);
    await _finish(tester);
  });

  group('строка «Доходы за месяц»', () {
    final emptyIncome = find.descendant(
      of: find.byKey(const ValueKey('month-summary-income')),
      matching: find.text('Пока нет'),
    );
    String income(int minor) =>
        '+${formatMoney(Money.fromMinor(minor, 'RUB'))}';

    testWidgets('доходов нет: пустое состояние, расход в неё не входит', (
      tester,
    ) async {
      await _pumpApp(
        tester,
        seed: () =>
            _put('e1', TransactionType.expense, 999900, DateOnly(2026, 9, 3)),
      );
      await tester.pumpAndSettle();

      expect(emptyIncome, findsOneWidget);
      expect(find.text('Доходы за сентябрь'), findsOneWidget);
      expect(_inExpense(_total(999900)), findsOneWidget);
      await _finish(tester);
    });

    testWidgets(
      'в итог входят только доходы текущего месяца, границы включены',
      (tester) async {
        await _pumpApp(
          tester,
          seed: () async {
            await _put(
              'i1',
              TransactionType.income,
              10000,
              DateOnly(2026, 9, 1),
            );
            await _put(
              'i2',
              TransactionType.income,
              20000,
              DateOnly(2026, 9, 30),
            );
            await _put(
              'i3',
              TransactionType.income,
              5000,
              DateOnly(2026, 9, 15),
            );
            // Не входят: соседние месяцы и расход.
            await _put(
              'x1',
              TransactionType.income,
              700,
              DateOnly(2026, 8, 31),
            );
            await _put(
              'x2',
              TransactionType.income,
              900,
              DateOnly(2026, 10, 1),
            );
            await _put(
              'x3',
              TransactionType.expense,
              999900,
              DateOnly(2026, 9, 15),
            );
          },
        );
        await tester.pumpAndSettle();

        expect(_inIncome(income(35000)), findsOneWidget);
        expect(emptyIncome, findsNothing);
        await _finish(tester);
      },
    );

    testWidgets('доход есть с первого показа: пустое состояние не мигает', (
      tester,
    ) async {
      await _pumpApp(
        tester,
        seed: () =>
            _put('i1', TransactionType.income, 1234500, DateOnly(2026, 9, 5)),
      );

      var shown = false;
      for (var i = 0; i < 20 && !shown; i++) {
        expect(emptyIncome, findsNothing, reason: 'кадр $i');
        shown = _inIncome(income(1234500)).evaluate().isNotEmpty;
        if (!shown) await tester.pump(const Duration(milliseconds: 10));
      }
      expect(shown, isTrue);
      await _finish(tester);
    });

    testWidgets('доход, сохранённый быстрым вводом, попадает в строку сам, '
        '«Отменить» возвращает пустое состояние', (tester) async {
      await _pumpApp(tester);
      await tester.pumpAndSettle();
      expect(emptyIncome, findsOneWidget);

      await tester.tap(find.text('Доход'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '1500,50');
      await tester.tap(find.widgetWithText(FilledButton, 'Далее'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Зарплата'));
      await settleDatabase(tester);

      expect(_inIncome(income(150050)), findsOneWidget);
      expect(emptyIncome, findsNothing);
      // Расходов доход не трогает.
      expect(_empty, findsOneWidget);

      await tester.tap(find.text('Отменить'));
      await tester.pumpAndSettle();
      expect(emptyIncome, findsOneWidget);
      await _finish(tester);
    });
  });

  testWidgets('после сохранения расхода итог обновляется сам, «Отменить» '
      'возвращает пустое состояние', (tester) async {
    await _pumpApp(tester);
    await tester.pumpAndSettle();
    expect(_empty, findsOneWidget);

    // «Главная» -> «Расход» -> сумма -> категория. Кнопки выше сообщения,
    // поэтому «Расход» доступен и при показанном сообщении (второй расход).
    Future<void> addExpense(String amount) async {
      await tester.tap(find.text('Расход'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), amount);
      await tester.tap(find.widgetWithText(FilledButton, 'Далее'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Продукты'));
      await settleDatabase(tester);
    }

    await addExpense('350');
    expect(_inExpense(_total(35000)), findsOneWidget);
    expect(_empty, findsNothing);

    // Сообщение ещё на экране, а следующий расход уже вводится.
    expect(find.byType(SnackBar), findsOneWidget);
    await addExpense('150,50');
    expect(_inExpense(_total(50050)), findsOneWidget);

    // «Отменить» относится к последней записи: итог откатывается сам.
    await tester.tap(find.text('Отменить'));
    await tester.pumpAndSettle();
    expect(_inExpense(_total(35000)), findsOneWidget);
    await _finish(tester);
  });
}
