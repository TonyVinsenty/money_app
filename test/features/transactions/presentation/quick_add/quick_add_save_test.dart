import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/app/app.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/date_chip.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/core/ui/transaction_rule_text.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_rules.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';
import 'package:money_app/features/transactions/presentation/quick_add/category_picker_screen.dart';
import 'package:money_app/features/transactions/presentation/quick_add/note_field.dart';
import 'package:money_app/features/transactions/presentation/quick_add/quick_add_screen.dart';

import '../../../../support/fake_id_generator.dart';
import '../../../../support/fakes.dart';
import '../../../../support/fixed_clock.dart';

/// Репозиторий операций, который запоминает вызовы; поведение (задержка,
/// ошибка) тест задаёт сам.
class _RecordingTransactions extends FakeTransactionsRepository {
  final added = <Transaction>[];
  final deleted = <String>[];
  int addCalls = 0;

  /// Если задан, `add` ждёт его завершения (сохранение «в пути»).
  Completer<void>? addGate;

  /// Если задан, вызывается в `add` до записи и может бросить ошибку.
  void Function()? beforeAdd;

  /// То же для `softDelete`.
  void Function()? beforeSoftDelete;

  @override
  Future<void> add(Transaction transaction) async {
    addCalls++;
    final gate = addGate;
    if (gate != null) await gate.future;
    beforeAdd?.call();
    added.add(transaction);
  }

  @override
  Future<void> softDelete(String id) async {
    beforeSoftDelete?.call();
    deleted.add(id);
  }
}

/// Категории, которые можно слушать сколько угодно раз: экран выбора
/// открывается заново при каждом вводе, а `Stream.value` слушается один раз.
class _Categories extends FakeCategoriesRepository {
  _Categories(this.all);

  final List<Category> all;

  @override
  Stream<List<Category>> watchTopLevel(CategoryKind kind) => Stream.value([
    for (final c in all)
      if (c.kind == kind) c,
  ]);
}

final _clock = FixedClock(DateTime(2026, 9, 20, 15, 30));

final _amountText = formatMoney(Money.fromMinor(35000, 'RUB'));

Category _category(
  String id,
  String name,
  int order, {
  CategoryKind kind = CategoryKind.expense,
}) => Category.topLevel(
  id: id,
  kind: kind,
  name: name,
  iconKey: 'shopping_cart',
  sortOrder: order,
);

/// «Главная» с кнопкой и экран ввода поверх неё: как в приложении, чтобы
/// `popUntil` до корня возвращал на «Главную».
Widget _app(_RecordingTransactions transactions, {TransactionType? type}) {
  final categories = _Categories([
    _category('a', 'Продукты', 0),
    _category('b', 'Кафе', 1),
    _category('c', 'Зарплата', 0, kind: CategoryKind.income),
  ]);
  final ids = FakeIdGenerator();
  return MaterialApp(
    theme: AppTheme.light(),
    locale: MoneyApp.appLocale,
    supportedLocales: MoneyApp.supportedLocales,
    localizationsDelegates: MoneyApp.localizationsDelegates,
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => QuickAddScreen(
                  type: type ?? TransactionType.expense,
                  clock: _clock,
                  categories: categories,
                  transactions: transactions,
                  idGenerator: ids,
                ),
              ),
            ),
            child: const Text('Открыть'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _toPicker(WidgetTester tester, {String amount = '350'}) async {
  await tester.tap(find.text('Открыть'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), amount);
  await tester.tap(find.widgetWithText(FilledButton, 'Далее'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
  });

  testWidgets('успех: запись создана, возврат на «Главную», сообщение с '
      'суммой', (tester) async {
    final repo = _RecordingTransactions();
    await tester.pumpWidget(_app(repo));
    await _toPicker(tester);

    await tester.tap(find.text('Продукты'));
    await tester.pumpAndSettle();

    expect(repo.added, hasLength(1));
    final saved = repo.added.single;
    expect(saved.id, 'id-1');
    expect(saved.type, TransactionType.expense);
    expect(saved.amount, Money.fromMinor(35000, 'RUB'));
    expect(saved.categoryId, 'a');
    expect(saved.note, isNull);
    expect(saved.occurredOn, DateOnly(2026, 9, 20));
    expect(saved.occurredAt, DateTime(2026, 9, 20, 15, 30).toUtc());
    expect(find.byType(QuickAddScreen), findsNothing);
    expect(find.byType(CategoryPickerScreen), findsNothing);
    expect(find.text('Открыть'), findsOneWidget);
    expect(
      find.text('Расход $_amountText · Продукты сохранён'),
      findsOneWidget,
    );
    expect(find.text('Отменить'), findsOneWidget);
  });

  testWidgets('доход: тип в записи и слово «Доход» в сообщении', (
    tester,
  ) async {
    final repo = _RecordingTransactions();
    await tester.pumpWidget(_app(repo, type: TransactionType.income));
    await _toPicker(tester);

    await tester.tap(find.text('Зарплата'));
    await tester.pumpAndSettle();

    expect(repo.added.single.type, TransactionType.income);
    expect(find.text('Доход $_amountText · Зарплата сохранён'), findsOneWidget);
  });

  testWidgets('нулевая сумма называется в сообщении', (tester) async {
    final repo = _RecordingTransactions();
    await tester.pumpWidget(_app(repo));
    await _toPicker(tester, amount: '0');

    await tester.tap(find.text('Продукты'));
    await tester.pumpAndSettle();

    final zero = formatMoney(Money.zero('RUB'));
    expect(repo.added.single.amount, Money.zero('RUB'));
    expect(find.text('Расход $zero · Продукты сохранён'), findsOneWidget);
  });

  testWidgets('комментарий уходит в запись нормализованным', (tester) async {
    final repo = _RecordingTransactions();
    await tester.pumpWidget(_app(repo));
    await _toPicker(tester);
    await tester.enterText(
      find.descendant(
        of: find.byType(NoteField),
        matching: find.byType(TextField),
      ),
      '  молоко  ',
    );

    await tester.tap(find.text('Продукты'));
    await tester.pumpAndSettle();

    expect(repo.added.single.note, 'молоко');
  });

  testWidgets('выбранное «Вчера» даёт день и момент вчерашнего дня', (
    tester,
  ) async {
    final repo = _RecordingTransactions();
    await tester.pumpWidget(_app(repo));
    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DateChip));
    await tester.pumpAndSettle();
    await tester.tap(find.text('19'));
    await tester.tap(find.text('ОК'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '350');
    await tester.tap(find.widgetWithText(FilledButton, 'Далее'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Продукты'));
    await tester.pumpAndSettle();

    final saved = repo.added.single;
    expect(saved.occurredOn, DateOnly(2026, 9, 19));
    expect(saved.occurredAt, DateTime(2026, 9, 19, 12).toUtc());
  });

  testWidgets('два быстрых тапа по плиткам дают одну запись', (tester) async {
    final gate = Completer<void>();
    final repo = _RecordingTransactions()..addGate = gate;
    await tester.pumpWidget(_app(repo));
    await _toPicker(tester);

    final tile = find.text('Продукты');
    await tester.tap(tile);
    await tester.tap(tile);
    // Третий тап — по другой плитке, пока первое сохранение ещё идёт.
    await tester.tap(find.text('Кафе'));
    await tester.pump();
    expect(repo.addCalls, 1);

    gate.complete();
    await tester.pumpAndSettle();
    expect(repo.added, hasLength(1));
    expect(repo.added.single.categoryId, 'a');
    expect(find.byType(CategoryPickerScreen), findsNothing);
  });

  group('ошибки сохранения', () {
    Future<_RecordingTransactions> failWith(
      WidgetTester tester,
      void Function() failure,
    ) async {
      final repo = _RecordingTransactions()..beforeAdd = failure;
      await tester.pumpWidget(_app(repo));
      await tester.tap(find.text('Открыть'));
      await tester.pumpAndSettle();
      // Вчерашний день и сумма: проверим, что они переживут ошибку.
      await tester.tap(find.byType(DateChip));
      await tester.pumpAndSettle();
      await tester.tap(find.text('19'));
      await tester.tap(find.text('ОК'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '350');
      await tester.tap(find.widgetWithText(FilledButton, 'Далее'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(NoteField),
          matching: find.byType(TextField),
        ),
        'молоко',
      );
      await tester.tap(find.text('Продукты'));
      await tester.pumpAndSettle();
      return repo;
    }

    void expectNothingLost(WidgetTester tester) {
      // Экран выбора остался, введённое на месте.
      expect(find.byType(CategoryPickerScreen), findsOneWidget);
      expect(find.text('молоко'), findsOneWidget);
      expect(find.textContaining('сохранён'), findsNothing);
      expect(find.text('Отменить'), findsNothing);
    }

    testWidgets('правило репозитория: понятный текст, ничего не потеряно', (
      tester,
    ) async {
      final repo = await failWith(
        tester,
        () => throw TransactionRuleException(TransactionRule.categoryArchived),
      );

      expectNothingLost(tester);
      expect(
        find.text('Эта категория в архиве. Выберите другую'),
        findsOneWidget,
      );
      expect(repo.added, isEmpty);

      // Назад: сумма и день на месте.
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      final amount = tester.widget<TextField>(find.byType(TextField));
      expect(amount.controller!.text, '350');
      expect(
        tester.widget<DateChip>(find.byType(DateChip)).value,
        DateOnly(2026, 9, 19),
      );
    });

    testWidgets('прочее исключение: общий текст, экран остаётся', (
      tester,
    ) async {
      await failWith(tester, () => throw StateError('disk is full'));

      expectNothingLost(tester);
      expect(find.text(transactionSaveFailedText), findsOneWidget);
    });

    testWidgets('правило «не должно случаться» даёт общий текст', (
      tester,
    ) async {
      await failWith(
        tester,
        () => throw TransactionRuleException(
          TransactionRule.categoryMustBeTopLevel,
        ),
      );

      expectNothingLost(tester);
      expect(find.text(transactionSaveFailedText), findsOneWidget);
    });

    testWidgets('после ошибки блокировка снята: повторный тап сохраняет', (
      tester,
    ) async {
      final repo = await failWith(
        tester,
        () => throw StateError('disk is full'),
      );
      repo.beforeAdd = null;

      await tester.tap(find.text('Продукты'));
      await tester.pumpAndSettle();

      expect(repo.addCalls, 2);
      expect(repo.added, hasLength(1));
      expect(repo.added.single.note, 'молоко');
      expect(repo.added.single.occurredOn, DateOnly(2026, 9, 19));
      expect(find.byType(CategoryPickerScreen), findsNothing);
      expect(find.textContaining('Продукты сохранён'), findsOneWidget);
      // Текст ошибки не остался висеть рядом с сообщением об успехе.
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text(transactionSaveFailedText), findsNothing);
    });
  });

  group('сообщение и «Отменить»', () {
    testWidgets('«Отменить» мягко удаляет свою запись, подтверждения нет', (
      tester,
    ) async {
      final repo = _RecordingTransactions();
      await tester.pumpWidget(_app(repo));
      await _toPicker(tester);
      await tester.tap(find.text('Продукты'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Отменить'));
      await tester.pumpAndSettle();

      expect(repo.deleted, ['id-1']);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('сообщение исчезает само примерно через 6 секунд', (
      tester,
    ) async {
      final repo = _RecordingTransactions();
      await tester.pumpWidget(_app(repo));
      await _toPicker(tester);
      await tester.tap(find.text('Продукты'));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      expect(find.byType(SnackBar), findsOneWidget);

      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      expect(repo.deleted, isEmpty);
    });

    testWidgets('второе сохранение заменяет сообщение; каждое отменяет своё', (
      tester,
    ) async {
      final repo = _RecordingTransactions();
      await tester.pumpWidget(_app(repo));
      await _toPicker(tester, amount: '350');
      await tester.tap(find.text('Продукты'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Продукты сохранён'), findsOneWidget);

      // Новый ввод убирает прошлое сообщение: оно не закрывает «Далее».
      await tester.tap(find.text('Открыть'));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      await tester.enterText(find.byType(TextField), '100');
      await tester.tap(find.widgetWithText(FilledButton, 'Далее'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Кафе'));
      await tester.pumpAndSettle();

      expect(repo.added.map((t) => t.id), ['id-1', 'id-2']);
      // Осталось одно, новое сообщение.
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('Кафе сохранён'), findsOneWidget);
      expect(find.textContaining('Продукты сохранён'), findsNothing);

      await tester.tap(find.text('Отменить'));
      await tester.pumpAndSettle();
      expect(repo.deleted, ['id-2']);
    });

    testWidgets('сбой отмены показывает понятный текст', (tester) async {
      final repo = _RecordingTransactions()
        ..beforeSoftDelete = () => throw StateError('gone');
      await tester.pumpWidget(_app(repo));
      await _toPicker(tester);
      await tester.tap(find.text('Продукты'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Отменить'));
      await tester.pumpAndSettle();

      expect(
        find.text('Не удалось отменить. Попробуйте ещё раз'),
        findsOneWidget,
      );
    });

    testWidgets('скринридер читает сумму словами, в том числе ноль', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final repo = _RecordingTransactions();
      await tester.pumpWidget(_app(repo));
      await _toPicker(tester, amount: '0');
      await tester.tap(find.text('Продукты'));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel('Расход 0 рублей · Продукты сохранён'),
        findsOneWidget,
      );
      semantics.dispose();
    });
  });
}
