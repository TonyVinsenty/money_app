import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/csv_import/domain/csv_import_result.dart';
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
  _PlanningStore({
    this.categories = const [],
    this.liveIds = const {},
    this.accounts = const [],
  });

  final List<Category> categories;
  final List<Account> accounts;
  final Set<String> liveIds;
  Object? writeError;
  Object? prepareError;

  /// Если задан, запись ждёт его завершения.
  Completer<void>? writeGate;
  final List<CsvImportPlan> written = [];

  @override
  Future<CsvImportPlan> prepare(
    List<ParsedCsvRow> rows, {
    List<ParsedOpeningBalance> openingBalances = const [],
  }) async {
    final error = prepareError;
    if (error != null) return Future.error(error);
    return planCsvImport(
      rows: rows,
      openingBalances: openingBalances,
      isKnownIconKey: (_) => true,
      categories: categories,
      accounts: accounts,
      liveTransactionIds: liveIds,
      deletedTransactionIds: const {},
      ids: FakeIdGenerator(prefix: 'new'),
    );
  }

  @override
  Future<void> write(CsvImportPlan plan) async {
    await writeGate?.future;
    final error = writeError;
    if (error != null) return Future.error(error);
    written.add(plan);
  }
}

/// Объявления скринридеру (VoiceOver/TalkBack), сделанные во время теста.
List<String> _captureAnnouncements(WidgetTester tester) {
  final announcements = <String>[];
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockDecodedMessageHandler<dynamic>(
    SystemChannels.accessibility,
    (message) async {
      final map = message as Map<Object?, Object?>;
      if (map['type'] == 'announce') {
        final data = map['data']! as Map<Object?, Object?>;
        announcements.add(data['message']! as String);
      }
      return null;
    },
  );
  addTearDown(
    () => messenger.setMockDecodedMessageHandler<dynamic>(
      SystemChannels.accessibility,
      null,
    ),
  );
  return announcements;
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
Future<List<CsvImportResult?>> _open(
  WidgetTester tester, {
  required String csv,
  required CsvImportStore store,
  List<int>? bytes,
}) async {
  final results = <CsvImportResult?>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            final result = await Navigator.of(context).push<CsvImportResult>(
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
    expect(find.text('Расходы'), findsOneWidget);
    expect(find.text('Еда: Кафе'), findsOneWidget);
    expect(find.text('Доходы'), findsOneWidget);
    expect(find.text('Кэшбэк (новая)'), findsOneWidget);

    await tester.tap(find.text(csvImportLoadButton));
    await tester.pumpAndSettle();

    expect(store.written.single.transactions, hasLength(2));
    expect(results, [const CsvImportResult(transactions: 2)]);
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
    expect(results, [const CsvImportResult(transactions: 1)]);
  });

  testWidgets(
    'сбой записи не Exception: текст ошибки, «назад» снова работает',
    (tester) async {
      final store = _PlanningStore()..writeError = StateError('неожиданно');
      final results = await _open(
        tester,
        store: store,
        csv: '$_header\n01.10.2026;Расход;350;Еда;;\n',
      );

      await tester.tap(find.text(csvImportLoadButton));
      await tester.pumpAndSettle();

      expect(find.text(csvImportWriteFailedMessage), findsOneWidget);
      expect(find.text(csvImportWritingLabel), findsNothing);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(results, [null]);
    },
  );

  testWidgets('сбой проверки не Exception — понятный текст', (tester) async {
    final store = _PlanningStore()..prepareError = StateError('неожиданно');
    await _open(
      tester,
      store: store,
      csv: '$_header\n01.10.2026;Расход;350;Еда;;\n',
    );

    expect(find.text(csvImportReadFailedMessage), findsOneWidget);
    expect(find.text(csvImportCheckingLabel), findsNothing);
  });

  testWidgets('крупный текст: кнопки друг под другом, «Загрузить» сверху', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(3)),
          child: child!,
        ),
        home: CsvImportScreen(
          path: '/tmp/import.csv',
          clock: FixedClock(DateTime(2026, 10, 7, 12)),
          store: _PlanningStore(categories: [_food]),
          categories: Stream.value([_food]),
          readBytes: (_) async =>
              utf8.encode('$_header\n01.10.2026;Расход;350;Еда;;\n'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final load = tester.getRect(find.text(csvImportLoadButton));
    final cancel = tester.getRect(find.text(csvImportCancelButton));
    expect(load.bottom, lessThanOrEqualTo(cancel.top));
    expect(load.right, lessThanOrEqualTo(320));
    expect(cancel.right, lessThanOrEqualTo(320));
  });

  group('скринридер', () {
    testWidgets('предпросмотр и запись объявляются', (tester) async {
      final announcements = _captureAnnouncements(tester);
      final store = _PlanningStore(categories: [_food])
        ..writeGate = Completer<void>();
      final results = await _open(
        tester,
        store: store,
        csv: '$_header\n01.10.2026;Расход;350;Еда;;\n',
      );
      expect(announcements, [csvImportWillAdd(1)]);

      await tester.tap(find.text(csvImportLoadButton));
      await tester.pump();
      expect(announcements, [csvImportWillAdd(1), csvImportWritingLabel]);
      // Кружок на кнопке спрятан: кнопка читается текстом «Загружаем…».
      expect(
        find.ancestor(
          of: find.byType(CircularProgressIndicator),
          matching: find.byType(ExcludeSemantics),
        ),
        findsWidgets,
      );

      store.writeGate!.complete();
      await tester.pumpAndSettle();
      expect(results, [const CsvImportResult(transactions: 1)]);
    });

    testWidgets('ошибки в файле объявляются', (tester) async {
      final announcements = _captureAnnouncements(tester);
      await _open(
        tester,
        store: _PlanningStore(),
        csv: '$_header\n01.10.2026;Расход;abc;Еда;;\n',
      );

      expect(announcements, [csvImportErrorsIntro]);
    });

    testWidgets('«Нечего добавлять» объявляется', (tester) async {
      final announcements = _captureAnnouncements(tester);
      const id = '0190f0a0-0000-7000-8000-000000000001';
      await _open(
        tester,
        store: _PlanningStore(liveIds: {id}),
        csv: '$_header\n01.10.2026;Расход;350;Еда;;$id\n',
      );

      expect(announcements, [csvImportNothingToAddMessage]);
    });

    testWidgets('файл не прочитался — объявляется', (tester) async {
      final announcements = _captureAnnouncements(tester);
      final store = _PlanningStore()..prepareError = StateError('неожиданно');
      await _open(
        tester,
        store: store,
        csv: '$_header\n01.10.2026;Расход;350;Еда;;\n',
      );

      expect(announcements, [csvImportReadFailedMessage]);
    });

    testWidgets('ошибка записи объявляется', (tester) async {
      final announcements = _captureAnnouncements(tester);
      final store = _PlanningStore()..writeError = Exception('диск полон');
      await _open(
        tester,
        store: store,
        csv: '$_header\n01.10.2026;Расход;350;Еда;;\n',
      );

      await tester.tap(find.text(csvImportLoadButton));
      await tester.pumpAndSettle();

      expect(announcements, [
        csvImportWillAdd(1),
        csvImportWritingLabel,
        csvImportWriteFailedMessage,
      ]);
    });
  });

  group('счета в предпросмотре (5.19)', () {
    const header =
        'Дата;Тип;Сумма;Валюта;Категория;Подкатегория;Счёт;ID счёта;'
        'Значок категории;Значок подкатегории';
    final nbsp = String.fromCharCode(0x00A0);
    final minus = String.fromCharCode(0x2212);

    String balance(String account, String amount, [String currency = '']) =>
        '01.09.2026;Начальный остаток;$amount;$currency;;;$account;;;\n';

    testWidgets(
      'операции и счета: список по алфавиту, остаток в валюте счёта',
      (tester) async {
        await _open(
          tester,
          store: _PlanningStore(categories: [_food]),
          csv:
              '$header\n'
              '${balance('Карта', '12000')}'
              '${balance('Кредитка', '-1500')}'
              '${balance('Кошелёк', '0,0015', 'BTC')}'
              '04.10.2026;Расход;5;;Еда;;Наличные;;;\n',
        );

        expect(find.text('Будет добавлена 1 операция'), findsOneWidget);
        expect(find.text(csvImportNewAccountsTitle), findsOneWidget);
        final lines = [
          'Карта (остаток 12${nbsp}000,00$nbsp₽)',
          'Кошелёк (остаток 0,0015${nbsp}BTC)',
          'Кредитка (остаток ${minus}1${nbsp}500,00$nbsp₽)',
          'Наличные',
        ];
        for (final line in lines) {
          expect(find.text(line), findsOneWidget, reason: line);
        }
        // По алфавиту: сверху вниз.
        final tops = [
          for (final l in lines) tester.getTopLeft(find.text(l)).dy,
        ];
        expect([...tops]..sort(), tops);
      },
    );

    testWidgets('озвучка строки счёта через spokenMoney (П3)', (tester) async {
      final handle = tester.ensureSemantics();
      await _open(
        tester,
        store: _PlanningStore(),
        csv:
            '$header\n'
            '${balance('Карта', '12000')}'
            '${balance('Кредитка', '-1500')}'
            '${balance('Кошелёк', '0,0015', 'BTC')}'
            '${balance('Наличные', '0')}',
      );

      for (final label in [
        'Карта, остаток 12000 рублей',
        'Кредитка, остаток минус 1500 рублей',
        'Кошелёк, остаток 0,0015 биткоина',
        'Наличные',
      ]) {
        expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
      }
      handle.dispose();
    });

    testWidgets('без счетов: заголовка счетов нет', (tester) async {
      await _open(
        tester,
        store: _PlanningStore(),
        csv: '$_header\n01.10.2026;Расход;350;Еда;;\n',
      );

      expect(find.text(csvImportNewAccountsTitle), findsNothing);
    });

    testWidgets('П4: только счета — главная строка, «Загрузить» видна', (
      tester,
    ) async {
      final store = _PlanningStore();
      final results = await _open(
        tester,
        store: store,
        csv: '$header\n${balance('Карта', '100')}${balance('Наличные', '0')}',
      );

      expect(find.text('Будут созданы 2 счёта'), findsOneWidget);
      expect(find.text(csvImportNothingToAddMessage), findsNothing);

      await tester.tap(find.text(csvImportLoadButton));
      await tester.pumpAndSettle();
      expect(results, [const CsvImportResult(transactions: 0, accounts: 2)]);
      expect(store.written.single.accountsToCreate, hasLength(2));
    });

    testWidgets('П4: один счёт — «Будет создан 1 счёт»', (tester) async {
      await _open(
        tester,
        store: _PlanningStore(),
        csv: '$header\n${balance('Карта', '100')}',
      );
      expect(find.text('Будет создан 1 счёт'), findsOneWidget);
    });

    testWidgets(
      'счёт уже есть: начальный остаток пропущен, «Нечего добавлять»',
      (tester) async {
        final card = Account(
          id: 'acc-card',
          name: 'Карта',
          iconKey: 'other',
          openingBalance: Money.fromMinor(0, 'RUB'),
          sortOrder: 0,
          currencyDigits: 2,
        );
        await _open(
          tester,
          store: _PlanningStore(accounts: [card]),
          csv: '$header\n${balance('Карта', '12000')}',
        );

        expect(
          csvImportNothingToAddMessage,
          'Нечего добавлять: всё из файла уже есть в приложении',
        );
        expect(find.text(csvImportNothingToAddMessage), findsOneWidget);
        // Счётчик «Пропущено» для начальных остатков (П6) считает план; он
        // пока их не считает (5.18), поэтому здесь не проверяется.
        expect(find.text(csvImportLoadButton), findsNothing);
      },
    );

    testWidgets('П7: объявление с операциями и счетами', (tester) async {
      final announcements = _captureAnnouncements(tester);
      await _open(
        tester,
        store: _PlanningStore(categories: [_food]),
        csv:
            '$header\n'
            '${balance('Карта', '100')}'
            '04.10.2026;Расход;5;;Еда;;Наличные;;;\n',
      );

      expect(announcements, [
        'Будет добавлена 1 операция. Будут созданы 2 счёта: Карта, Наличные',
      ]);
    });

    testWidgets('П7: без операций, больше пяти счетов — «и ещё N»', (
      tester,
    ) async {
      final announcements = _captureAnnouncements(tester);
      await _open(
        tester,
        store: _PlanningStore(),
        csv:
            '$header\n'
            '${[for (final n in 'ВАБГДЕЖ'.split('')) balance('Счёт $n', '1')].join()}'
            '${balance('Яблоко', '1')}',
      );

      expect(announcements, [
        'Будет создано 8 счетов: '
            'Счёт А, Счёт Б, Счёт В, Счёт Г, Счёт Д и ещё 3',
      ]);
    });

    testWidgets('360 dp и шрифт 200 %: без переполнения', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: CsvImportScreen(
            path: '/tmp/import.csv',
            clock: FixedClock(DateTime(2026, 10, 7, 12)),
            store: _PlanningStore(),
            categories: Stream.value(const []),
            readBytes: (_) async => utf8.encode(
              '$header\n'
              '${balance('Очень длинное название накопления', '12000')}'
              '${balance('Кошелёк', '0,0015', 'BTC')}',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text(csvImportLoadButton), findsOneWidget);
      expect(find.textContaining('Кошелёк'), findsOneWidget);
    });
  });
}
