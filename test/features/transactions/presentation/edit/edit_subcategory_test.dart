import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/app/app.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/amount_field.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';
import 'package:money_app/features/transactions/presentation/edit/edit_transaction_screen.dart';

import '../../../../support/fakes.dart';
import '../../../../support/fixed_clock.dart';

/// Репозиторий операций: помнит сохранённое.
class _Transactions extends FakeTransactionsRepository {
  _Transactions(this.original);

  final Transaction original;
  final updated = <Transaction>[];

  @override
  Future<Transaction?> findById(String id) async => original;

  @override
  Future<void> update(Transaction transaction) async =>
      updated.add(transaction);
}

class _Categories extends FakeCategoriesRepository {
  _Categories(this.all);

  final List<Category> all;

  /// Если `true`, чтение подкатегорий падает.
  bool subsFail = false;

  @override
  Future<Category?> findById(String id) async {
    for (final c in all) {
      if (c.id == id) return c;
    }
    return null;
  }

  @override
  Stream<List<Category>> watchTopLevel(CategoryKind kind) => Stream.value([
    for (final c in all)
      if (c.kind == kind && c.isTopLevel && !c.isArchived) c,
  ]);

  /// Как настоящий репозиторий, отдаёт только живых, но архивная в списке
  /// `all` есть: экран не должен полагаться на это (и не показывает её сам).
  @override
  Stream<List<Category>> watchSubcategories(String parentId) {
    if (subsFail) return Stream.error(StateError('db'));
    return Stream.value([
      for (final c in all)
        if (c.parentId == parentId) c,
    ]);
  }
}

final _clock = FixedClock(DateTime(2026, 9, 20, 15, 30));

Category _top(String id, String name, {CategoryKind? kind}) =>
    Category.topLevel(
      id: id,
      kind: kind ?? CategoryKind.expense,
      name: name,
      iconKey: 'shopping_cart',
      sortOrder: 0,
    );

final _food = _top('food', 'Продукты');
final _cafe = _top('cafe', 'Кафе');
final _clothes = _top('clothes', 'Одежда');
final _salary = _top('salary', 'Зарплата', kind: CategoryKind.income);

Category _sub(
  String id,
  String name,
  Category parent, {
  bool archived = false,
}) => Category(
  id: id,
  kind: parent.kind,
  name: name,
  iconKey: 'shopping_cart',
  parentId: parent.id,
  sortOrder: 0,
  archivedAt: archived ? DateTime.utc(2026, 1, 1) : null,
);

_Categories _catalog() => _Categories([
  _food,
  _cafe,
  _clothes,
  _salary,
  _sub('veg', 'Овощи', _food),
  _sub('fruit', 'Фрукты', _food),
  _sub('old', 'Старая', _food, archived: true),
  _sub('shoes', 'Обувь', _clothes),
]);

Transaction _tx({
  String categoryId = 'food',
  String? subcategoryId,
  TransactionType type = TransactionType.expense,
}) => Transaction(
  id: 'tx',
  type: type,
  amount: Money.fromMinor(35000, 'RUB'),
  occurredOn: DateOnly(2026, 9, 18),
  occurredAt: DateTime.utc(2026, 9, 18, 7, 45),
  categoryId: categoryId,
  subcategoryId: subcategoryId,
  note: 'молоко',
);

Widget _app(
  _Transactions transactions,
  _Categories categories, {
  double textScale = 1,
}) {
  return MaterialApp(
    theme: AppTheme.light(),
    locale: MoneyApp.appLocale,
    supportedLocales: MoneyApp.supportedLocales,
    localizationsDelegates: MoneyApp.localizationsDelegates,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => EditTransactionScreen(
                  transaction: transactions.original,
                  clock: _clock,
                  categories: categories,
                  transactions: transactions,
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

Future<_Transactions> _open(
  WidgetTester tester,
  Transaction tx, {
  _Categories? categories,
  double textScale = 1,
}) async {
  final repo = _Transactions(tx);
  await tester.pumpWidget(
    _app(repo, categories ?? _catalog(), textScale: textScale),
  );
  await tester.tap(find.text('Открыть'));
  await tester.pumpAndSettle();
  return repo;
}

Finder get _saveButton => find.widgetWithText(FilledButton, 'Сохранить');

/// Строка «Подкатегория» (её подпись; у строки категории подпись «Категория»).
Finder get _subRow => find.text('Подкатегория');

Future<void> _pickCategory(WidgetTester tester, String name) async {
  await tester.tap(find.text('Категория'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(name));
  await tester.pumpAndSettle();
}

Future<void> _pickSub(WidgetTester tester, String name) async {
  await tester.tap(_subRow);
  await tester.pumpAndSettle();
  await tester.tap(find.text(name));
  await tester.pumpAndSettle();
}

Future<void> _switchTo(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(
      of: find.byType(SegmentedButton<TransactionType>),
      matching: find.text(label),
    ),
  );
  await tester.pumpAndSettle();
}

Future<Transaction> _saveAndGet(WidgetTester tester, _Transactions repo) async {
  await tester.tap(_saveButton);
  await tester.pumpAndSettle();
  expect(repo.updated, hasLength(1));
  return repo.updated.single;
}

/// Перехватывает объявления скринридеру.
List<String> _listenAnnouncements(WidgetTester tester) {
  final announcements = <String>[];
  tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(
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
    () => tester.binding.defaultBinaryMessenger
        .setMockDecodedMessageHandler<dynamic>(
          SystemChannels.accessibility,
          null,
        ),
  );
  return announcements;
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
  });

  group('строка «Подкатегория»', () {
    testWidgets('есть у категории с живыми подкатегориями: «Не выбрана»', (
      tester,
    ) async {
      await _open(tester, _tx());
      expect(_subRow, findsOneWidget);
      expect(find.text('Не выбрана'), findsOneWidget);
    });

    testWidgets('показывает выбранную подкатегорию операции', (tester) async {
      await _open(tester, _tx(subcategoryId: 'veg'));
      expect(find.text('Овощи'), findsOneWidget);
      expect(find.text('Не выбрана'), findsNothing);
    });

    testWidgets('нет у категории без подкатегорий', (tester) async {
      await _open(tester, _tx(categoryId: 'cafe'));
      expect(_subRow, findsNothing);
    });

    testWidgets('нет, если все подкатегории в архиве и своей нет', (
      tester,
    ) async {
      final categories = _Categories([
        _food,
        _sub('old', 'Старая', _food, archived: true),
      ]);
      await _open(tester, _tx(), categories: categories);
      expect(_subRow, findsNothing);
    });

    testWidgets('архивная подкатегория операции показана', (tester) async {
      await _open(tester, _tx(subcategoryId: 'old'));
      expect(_subRow, findsOneWidget);
      expect(find.text('Старая'), findsOneWidget);
    });

    testWidgets('скринридер: «Подкатегория: Овощи» и «...: не выбрана»', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _open(tester, _tx(subcategoryId: 'veg'));
      expect(find.bySemanticsLabel('Подкатегория: Овощи'), findsOneWidget);
      final node = tester.getSemantics(
        find.bySemanticsLabel('Подкатегория: Овощи'),
      );
      expect(node.flagsCollection.isButton, isTrue);
      await _pickSub(tester, 'Без подкатегории');
      expect(find.bySemanticsLabel('Подкатегория: не выбрана'), findsOneWidget);
      semantics.dispose();
    });
  });

  group('выбор и снятие', () {
    testWidgets('выбор: сетка с «Без подкатегории», без архивных; в базу '
        'уходит subcategoryId только после «Сохранить»', (tester) async {
      final repo = await _open(tester, _tx());

      await tester.tap(_subRow);
      await tester.pumpAndSettle();
      expect(find.text('Без подкатегории'), findsOneWidget);
      expect(find.text('Овощи'), findsOneWidget);
      expect(find.text('Фрукты'), findsOneWidget);
      expect(find.text('Старая'), findsNothing);

      await tester.tap(find.text('Фрукты'));
      await tester.pumpAndSettle();
      // Вернулись на правку, ничего не сохранено.
      expect(find.byType(EditTransactionScreen), findsOneWidget);
      expect(find.text('Фрукты'), findsOneWidget);
      expect(repo.updated, isEmpty);

      final saved = await _saveAndGet(tester, repo);
      expect(saved.categoryId, 'food');
      expect(saved.subcategoryId, 'fruit');
      expect(saved.note, 'молоко');
    });

    testWidgets('снятие: «Без подкатегории» сохраняется как null', (
      tester,
    ) async {
      final repo = await _open(tester, _tx(subcategoryId: 'veg'));
      await _pickSub(tester, 'Без подкатегории');
      expect(find.text('Не выбрана'), findsOneWidget);

      final saved = await _saveAndGet(tester, repo);
      expect(saved.subcategoryId, isNull);
      expect(saved.categoryId, 'food');
    });

    testWidgets('архивную можно снять: сетка только с «Без подкатегории»', (
      tester,
    ) async {
      final categories = _Categories([
        _food,
        _sub('old', 'Старая', _food, archived: true),
      ]);
      final repo = await _open(
        tester,
        _tx(subcategoryId: 'old'),
        categories: categories,
      );
      await tester.tap(_subRow);
      await tester.pumpAndSettle();
      expect(find.text('Без подкатегории'), findsOneWidget);
      expect(find.text('Старая'), findsNothing);
      await tester.tap(find.text('Без подкатегории'));
      await tester.pumpAndSettle();

      final saved = await _saveAndGet(tester, repo);
      expect(saved.subcategoryId, isNull);
    });

    testWidgets('архивная подкатегория без изменения сохраняется как есть', (
      tester,
    ) async {
      final repo = await _open(tester, _tx(subcategoryId: 'old'));
      await tester.enterText(
        find.descendant(
          of: find.byType(AmountField),
          matching: find.byType(TextField),
        ),
        '400',
      );
      final saved = await _saveAndGet(tester, repo);
      expect(saved.subcategoryId, 'old');
      expect(saved.amount, Money.fromMinor(40000, 'RUB'));
    });
  });

  group('сброс', () {
    testWidgets('смена категории сбрасывает подкатегорию и объявляет это', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final announcements = _listenAnnouncements(tester);
      final repo = await _open(tester, _tx(subcategoryId: 'veg'));

      await _pickCategory(tester, 'Одежда');

      // У «Одежды» подкатегории есть, но не выбрана.
      expect(find.text('Овощи'), findsNothing);
      expect(find.text('Не выбрана'), findsOneWidget);
      expect(announcements, ['Подкатегория сброшена']);

      final saved = await _saveAndGet(tester, repo);
      expect(saved.categoryId, 'clothes');
      expect(saved.subcategoryId, isNull);
      semantics.dispose();
    });

    testWidgets('категория без подкатегорий: строка пропадает', (tester) async {
      final repo = await _open(tester, _tx(subcategoryId: 'veg'));
      await _pickCategory(tester, 'Кафе');
      expect(_subRow, findsNothing);

      final saved = await _saveAndGet(tester, repo);
      expect(saved.categoryId, 'cafe');
      expect(saved.subcategoryId, isNull);
    });

    testWidgets('другая категория и возврат к исходной: подкатегория не '
        'возвращается', (tester) async {
      final repo = await _open(tester, _tx(subcategoryId: 'veg'));
      await _pickCategory(tester, 'Одежда');
      await _pickCategory(tester, 'Продукты');
      expect(find.text('Овощи'), findsNothing);
      expect(find.text('Не выбрана'), findsOneWidget);

      final saved = await _saveAndGet(tester, repo);
      expect(saved.categoryId, 'food');
      expect(saved.subcategoryId, isNull);
    });

    testWidgets('та же категория подкатегорию не сбрасывает', (tester) async {
      final semantics = tester.ensureSemantics();
      final announcements = _listenAnnouncements(tester);
      final repo = await _open(tester, _tx(subcategoryId: 'veg'));

      await _pickCategory(tester, 'Продукты');
      expect(find.text('Овощи'), findsOneWidget);
      expect(announcements, isEmpty);

      final saved = await _saveAndGet(tester, repo);
      expect(saved.subcategoryId, 'veg');
      semantics.dispose();
    });

    testWidgets('выбранная заново подкатегория переживает повторный выбор '
        'той же категории', (tester) async {
      final repo = await _open(tester, _tx());
      await _pickSub(tester, 'Фрукты');
      await _pickCategory(tester, 'Продукты');
      expect(find.text('Фрукты'), findsOneWidget);

      final saved = await _saveAndGet(tester, repo);
      expect(saved.subcategoryId, 'fruit');
    });

    testWidgets('смена типа сбрасывает и категорию, и подкатегорию', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final announcements = _listenAnnouncements(tester);
      final repo = await _open(tester, _tx(subcategoryId: 'veg'));

      await _switchTo(tester, 'Доход');
      expect(_subRow, findsNothing);
      expect(find.text('Овощи'), findsNothing);
      expect(announcements, ['Подкатегория сброшена']);

      await _pickCategory(tester, 'Зарплата');
      expect(_subRow, findsNothing);
      final saved = await _saveAndGet(tester, repo);
      expect(saved.type, TransactionType.income);
      expect(saved.categoryId, 'salary');
      expect(saved.subcategoryId, isNull);
      semantics.dispose();
    });

    testWidgets('возврат исходного типа возвращает и подкатегорию', (
      tester,
    ) async {
      final repo = await _open(tester, _tx(subcategoryId: 'veg'));
      await _switchTo(tester, 'Доход');
      await _switchTo(tester, 'Расход');
      expect(find.text('Овощи'), findsOneWidget);

      final saved = await _saveAndGet(tester, repo);
      expect(saved.type, TransactionType.expense);
      expect(saved.subcategoryId, 'veg');
    });
  });

  group('ошибки и «Назад»', () {
    testWidgets('ошибка чтения: сообщение, сетка не открывается, правка цела', (
      tester,
    ) async {
      final categories = _catalog();
      final repo = await _open(
        tester,
        _tx(subcategoryId: 'veg'),
        categories: categories,
      );
      categories.subsFail = true;

      await tester.tap(_subRow);
      await tester.pumpAndSettle();

      expect(find.text('Не удалось загрузить подкатегории'), findsOneWidget);
      expect(find.text('Без подкатегории'), findsNothing);
      expect(find.byType(EditTransactionScreen), findsOneWidget);
      expect(find.text('Овощи'), findsOneWidget);

      // Состояние цело: сохранение проходит с прежней подкатегорией.
      final saved = await _saveAndGet(tester, repo);
      expect(saved.subcategoryId, 'veg');
    });

    testWidgets('«Назад» с сетки подкатегорий ничего не меняет', (
      tester,
    ) async {
      final repo = await _open(tester, _tx(subcategoryId: 'veg'));
      await tester.tap(_subRow);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.byType(EditTransactionScreen), findsOneWidget);
      expect(find.text('Овощи'), findsOneWidget);
      expect(repo.updated, isEmpty);
    });

    testWidgets('«Назад» с правки после выбора: в базу ничего не уходит', (
      tester,
    ) async {
      final repo = await _open(tester, _tx());
      await _pickSub(tester, 'Фрукты');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.byType(EditTransactionScreen), findsNothing);
      expect(repo.updated, isEmpty);
    });

    testWidgets('масштаб 200 %: строка и сетка без overflow', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repo = await _open(tester, _tx(subcategoryId: 'veg'), textScale: 2);
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(_subRow);
      await tester.pumpAndSettle();
      await tester.tap(_subRow);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Без подкатегории'), findsOneWidget);
      await tester.tap(find.text('Фрукты'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final saved = await _saveAndGet(tester, repo);
      expect(saved.subcategoryId, 'fruit');
    });
  });
}
