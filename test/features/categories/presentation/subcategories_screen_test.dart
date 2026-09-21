import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart'
    show CustomSemanticsAction, SemanticsAction;
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/app/app.dart';
import 'package:money_app/core/ui/category_rule_text.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/categories/domain/categories_repository.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/categories/presentation/categories_screen.dart';
import 'package:money_app/features/categories/presentation/subcategories_screen.dart';

import '../../../support/fakes.dart';

final _parent = Category.topLevel(
  id: 'food',
  kind: CategoryKind.expense,
  name: 'Продукты',
  iconKey: 'shopping_cart',
  sortOrder: 0,
);

Category _s(
  String id,
  String name,
  int order, {
  Category? parent,
  bool archived = false,
}) {
  final category = Category.subcategoryOf(
    id: id,
    parent: parent ?? _parent,
    name: name,
    iconKey: 'shopping_cart',
    sortOrder: order,
  );
  return archived ? category.archived(DateTime.utc(2026, 9, 1)) : category;
}

List<Category> _fixture() => [
  _parent,
  Category.topLevel(
    id: 'cafe',
    kind: CategoryKind.expense,
    name: 'Кафе',
    iconKey: 'restaurant',
    sortOrder: 1,
  ),
  _s('milk', 'Молоко', 0),
  _s('bread', 'Хлеб', 1),
  _s('meat', 'Мясо', 2),
  _s('old', 'Старое', 3, archived: true),
  // Подкатегория другой категории: здесь её быть не должно.
  _s(
    'tea',
    'Чай',
    0,
    parent: Category.topLevel(
      id: 'cafe',
      kind: CategoryKind.expense,
      name: 'Кафе',
      iconKey: 'restaurant',
      sortOrder: 1,
    ),
  ),
];

/// Что попросил открыть экран: создание и переименование подкатегорий.
int createCalls = 0;
final renamed = <Category>[];

/// Пока не завершён, «форма» считается открытой (колбэки ждут его).
Future<void>? formGate;

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
      locale: MoneyApp.appLocale,
      supportedLocales: MoneyApp.supportedLocales,
      localizationsDelegates: MoneyApp.localizationsDelegates,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: SubcategoriesScreen(
        parent: _parent,
        categories: repository,
        onCreate: () async {
          createCalls++;
          await formGate;
        },
        onRename: (subcategory) async {
          renamed.add(subcategory);
          await formGate;
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Кнопка действия («В архив»/«Вернуть из архива») в строке с id [id].
Finder _button(String id) => find.descendant(
  of: find.byKey(ValueKey<String>(id)),
  matching: find.byType(TextButton),
);

Finder _handleOf(String id) => find.descendant(
  of: find.byKey(ValueKey<String>(id)),
  matching: find.byIcon(Icons.drag_handle),
);

Future<void> _openArchive(WidgetTester tester) async {
  await tester.tap(find.textContaining('Архив ('));
  await tester.pumpAndSettle();
}

Future<void> _drag(WidgetTester tester, Finder handle, double dy) async {
  final gesture = await tester.startGesture(tester.getCenter(handle));
  await gesture.moveBy(Offset(0, dy.sign * 20));
  await tester.pump();
  await gesture.moveBy(Offset(0, dy - dy.sign * 20));
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

List<String> _shownOrder(WidgetTester tester, List<String> names) {
  final sorted = [...names]
    ..sort(
      (a, b) => tester
          .getTopLeft(find.text(a))
          .dy
          .compareTo(tester.getTopLeft(find.text(b)).dy),
    );
  return sorted;
}

class _BrokenRepository extends FakeCategoriesRepository {
  @override
  Stream<List<Category>> watchAll() => Stream.error(Exception('boom'));
}

void main() {
  setUp(() {
    createCalls = 0;
    renamed.clear();
    formGate = null;
  });

  testWidgets('заголовок — имя родителя, подпись «Подкатегории», живые '
      'подкатегории только этого родителя по порядку', (tester) async {
    await _pump(tester, _fixture());

    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Продукты')),
      findsOneWidget,
    );
    expect(find.text(subcategoriesSectionTitle), findsOneWidget);
    expect(_shownOrder(tester, ['Молоко', 'Хлеб', 'Мясо']), [
      'Молоко',
      'Хлеб',
      'Мясо',
    ]);
    expect(find.text('Чай'), findsNothing);
    // Архивная свёрнута, вкладок вида нет, кнопок подкатегорий у строк нет.
    expect(find.text('Старое'), findsNothing);
    expect(find.text(categoriesArchiveTitle(1)), findsOneWidget);
    expect(find.byType(Tab), findsNothing);
    expect(find.byIcon(Icons.subdirectory_arrow_right), findsNothing);
    expect(find.textContaining('Подкатегорий:'), findsNothing);
    expect(find.text(subcategoriesAddAction), findsOneWidget);
  });

  testWidgets('пустое состояние: «Подкатегорий пока нет»', (tester) async {
    await _pump(tester, [_parent]);

    expect(find.text(subcategoriesEmptyText), findsOneWidget);
    expect(find.text(subcategoriesAddAction), findsOneWidget);
  });

  testWidgets('только архивные: подсказка и раздел архива', (tester) async {
    await _pump(tester, [_parent, _s('old', 'Старое', 0, archived: true)]);

    expect(find.text(subcategoriesEmptyText), findsOneWidget);
    expect(find.text(categoriesArchiveTitle(1)), findsOneWidget);
  });

  testWidgets('база не отдала список: сообщение об ошибке', (tester) async {
    await _pumpWith(tester, _BrokenRepository());

    expect(find.text(subcategoriesLoadErrorText), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    '«Добавить подкатегорию» вызывает создание; двойной тап открывает '
    'одну форму',
    (tester) async {
      final gate = Completer<void>();
      formGate = gate.future;
      await _pump(tester, _fixture());

      await tester.tap(find.text(subcategoriesAddAction));
      await tester.pump();
      await tester.tap(find.text(subcategoriesAddAction));
      await tester.pump();
      expect(createCalls, 1);

      gate.complete();
      await tester.pumpAndSettle();
      formGate = null;
      await tester.tap(find.text(subcategoriesAddAction));
      await tester.pumpAndSettle();
      expect(createCalls, 2);
    },
  );

  testWidgets('карандаш «Переименовать: X» есть у живых и архивных', (
    tester,
  ) async {
    await _pump(tester, _fixture());

    Finder pencil(String id, String name) => find.descendant(
      of: find.byKey(ValueKey<String>(id)),
      matching: find.byTooltip(categoriesRenameLabel(name)),
    );
    expect(
      tester.getSize(pencil('bread', 'Хлеб')).width,
      greaterThanOrEqualTo(48),
    );
    await tester.tap(pencil('bread', 'Хлеб'));
    await tester.pumpAndSettle();
    expect(renamed.map((c) => c.id), ['bread']);

    await _openArchive(tester);
    await tester.tap(pencil('old', 'Старое'));
    await tester.pumpAndSettle();
    expect(renamed.map((c) => c.id), ['bread', 'old']);
  });

  testWidgets('в архив: сообщение «Подкатегория «X» в архиве», «Вернуть» '
      'возвращает', (tester) async {
    final repository = await _pump(tester, _fixture());

    await tester.tap(_button('bread'));
    await tester.pumpAndSettle();

    expect(find.text('Подкатегория «Хлеб» в архиве'), findsOneWidget);
    expect(find.text(categoriesUndoAction), findsOneWidget);
    expect(find.text('Хлеб'), findsNothing);
    expect(find.text(categoriesArchiveTitle(2)), findsOneWidget);
    expect(repository.all.firstWhere((c) => c.id == 'bread').isArchived, true);

    await tester.tap(find.text(categoriesUndoAction));
    await tester.pumpAndSettle();
    expect(find.text('Хлеб'), findsOneWidget);
    expect(find.text(categoriesArchiveTitle(1)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('сообщение об архиве исчезает через 6 секунд', (tester) async {
    await _pump(tester, _fixture());

    await tester.tap(_button('bread'));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsOneWidget);

    await tester.pump(categoriesArchivedDuration + const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('архив: пояснение, «Вернуть из архива» возвращает в список', (
    tester,
  ) async {
    final repository = await _pump(tester, _fixture());

    await _openArchive(tester);
    expect(find.text(subcategoriesArchiveNote), findsOneWidget);
    expect(find.text('Старое'), findsOneWidget);

    await tester.tap(_button('old'));
    await tester.pumpAndSettle();

    expect(repository.all.firstWhere((c) => c.id == 'old').isArchived, false);
    expect(find.textContaining('Архив ('), findsNothing);
    expect(find.text('Старое'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('возврат при занятом имени: отказ с объяснением, остаётся в '
      'архиве', (tester) async {
    final repository = await _pump(tester, [
      _parent,
      _s('milk', 'Молоко', 0),
      _s('milk-old', 'молоко', 1, archived: true),
    ]);

    await _openArchive(tester);
    await tester.tap(_button('milk-old'));
    await tester.pumpAndSettle();

    expect(find.text(subcategoryRestoreDuplicateText), findsOneWidget);
    expect(find.text(categoryRestoreDuplicateText), findsNothing);
    expect(
      repository.all.firstWhere((c) => c.id == 'milk-old').isArchived,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  group('«Вернуть» после ухода с экрана', () {
    Future<InMemoryCategoriesRepository> archiveAndLeave(
      WidgetTester tester,
    ) async {
      final repository = InMemoryCategoriesRepository(_fixture());
      addTearDown(repository.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          locale: MoneyApp.appLocale,
          supportedLocales: MoneyApp.supportedLocales,
          localizationsDelegates: MoneyApp.localizationsDelegates,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SubcategoriesScreen(
                      parent: _parent,
                      categories: repository,
                      onCreate: () async {},
                      onRename: (_) async {},
                    ),
                  ),
                ),
                child: const Text('открыть'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('открыть'));
      await tester.pumpAndSettle();
      await tester.tap(_button('bread'));
      await tester.pumpAndSettle();
      // Уходим с экрана; сообщение с «Вернуть» остаётся на корневом messenger.
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      expect(find.byType(SubcategoriesScreen), findsNothing);
      return repository;
    }

    testWidgets('занятое имя: объяснение про подкатегорию', (tester) async {
      final repository = await archiveAndLeave(tester);
      await repository.create(_s('bread2', 'Хлеб', 9));

      await tester.tap(find.text(categoriesUndoAction));
      await tester.pumpAndSettle();

      expect(find.text(subcategoryRestoreDuplicateText), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('сбой базы: общее сообщение', (tester) async {
      final repository = await archiveAndLeave(tester);
      repository.failWith = Exception('disk');

      await tester.tap(find.text(categoriesUndoAction));
      await tester.pumpAndSettle();

      expect(find.text(categorySaveFailedText), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('сбой записи при архивации: общее сообщение', (tester) async {
    final repository = await _pump(tester, _fixture());
    repository.failWith = Exception('disk');

    await tester.tap(_button('bread'));
    await tester.pumpAndSettle();

    expect(find.text(categorySaveFailedText), findsOneWidget);
    expect(find.text('Хлеб'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('порядок', () {
    testWidgets('перетаскивание за ручку пишет порядок подкатегорий целиком', (
      tester,
    ) async {
      final repository = await _pump(tester, _fixture());

      await _drag(tester, _handleOf('milk'), 60);

      expect(repository.reorderCalls, [
        ['bread', 'milk', 'meat'],
      ]);
      expect(_shownOrder(tester, ['Молоко', 'Хлеб', 'Мясо']), [
        'Хлеб',
        'Молоко',
        'Мясо',
      ]);
      expect(find.byType(SnackBar), findsNothing);
      // Порядок в репозитории: перестановленные первыми, дальше остальные
      // подкатегории родителя.
      final subs = repository.all
          .where((c) => c.parentId == 'food' && !c.isArchived)
          .map((c) => c.id);
      expect(subs, ['bread', 'milk', 'meat']);
    });

    testWidgets('ручка есть у живых, у архивных нет', (tester) async {
      await _pump(tester, _fixture());
      expect(find.byIcon(Icons.drag_handle), findsNWidgets(3));

      await _openArchive(tester);
      expect(find.byIcon(Icons.drag_handle), findsNWidgets(3));
    });

    testWidgets('скринридер: «вниз» переставляет и объявляет позицию', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final repository = await _pump(tester, _fixture());

      final node = tester.getSemantics(find.byKey(const ValueKey('milk')));
      final actions = {
        for (final id
            in node.getSemanticsData().customSemanticsActionIds ?? <int>[])
          CustomSemanticsAction.getAction(id)!.label!: id,
      };
      expect(actions.keys, containsAll(['Переместить вниз']));
      expect(actions.keys, isNot(contains('Переместить вверх')));
      node.owner!.performAction(
        node.id,
        SemanticsAction.customAction,
        actions['Переместить вниз'],
      );
      await tester.pumpAndSettle();

      expect(repository.reorderCalls, [
        ['bread', 'milk', 'meat'],
      ]);
      semantics.dispose();
    });

    testWidgets('ошибка записи: сообщение и порядок из базы', (tester) async {
      final repository = await _pump(tester, _fixture());
      repository.failWith = Exception('disk');

      await _drag(tester, _handleOf('milk'), 60);

      expect(find.text(categorySaveFailedText), findsOneWidget);
      expect(_shownOrder(tester, ['Молоко', 'Хлеб', 'Мясо']), [
        'Молоко',
        'Хлеб',
        'Мясо',
      ]);
    });
  });

  testWidgets('масштаб шрифта 200 %: без переполнения, кнопки достижимы', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pump(tester, [
      Category.topLevel(
        id: 'food',
        kind: CategoryKind.expense,
        name: 'Продукты с очень длинным названием',
        iconKey: 'shopping_cart',
        sortOrder: 0,
      ),
      _s('long', 'Очень длинное название подкатегории', 0),
      _s('long-old', 'Архивная подкатегория длинная', 1, archived: true),
    ], textScale: 2);

    await _openArchive(tester);
    expect(find.text(categoriesRestoreAction), findsOneWidget);
    expect(find.text(categoriesArchiveAction), findsOneWidget);
    expect(find.text(subcategoriesAddAction), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
