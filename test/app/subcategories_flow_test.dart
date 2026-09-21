import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/app/app.dart';
import 'package:money_app/app/app_routes.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/categories/presentation/categories_screen.dart';
import 'package:money_app/features/categories/presentation/category_form_screen.dart';
import 'package:money_app/features/categories/presentation/subcategories_screen.dart';

import '../support/fake_id_generator.dart';
import '../support/fakes.dart';

/// Путь «Категории» -> «Подкатегории» -> форма по настоящим маршрутам
/// приложения, на репозитории в памяти.
Category _top(
  String id,
  String name,
  int order, {
  String iconKey = 'shopping_cart',
}) => Category.topLevel(
  id: id,
  kind: CategoryKind.expense,
  name: name,
  iconKey: iconKey,
  sortOrder: order,
);

Future<InMemoryCategoriesRepository> _pumpCategories(
  WidgetTester tester,
  List<Category> initial,
) async {
  final repository = InMemoryCategoriesRepository(initial);
  addTearDown(repository.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      locale: MoneyApp.appLocale,
      supportedLocales: MoneyApp.supportedLocales,
      localizationsDelegates: MoneyApp.localizationsDelegates,
      onGenerateRoute: onGenerateAppRoute,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => unawaited(
              Navigator.of(context).pushNamed<void>(
                AppRoutes.categories,
                arguments: CategoriesRouteArguments(
                  categories: repository,
                  idGenerator: FakeIdGenerator(),
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return repository;
}

Future<void> _openSubcategories(WidgetTester tester, String name) async {
  await tester.tap(find.byTooltip(categoriesSubcategoriesLabel(name)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('создание, переименование и счётчик: подкатегории доходят до '
      'репозитория с видом и иконкой родителя и порядком в конец', (
    tester,
  ) async {
    final repository = await _pumpCategories(tester, [
      _top('food', 'Продукты', 0, iconKey: 'restaurant'),
      _top('cafe', 'Кафе', 1),
    ]);
    expect(find.textContaining('Подкатегорий:'), findsNothing);

    await _openSubcategories(tester, 'Продукты');
    expect(find.byType(SubcategoriesScreen), findsOneWidget);
    expect(find.text(subcategoriesEmptyText), findsOneWidget);

    // Первая подкатегория.
    await tester.tap(find.text(subcategoriesAddAction));
    await tester.pumpAndSettle();
    expect(find.text(subcategoryFormCreateTitle), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Молоко');
    await tester.tap(find.text(categoryFormSaveLabel));
    await tester.pumpAndSettle();
    // Вторая.
    await tester.tap(find.text(subcategoriesAddAction));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Хлеб');
    await tester.tap(find.text(categoryFormSaveLabel));
    await tester.pumpAndSettle();

    expect(find.byType(SubcategoriesScreen), findsOneWidget);
    expect(find.text('Молоко'), findsOneWidget);
    expect(find.text('Хлеб'), findsOneWidget);
    final created = repository.all.where((c) => c.parentId == 'food').toList();
    expect(created.map((c) => c.name), ['Молоко', 'Хлеб']);
    expect(created.map((c) => c.sortOrder), [0, 1]);
    expect(created.every((c) => c.kind == CategoryKind.expense), isTrue);
    expect(created.every((c) => c.iconKey == 'restaurant'), isTrue);

    // Переименование.
    await tester.tap(find.byTooltip(categoriesRenameLabel('Хлеб')));
    await tester.pumpAndSettle();
    expect(find.text(subcategoryFormRenameTitle), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Батон');
    await tester.tap(find.text(categoryFormSaveLabel));
    await tester.pumpAndSettle();
    expect(find.text('Батон'), findsOneWidget);
    expect(find.text('Хлеб'), findsNothing);

    // Назад на «Категории»: у «Продуктов» счётчик, у «Кафе» нет.
    Navigator.of(tester.element(find.byType(SubcategoriesScreen))).pop();
    await tester.pumpAndSettle();
    expect(find.byType(CategoriesScreen), findsOneWidget);
    expect(find.text(categoriesSubcategoryCount(2)), findsOneWidget);
    expect(find.textContaining('Подкатегорий:'), findsOneWidget);
  });

  testWidgets('дубль имени в форме подкатегории: текст под полем, форма '
      'остаётся открытой', (tester) async {
    await _pumpCategories(tester, [_top('food', 'Продукты', 0)]);
    await _openSubcategories(tester, 'Продукты');

    for (final name in ['Молоко', ' молоко ']) {
      await tester.tap(find.text(subcategoriesAddAction));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), name);
      await tester.tap(find.text(categoryFormSaveLabel));
      await tester.pumpAndSettle();
    }

    expect(
      find.text('Такая категория уже есть. Выберите другое название'),
      findsOneWidget,
    );
    expect(find.text(categoryFormSaveLabel), findsOneWidget);
  });
}
