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
import 'package:money_app/features/transactions/domain/transaction_type.dart';
import 'package:money_app/features/transactions/presentation/quick_add/category_picker_screen.dart';
import 'package:money_app/features/transactions/presentation/quick_add/note_field.dart';
import 'package:money_app/features/transactions/presentation/quick_add/quick_add_screen.dart';
import 'package:money_app/features/transactions/presentation/quick_add/subcategory_picker_screen.dart';

import '../../../../support/fake_id_generator.dart';
import '../../../../support/fakes.dart';
import '../../../../support/fixed_clock.dart';

class _RecordingTransactions extends FakeTransactionsRepository {
  final added = <Transaction>[];
  final deleted = <String>[];
  int addCalls = 0;
  Completer<void>? addGate;

  @override
  Future<void> add(Transaction transaction) async {
    addCalls++;
    final gate = addGate;
    if (gate != null) await gate.future;
    added.add(transaction);
  }

  @override
  Future<void> softDelete(String id) async => deleted.add(id);
}

/// Категории и подкатегории «в памяти». Как настоящий репозиторий, отдаёт
/// подкатегории только живые и по `sortOrder`; каждый вызов даёт новый поток.
class _Categories extends FakeCategoriesRepository {
  _Categories(this.tops, this.subs);

  final List<Category> tops;
  final List<Category> subs;

  /// Номера (с единицы) вызовов `watchSubcategories`, которые должны упасть.
  final failOnCalls = <int>{};
  int subCalls = 0;

  @override
  Stream<List<Category>> watchTopLevel(CategoryKind kind) => Stream.value([
    for (final c in tops)
      if (c.kind == kind) c,
  ]);

  @override
  Stream<List<Category>> watchSubcategories(String parentId) {
    subCalls++;
    if (failOnCalls.contains(subCalls)) {
      return Stream.error(StateError('db is broken'));
    }
    final live = [
      for (final s in subs)
        if (s.parentId == parentId && !s.isArchived) s,
    ]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return Stream.value(live);
  }
}

final _clock = FixedClock(DateTime(2026, 9, 20, 15, 30));
final _amountText = formatMoney(Money.fromMinor(35000, 'RUB'));

Category _top(String id, String name, int order) => Category.topLevel(
  id: id,
  kind: CategoryKind.expense,
  name: name,
  iconKey: 'shopping_cart',
  sortOrder: order,
);

final _products = _top('a', 'Продукты', 0);
final _cafe = _top('b', 'Кафе', 1);
final _transport = _top('c', 'Транспорт', 2);

Category _sub(String id, Category parent, String name, int order) =>
    Category.subcategoryOf(
      id: id,
      parent: parent,
      name: name,
      iconKey: 'shopping_cart',
      sortOrder: order,
    );

/// Подкатегории «Продуктов» заданы не по порядку: экран обязан упорядочить.
_Categories _categories({List<Category>? extraSubs}) => _Categories(
  [_products, _cafe, _transport],
  [
    _sub('s2', _products, 'Фрукты', 1),
    _sub('s1', _products, 'Овощи', 0),
    // «Кафе»: единственная подкатегория в архиве.
    _sub('s3', _cafe, 'Кофе', 0).archived(DateTime.utc(2026, 9, 1)),
    ...?extraSubs,
  ],
);

Widget _app(
  _RecordingTransactions transactions,
  _Categories categories, {
  double textScale = 1,
}) {
  final ids = FakeIdGenerator();
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
                builder: (_) => QuickAddScreen(
                  type: TransactionType.expense,
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

Future<void> _toPicker(
  WidgetTester tester, {
  bool yesterday = false,
  String? note,
}) async {
  await tester.tap(find.text('Открыть'));
  await tester.pumpAndSettle();
  if (yesterday) {
    await tester.tap(find.byType(DateChip));
    await tester.pumpAndSettle();
    await tester.tap(find.text('19'));
    await tester.tap(find.text('ОК'));
    await tester.pumpAndSettle();
  }
  await tester.enterText(find.byType(TextField), '350');
  await tester.tap(find.widgetWithText(FilledButton, 'Далее'));
  await tester.pumpAndSettle();
  if (note != null) {
    await tester.enterText(
      find.descendant(
        of: find.byType(NoteField),
        matching: find.byType(TextField),
      ),
      note,
    );
  }
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
  });

  testWidgets('категория без подкатегорий сохраняется сразу', (tester) async {
    final repo = _RecordingTransactions();
    await tester.pumpWidget(_app(repo, _categories()));
    await _toPicker(tester);

    await tester.tap(find.text('Транспорт'));
    await tester.pumpAndSettle();

    expect(find.byType(SubcategoryPickerScreen), findsNothing);
    expect(repo.added.single.categoryId, 'c');
    expect(repo.added.single.subcategoryId, isNull);
    expect(
      find.text('Сохранено: расход $_amountText · Транспорт'),
      findsOneWidget,
    );
  });

  testWidgets('все подкатегории в архиве: сохраняется сразу', (tester) async {
    final repo = _RecordingTransactions();
    await tester.pumpWidget(_app(repo, _categories()));
    await _toPicker(tester);

    await tester.tap(find.text('Кафе'));
    await tester.pumpAndSettle();

    expect(find.byType(SubcategoryPickerScreen), findsNothing);
    expect(repo.added.single.categoryId, 'b');
    expect(repo.added.single.subcategoryId, isNull);
  });

  testWidgets(
    'с подкатегориями: «Без подкатегории» первой, дальше по порядку',
    (tester) async {
      final repo = _RecordingTransactions();
      await tester.pumpWidget(_app(repo, _categories()));
      await _toPicker(tester);

      await tester.tap(find.text('Продукты'));
      await tester.pumpAndSettle();

      expect(find.byType(SubcategoryPickerScreen), findsOneWidget);
      expect(repo.added, isEmpty);
      // Заголовок — имя категории; сумма и день видны, комментария нет.
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Продукты'),
        ),
        findsOneWidget,
      );
      expect(find.text('\u2212$_amountText'), findsOneWidget);
      expect(find.text('Сегодня'), findsOneWidget);
      expect(find.byType(NoteField), findsNothing);

      final skip = tester.getTopLeft(find.text('Без подкатегории')).dx;
      final vegetables = tester.getTopLeft(find.text('Овощи')).dx;
      final fruits = tester.getTopLeft(find.text('Фрукты')).dx;
      expect(skip, lessThan(vegetables));
      expect(vegetables, lessThan(fruits));
    },
  );

  testWidgets('«Без подкатегории» сохраняет только с категорией', (
    tester,
  ) async {
    final repo = _RecordingTransactions();
    await tester.pumpWidget(_app(repo, _categories()));
    await _toPicker(tester);
    await tester.tap(find.text('Продукты'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Без подкатегории'));
    await tester.pumpAndSettle();

    expect(repo.added.single.categoryId, 'a');
    expect(repo.added.single.subcategoryId, isNull);
    expect(find.byType(QuickAddScreen), findsNothing);
    expect(
      find.text('Сохранено: расход $_amountText · Продукты'),
      findsOneWidget,
    );
  });

  testWidgets('тап по подкатегории сохраняет с ней и называет её', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final repo = _RecordingTransactions();
    await tester.pumpWidget(_app(repo, _categories()));
    await _toPicker(tester);
    await tester.tap(find.text('Продукты'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Овощи'));
    await tester.pumpAndSettle();

    expect(repo.added.single.categoryId, 'a');
    expect(repo.added.single.subcategoryId, 's1');
    expect(find.byType(CategoryPickerScreen), findsNothing);
    expect(
      find.text('Сохранено: расход $_amountText · Продукты · Овощи'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Сохранено: расход 350 рублей · Продукты · Овощи'),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('комментарий и выбранная дата доезжают до записи', (
    tester,
  ) async {
    final repo = _RecordingTransactions();
    await tester.pumpWidget(_app(repo, _categories()));
    await _toPicker(tester, yesterday: true, note: '  молоко  ');
    await tester.tap(find.text('Продукты'));
    await tester.pumpAndSettle();
    expect(find.text('Вчера'), findsOneWidget);

    await tester.tap(find.text('Фрукты'));
    await tester.pumpAndSettle();

    final saved = repo.added.single;
    expect(saved.subcategoryId, 's2');
    expect(saved.note, 'молоко');
    expect(saved.occurredOn, DateOnly(2026, 9, 19));
  });

  testWidgets('«Без подкатегории» тоже сохраняет комментарий и дату', (
    tester,
  ) async {
    final repo = _RecordingTransactions();
    await tester.pumpWidget(_app(repo, _categories()));
    await _toPicker(tester, yesterday: true, note: 'молоко');
    await tester.tap(find.text('Продукты'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Без подкатегории'));
    await tester.pumpAndSettle();

    expect(repo.added.single.note, 'молоко');
    expect(repo.added.single.occurredOn, DateOnly(2026, 9, 19));
  });

  testWidgets('«Отменить» после сохранения с подкатегорией удаляет запись', (
    tester,
  ) async {
    final repo = _RecordingTransactions();
    await tester.pumpWidget(_app(repo, _categories()));
    await _toPicker(tester);
    await tester.tap(find.text('Продукты'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Овощи'));
    await tester.pumpAndSettle();
    expect(find.text('Отменить'), findsOneWidget);

    await tester.tap(find.text('Отменить'));
    await tester.pumpAndSettle();

    expect(repo.deleted, ['id-1']);
  });

  testWidgets('двойной тап по категории открывает один экран подкатегорий', (
    tester,
  ) async {
    final repo = _RecordingTransactions();
    await tester.pumpWidget(_app(repo, _categories()));
    await _toPicker(tester);

    final tile = find.text('Продукты');
    await tester.tap(tile);
    await tester.tap(tile, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.byType(SubcategoryPickerScreen), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    // Один «Назад» возвращает на выбор категории, а не на второй такой же экран.
    expect(find.byType(SubcategoryPickerScreen), findsNothing);
    expect(find.byType(CategoryPickerScreen), findsOneWidget);
  });

  testWidgets('двойной тап по подкатегории не создаёт две записи', (
    tester,
  ) async {
    final gate = Completer<void>();
    final repo = _RecordingTransactions()..addGate = gate;
    await tester.pumpWidget(_app(repo, _categories()));
    await _toPicker(tester);
    await tester.tap(find.text('Продукты'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Овощи'));
    await tester.tap(find.text('Овощи'));
    await tester.tap(find.text('Без подкатегории'));
    await tester.pump();
    expect(repo.addCalls, 1);

    gate.complete();
    await tester.pumpAndSettle();
    expect(repo.added, hasLength(1));
    expect(repo.added.single.subcategoryId, 's1');
  });

  testWidgets('ошибка чтения подкатегорий не сохраняет операцию', (
    tester,
  ) async {
    final repo = _RecordingTransactions();
    final categories = _categories()..failOnCalls.add(1);
    await tester.pumpWidget(_app(repo, categories));
    await _toPicker(tester, note: 'молоко');

    await tester.tap(find.text('Продукты'));
    await tester.pumpAndSettle();

    expect(repo.addCalls, 0);
    expect(find.byType(CategoryPickerScreen), findsOneWidget);
    expect(find.byType(SubcategoryPickerScreen), findsNothing);
    expect(find.text(transactionSaveFailedText), findsOneWidget);
    expect(find.text('молоко'), findsOneWidget);

    // Можно повторить: блокировка снята.
    await tester.tap(find.text('Продукты'));
    await tester.pumpAndSettle();
    expect(find.byType(SubcategoryPickerScreen), findsOneWidget);
  });

  testWidgets(
    'ошибка потока на экране подкатегорий: текст и «Без подкатегории»',
    (tester) async {
      final repo = _RecordingTransactions();
      // Первое чтение (тап по плитке) успешно, второе (экран) падает.
      final categories = _categories()..failOnCalls.add(2);
      await tester.pumpWidget(_app(repo, categories));
      await _toPicker(tester);
      await tester.tap(find.text('Продукты'));
      await tester.pumpAndSettle();

      expect(find.text('Не удалось загрузить подкатегории'), findsOneWidget);
      await tester.tap(find.text('Без подкатегории'));
      await tester.pumpAndSettle();

      expect(repo.added.single.categoryId, 'a');
      expect(repo.added.single.subcategoryId, isNull);
    },
  );

  testWidgets('«Назад» возвращает на выбор категории с комментарием', (
    tester,
  ) async {
    final repo = _RecordingTransactions();
    await tester.pumpWidget(_app(repo, _categories()));
    await _toPicker(tester, yesterday: true, note: 'молоко');
    await tester.tap(find.text('Продукты'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.byType(SubcategoryPickerScreen), findsNothing);
    expect(find.byType(CategoryPickerScreen), findsOneWidget);
    expect(find.text('молоко'), findsOneWidget);
    expect(repo.added, isEmpty);

    // Другая категория после возврата: комментарий и дата на месте.
    await tester.tap(find.text('Транспорт'));
    await tester.pumpAndSettle();
    expect(repo.added.single.note, 'молоко');
    expect(repo.added.single.occurredOn, DateOnly(2026, 9, 19));
  });

  testWidgets('масштаб шрифта 200 % без overflow', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _RecordingTransactions();
    final categories = _categories(
      extraSubs: [
        _sub('s4', _products, 'Молочные продукты и яйца', 2),
        _sub('s5', _products, 'Мясо', 3),
      ],
    );
    await tester.pumpWidget(_app(repo, categories, textScale: 2));
    await _toPicker(tester);

    await tester.tap(find.text('Продукты'));
    await tester.pumpAndSettle();

    expect(find.byType(SubcategoryPickerScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(find.text('Без подкатегории'), findsOneWidget);
  });
}
