import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/ui/category_icons.dart';
import 'package:money_app/core/ui/category_rule_text.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/categories/domain/categories_repository.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/categories/domain/category_rules.dart';
import 'package:money_app/features/categories/presentation/categories_screen.dart';

import '../../../support/fakes.dart';

Category _c(
  String id,
  String name,
  int order, {
  CategoryKind kind = CategoryKind.expense,
  String iconKey = 'shopping_cart',
  bool archived = false,
}) {
  final category = Category.topLevel(
    id: id,
    kind: kind,
    name: name,
    iconKey: iconKey,
    sortOrder: order,
  );
  return archived ? category.archived(DateTime.utc(2026, 9, 1)) : category;
}

List<Category> _fixture() => [
  _c('food', 'Продукты', 0),
  _c('cafe', 'Кафе', 1, iconKey: 'restaurant'),
  _c('transport', 'Транспорт', 2),
  _c('clothes', 'Одежда', 3, archived: true),
  _c('salary', 'Зарплата', 0, kind: CategoryKind.income, iconKey: 'payments'),
  _c('gift', 'Подарки', 1, kind: CategoryKind.income),
  // Подкатегория в этом шаге не показывается.
  Category.subcategoryOf(
    id: 'milk',
    parent: _c('food', 'Продукты', 0),
    name: 'Молоко',
    iconKey: 'shopping_cart',
    sortOrder: 0,
  ),
];

Future<InMemoryCategoriesRepository> _pump(
  WidgetTester tester,
  List<Category> categories, {
  double textScale = 1,
}) async {
  final repository = InMemoryCategoriesRepository(categories);
  addTearDown(repository.dispose);
  await _pumpWith(tester, repository, textScale: textScale);
  return repository;
}

Future<void> _pumpWith(
  WidgetTester tester,
  CategoriesRepository repository, {
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: CategoriesScreen(categories: repository),
    ),
  );
  await tester.pumpAndSettle();
}

/// Кнопка в строке категории с id [id].
Finder _button(String id) => find.descendant(
  of: find.byKey(ValueKey<String>(id)),
  matching: find.byType(TextButton),
);

Future<void> _openArchive(WidgetTester tester) async {
  await tester.tap(find.textContaining('Архив ('));
  await tester.pumpAndSettle();
}

class _BrokenRepository extends FakeCategoriesRepository {
  @override
  Stream<List<Category>> watchAll() => Stream.error(Exception('boom'));
}

void main() {
  testWidgets('расходы первой: живые категории по порядку, подкатегорий нет', (
    tester,
  ) async {
    await _pump(tester, _fixture());

    expect(find.text(categoriesScreenTitle), findsOneWidget);
    final tabs = find.byType(Tab);
    expect(
      tester.getTopLeft(find.widgetWithText(Tab, categoriesExpenseTab)).dx,
      lessThan(
        tester.getTopLeft(find.widgetWithText(Tab, categoriesIncomeTab)).dx,
      ),
    );
    expect(tabs, findsNWidgets(2));

    double top(String name) => tester.getTopLeft(find.text(name)).dy;
    expect(top('Продукты'), lessThan(top('Кафе')));
    expect(top('Кафе'), lessThan(top('Транспорт')));
    expect(find.text('Зарплата'), findsNothing);
    expect(find.text('Молоко'), findsNothing);
    // Архивная свёрнута: имени не видно, счётчик виден.
    expect(find.text('Одежда'), findsNothing);
    expect(find.text(categoriesArchiveTitle(1)), findsOneWidget);
    // Иконка берётся по ключу категории.
    expect(find.byIcon(categoryIconFor('restaurant')), findsOneWidget);

    await tester.tap(find.text(categoriesIncomeTab));
    await tester.pumpAndSettle();
    double topIncome(String name) => tester.getTopLeft(find.text(name)).dy;
    expect(topIncome('Зарплата'), lessThan(topIncome('Подарки')));
    expect(find.text('Продукты'), findsNothing);
    expect(find.byIcon(categoryIconFor('payments')), findsOneWidget);
    // В доходах архивных нет: раздела нет.
    expect(find.textContaining('Архив'), findsNothing);
  });

  testWidgets('«В архив» убирает из списка и переносит в «Архив (N)»', (
    tester,
  ) async {
    await _pump(tester, _fixture());

    await tester.tap(_button('cafe'));
    await tester.pumpAndSettle();

    // Диалога нет, из списка ушла, остальные на месте.
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Кафе'), findsNothing);
    expect(find.text('Продукты'), findsOneWidget);
    expect(find.text(categoriesArchiveTitle(2)), findsOneWidget);

    await _openArchive(tester);
    expect(find.text('Кафе'), findsOneWidget);
    expect(find.text('Одежда'), findsOneWidget);
    expect(find.text(categoriesRestoreAction), findsNWidgets(2));
  });

  testWidgets('«Вернуть из архива» возвращает категорию в список', (
    tester,
  ) async {
    await _pump(tester, _fixture());

    await _openArchive(tester);
    await tester.tap(_button('clothes'));
    await tester.pumpAndSettle();

    expect(find.text('Одежда'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    // Архив опустел: раздела нет.
    expect(find.textContaining('Архив'), findsNothing);
    // Вернулась в конец своего вида, кнопка у неё снова «В архив».
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('clothes')),
        matching: find.text(categoriesArchiveAction),
      ),
      findsOneWidget,
    );
  });

  testWidgets('дубль имени при возврате: сообщение, категория остаётся в '
      'архиве', (tester) async {
    await _pump(tester, [
      _c('cafe', 'Кафе', 0),
      _c('cafe-old', 'кафе', 1, archived: true),
    ]);

    await _openArchive(tester);
    await tester.tap(_button('cafe-old'));
    await tester.pumpAndSettle();

    expect(
      find.text(categoryRuleMessage(CategoryRule.duplicateName)),
      findsOneWidget,
    );
    expect(find.text(categoriesArchiveTitle(1)), findsOneWidget);
    expect(find.text('кафе'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('сбой записи: общее сообщение, приложение не падает', (
    tester,
  ) async {
    final repository = await _pump(tester, _fixture());
    repository.failWith = Exception('disk');

    await tester.tap(_button('food'));
    await tester.pumpAndSettle();

    expect(find.text(categorySaveFailedText), findsOneWidget);
    expect(find.text('Продукты'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Кнопка снова работает: запись не «залипла».
    repository.failWith = null;
    await tester.tap(_button('food'));
    await tester.pumpAndSettle();
    expect(find.text('Продукты'), findsNothing);
  });

  testWidgets('в виде нет живых категорий: подсказка', (tester) async {
    await _pump(tester, [
      _c('salary', 'Зарплата', 0, kind: CategoryKind.income),
    ]);

    expect(find.text(categoriesEmptyText), findsOneWidget);
  });

  testWidgets('база не отдала список: сообщение об ошибке', (tester) async {
    await _pumpWith(tester, _BrokenRepository());

    expect(find.text(categoriesLoadErrorText), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('масштаб шрифта 200 %: без переполнения, кнопки достижимы', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pump(tester, [
      _c('long', 'Очень длинное название категории', 0),
      _c(
        'archived',
        'Архивная категория с длинным названием',
        1,
        archived: true,
      ),
    ], textScale: 2);

    await _openArchive(tester);
    expect(find.text(categoriesRestoreAction), findsOneWidget);
    expect(find.text(categoriesArchiveAction), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('кнопки: подпись с именем для скринридера, зона от 48 dp', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, _fixture());

    expect(
      find.bySemanticsLabel(categoriesArchiveLabel('Кафе')),
      findsOneWidget,
    );
    for (final id in ['food', 'cafe', 'transport']) {
      final size = tester.getSize(_button(id));
      expect(size.height, greaterThanOrEqualTo(48), reason: id);
      expect(size.width, greaterThanOrEqualTo(48), reason: id);
    }

    await _openArchive(tester);
    expect(
      find.bySemanticsLabel(categoriesRestoreLabel('Одежда')),
      findsOneWidget,
    );
    final size = tester.getSize(_button('clothes'));
    expect(size.height, greaterThanOrEqualTo(48));
    expect(size.width, greaterThanOrEqualTo(48));
    // Действие нажатия доступно скринридеру.
    expect(
      tester.getSemantics(_button('clothes')),
      isSemantics(
        label: categoriesRestoreLabel('Одежда'),
        isButton: true,
        hasTapAction: true,
      ),
    );
    handle.dispose();
  });
}
