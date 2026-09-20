import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/app/app.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/category_icons.dart';
import 'package:money_app/core/ui/theme/app_colors.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';
import 'package:money_app/features/transactions/presentation/quick_add/category_picker_screen.dart';

import '../../../../support/fakes.dart';

/// Сумма в тестах, как её показывает formatMoney (без невидимых символов в коде).
final _formatted = formatMoney(Money.fromMinor(123450, 'RUB'));

Category _category(
  String id,
  String name, {
  int order = 0,
  CategoryKind kind = CategoryKind.expense,
  String iconKey = 'shopping_cart',
}) => Category.topLevel(
  id: id,
  kind: kind,
  name: name,
  iconKey: iconKey,
  sortOrder: order,
);

/// Тест управляет потоком сам: до первого `add` ответа «из базы» нет.
class _Harness {
  _Harness() {
    // Без await: close() у потока без слушателя не завершается.
    addTearDown(() {
      unawaited(source.close());
    });
    repository = StreamCategoriesRepository(source.stream);
  }

  // Закрывается в addTearDown в конструкторе.
  // ignore: close_sinks
  final source = StreamController<List<Category>>();
  late final StreamCategoriesRepository repository;
  final selected = <Category>[];

  Widget app({
    TransactionType type = TransactionType.expense,
    double textScale = 1,
  }) {
    return MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      locale: MoneyApp.appLocale,
      supportedLocales: MoneyApp.supportedLocales,
      localizationsDelegates: MoneyApp.localizationsDelegates,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: CategoryPickerScreen(
        type: type,
        amount: Money.fromMinor(123450, 'RUB'),
        day: DateOnly(2026, 9, 20),
        categories: repository,
        onCategorySelected: selected.add,
      ),
    );
  }
}

void main() {
  Future<_Harness> pump(
    WidgetTester tester, {
    TransactionType type = TransactionType.expense,
    double textScale = 1,
  }) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final harness = _Harness();
    await tester.pumpWidget(harness.app(type: type, textScale: textScale));
    return harness;
  }

  testWidgets(
    'до первого значения потока нет ни плиток, ни пустого состояния',
    (tester) async {
      await pump(tester);
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(InkWell), findsNothing);
      expect(find.text(CategoryPickerScreen.emptyText), findsNothing);
      expect(find.text(CategoryPickerScreen.createLabel), findsNothing);
      // Сумма при этом уже видна.
      expect(find.textContaining(_formatted), findsOneWidget);
    },
  );

  testWidgets('плитки идут в порядке репозитория, архивные не показаны', (
    tester,
  ) async {
    final harness = await pump(tester);
    harness.source.add([
      _category('a', 'Продукты', order: 0),
      _category('b', 'Кафе', order: 1).archived(DateTime.utc(2026, 9, 1)),
      _category('c', 'Транспорт', order: 2),
      _category('d', 'Зарплата', order: 3, kind: CategoryKind.income),
      _category('e', 'Дом', order: 4),
    ]);
    await tester.pump();

    expect(find.text('Кафе'), findsNothing);
    expect(find.text('Зарплата'), findsNothing);
    final names = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byType(InkWell),
            matching: find.byType(Text),
          ),
        )
        .map((t) => t.data)
        .toList();
    expect(names, ['Продукты', 'Транспорт', 'Дом']);
  });

  testWidgets('заголовок и знак суммы зависят от типа', (tester) async {
    await pump(tester);
    expect(find.text('Категория расхода'), findsOneWidget);
    expect(
      find.text('${String.fromCharCode(0x2212)}$_formatted'),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox());
    await pump(tester, type: TransactionType.income);
    expect(find.text('Категория дохода'), findsOneWidget);
    expect(find.text('+$_formatted'), findsOneWidget);
  });

  testWidgets('для дохода показываются только доходные категории', (
    tester,
  ) async {
    final harness = await pump(tester, type: TransactionType.income);
    harness.source.add([
      _category('a', 'Продукты'),
      _category('d', 'Зарплата', kind: CategoryKind.income),
    ]);
    await tester.pump();

    expect(find.text('Зарплата'), findsOneWidget);
    expect(find.text('Продукты'), findsNothing);
  });

  testWidgets('пустое состояние: текст и кнопка «Создать категорию»', (
    tester,
  ) async {
    final harness = await pump(tester);
    harness.source.add(const []);
    await tester.pump();

    expect(find.text(CategoryPickerScreen.emptyText), findsOneWidget);
    final button = find.widgetWithText(
      FilledButton,
      CategoryPickerScreen.createLabel,
    );
    expect(button, findsOneWidget);

    await tester.tap(button);
    await tester.pump();
    expect(find.text(CategoryPickerScreen.createSoonMessage), findsOneWidget);
  });

  testWidgets('только архивные категории — тоже пустое состояние', (
    tester,
  ) async {
    final harness = await pump(tester);
    harness.source.add([
      _category('a', 'Кафе').archived(DateTime.utc(2026, 9, 1)),
    ]);
    await tester.pump();

    expect(find.text(CategoryPickerScreen.emptyText), findsOneWidget);
  });

  testWidgets('ошибка потока показывается текстом', (tester) async {
    final harness = await pump(tester);
    harness.source.addError(StateError('boom'));
    await tester.pump();

    expect(find.text(CategoryPickerScreen.loadErrorText), findsOneWidget);
    expect(find.textContaining('boom'), findsNothing);
  });

  testWidgets('тап по плитке вызывает onCategorySelected с нужной категорией', (
    tester,
  ) async {
    final harness = await pump(tester);
    final cafe = _category('b', 'Кафе', order: 1, iconKey: 'restaurant');
    harness.source.add([_category('a', 'Продукты'), cafe]);
    await tester.pump();

    await tester.tap(find.text('Кафе'));
    await tester.pump();

    expect(harness.selected, [cafe]);
  });

  testWidgets('иконка берётся из таблицы ключей и исключена из семантики', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final harness = await pump(tester);
    harness.source.add([
      _category('a', 'Кафе', iconKey: 'restaurant'),
      _category('b', 'Странная', order: 1, iconKey: 'no_such_icon'),
    ]);
    await tester.pump();

    expect(find.byIcon(categoryIconFor('restaurant')), findsOneWidget);
    expect(find.byIcon(fallbackCategoryIcon), findsOneWidget);
    for (final icon in tester.widgetList<Icon>(
      find.descendant(of: find.byType(InkWell), matching: find.byType(Icon)),
    )) {
      final iconFinder = find.byWidget(icon);
      expect(
        find.ancestor(of: iconFinder, matching: find.byType(ExcludeSemantics)),
        findsWidgets,
      );
    }
    // Скринридер читает только название и знает, что это кнопка.
    expect(
      tester.getSemantics(find.bySemanticsLabel('Кафе')),
      matchesSemantics(label: 'Кафе', isButton: true, hasTapAction: true),
    );
    expect(find.bySemanticsLabel(RegExp('restaurant|Иконка')), findsNothing);
    semantics.dispose();
  });

  testWidgets('зона нажатия плитки не меньше 48 dp', (tester) async {
    final harness = await pump(tester);
    harness.source.add([_category('a', 'Кафе')]);
    await tester.pump();

    final size = tester.getSize(find.byType(InkWell));
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
  });

  group('крупный шрифт', () {
    testWidgets('масштаб 200 % и «Развлечения» не дают overflow', (
      tester,
    ) async {
      final harness = await pump(tester, textScale: 2);
      harness.source.add([
        _category('a', 'Развлечения', order: 0),
        _category('b', 'Продукты', order: 1),
        _category('c', 'Транспорт', order: 2),
        _category('d', 'Подработка длинное название категории', order: 3),
        _category('e', 'Кафе', order: 4),
        _category('f', 'Здоровье', order: 5),
      ]);
      await tester.pump();

      expect(tester.takeException(), isNull);
      final text = tester.widget<Text>(find.text('Развлечения'));
      expect(text.maxLines, 2);
    });

    testWidgets('высота плитки растёт вместе с масштабом шрифта', (
      tester,
    ) async {
      final normal = await pump(tester);
      normal.source.add([_category('a', 'Кафе')]);
      await tester.pump();
      final normalHeight = tester.getSize(find.byType(InkWell)).height;

      final big = await pump(tester, textScale: 2);
      big.source.add([_category('a', 'Кафе')]);
      await tester.pump();
      final bigHeight = tester.getSize(find.byType(InkWell)).height;

      expect(bigHeight, greaterThan(normalHeight));
    });
  });

  testWidgets('сумма окрашена цветом типа операции', (tester) async {
    await pump(tester);
    final colors = tester.element(find.byType(CategoryPickerScreen)).appColors;
    final amount = tester.widget<Text>(
      find.text('${String.fromCharCode(0x2212)}$_formatted'),
    );
    expect(amount.style?.color, colors.expense);
  });
}
