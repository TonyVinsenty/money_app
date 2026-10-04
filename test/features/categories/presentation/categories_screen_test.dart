import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart'
    show CustomSemanticsAction, SemanticsAction;
import 'package:flutter/services.dart' show SystemChannels;
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/app/app.dart';
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
  // Подкатегории в списке категорий не показываются.
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
      locale: MoneyApp.appLocale,
      supportedLocales: MoneyApp.supportedLocales,
      localizationsDelegates: MoneyApp.localizationsDelegates,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: CategoriesScreen(
        categories: repository,
        onCreate: (kind) async {
          created.add(kind);
          await formGate;
        },
        onRename: (category) async {
          renamed.add(category);
          await formGate;
        },
        onOpenSubcategories: (category) async {
          openedSubcategories.add(category);
          await formGate;
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Что попросил открыть экран: виды для создания, категории для
/// переименования и категории, чьи подкатегории открывают.
final created = <CategoryKind>[];
final renamed = <Category>[];
final openedSubcategories = <Category>[];

/// Пока не завершён, «форма» считается открытой (колбэки ждут его).
Future<void>? formGate;

String _nameOf(String id) => _fixture().firstWhere((c) => c.id == id).name;

/// Кнопка «В архив»/«Вернуть» в строке категории с id [id]: первая из
/// текстовых кнопок строки, вторая (если есть) — «Подкатегории».
Finder _button(String id) => find
    .descendant(
      of: find.byKey(ValueKey<String>(id)),
      matching: find.byType(TextButton),
    )
    .first;

Future<void> _openArchive(WidgetTester tester) async {
  await tester.tap(find.textContaining('Архив ('));
  await tester.pumpAndSettle();
}

/// Тянет ручку на [dy] пикселей по вертикали: сначала небольшой сдвиг (жест
/// начинается), затем остальной путь, и лишь потом палец отпускается.
Future<void> dragHandle(WidgetTester tester, Finder handle, double dy) async {
  final gesture = await tester.startGesture(tester.getCenter(handle));
  await gesture.moveBy(Offset(0, dy.sign * 20));
  await tester.pump();
  await gesture.moveBy(Offset(0, dy - dy.sign * 20));
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

class _BrokenRepository extends FakeCategoriesRepository {
  @override
  Stream<List<Category>> watchAll() => Stream.error(Exception('boom'));
}

void main() {
  setUp(() {
    created.clear();
    renamed.clear();
    openedSubcategories.clear();
    formGate = null;
  });

  testWidgets('кнопки строки: иконка и текст цветом primary, высота от 48 dp; '
      'у архивной «Вернуть из архива» та же форма', (tester) async {
    await _pump(tester, _fixture());
    final primary = Theme.of(tester.element(find.byType(CategoriesScreen)))
        .colorScheme
        .primary;

    /// Кнопка с текстом [text] в строке категории [id].
    Finder rowButton(String id, String text) => find.descendant(
      of: find.byKey(ValueKey<String>(id)),
      matching: find.widgetWithText(TextButton, text),
    );

    void expectActionStyle(String id, String text, IconData icon) {
      final button = rowButton(id, text);
      expect(button, findsOneWidget, reason: '$id: «$text»');
      expect(
        tester.getSize(button).height,
        greaterThanOrEqualTo(48),
        reason: '$id: «$text»',
      );
      expect(
        find.descendant(of: button, matching: find.byIcon(icon)),
        findsOneWidget,
        reason: '$id: иконка «$text»',
      );
      // Цвет текста кнопки — цвет темы primary.
      final textContext = tester.element(
        find.descendant(of: button, matching: find.text(text)),
      );
      expect(
        DefaultTextStyle.of(textContext).style.color,
        primary,
        reason: '$id: цвет «$text»',
      );
    }

    expectActionStyle('cafe', categoriesArchiveAction, Icons.archive_outlined);
    expectActionStyle(
      'cafe',
      categoriesSubcategoriesAction,
      Icons.account_tree_outlined,
    );

    await _openArchive(tester);
    expectActionStyle(
      'clothes',
      categoriesRestoreAction,
      Icons.unarchive_outlined,
    );
  });

  /// Центры по вертикали: название и кнопки строки «Кафе».
  Finder inCafe(Finder finder) => find.descendant(
    of: find.byKey(const ValueKey<String>('cafe')),
    matching: finder,
  );

  testWidgets('строка на 360 dp: кнопки ниже названия, без переполнения при '
      'масштабе 1 и 2', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pump(tester, _fixture());

    final nameY = tester.getCenter(inCafe(find.text('Кафе'))).dy;
    final archiveY = tester
        .getCenter(inCafe(find.text(categoriesArchiveAction)))
        .dy;
    expect(archiveY, greaterThan(nameY));
    expect(tester.takeException(), isNull);

    // При крупном шрифте строка переносится, но исключений нет.
    await _pump(tester, [
      _c('long', 'Очень длинное название категории', 0),
      Category.subcategoryOf(
        id: 'sub',
        parent: _c('long', 'Очень длинное название категории', 0),
        name: 'Подкатегория',
        iconKey: 'shopping_cart',
        sortOrder: 0,
      ),
    ], textScale: 2);
    expect(find.text(categoriesSubcategoryCount(1)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('строка: «В архив» и «Подкатегории» в одном ряду, если ширины '
      'хватает', (tester) async {
    // На 360 dp тестовый шрифт (Ahem: каждый символ шириной с кегль) не даёт
    // уместить две кнопки в 288 dp, поэтому ряд проверяем на 600 dp. Проверка
    // на 360 dp нужна с настоящим шрифтом: это решение пользователя (шрифт в
    // docs/design-style.md), пока её нет.
    tester.view.physicalSize = const Size(600, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pump(tester, _fixture());

    final archiveY = tester
        .getCenter(inCafe(find.text(categoriesArchiveAction)))
        .dy;
    final subY = tester
        .getCenter(inCafe(find.text(categoriesSubcategoriesAction)))
        .dy;
    expect(archiveY, closeTo(subY, 1));
  });

  testWidgets('между строками категорий виден разделитель, отступ 40 dp и цвет '
      'outlineVariant', (tester) async {
    await _pump(tester, _fixture());

    final divider = find.descendant(
      of: find.byKey(const ValueKey<String>('cafe')),
      matching: find.byType(Divider),
    );
    expect(divider, findsOneWidget);
    final widget = tester.widget<Divider>(divider);
    expect(widget.indent, 40);
    final outline = Theme.of(tester.element(find.byType(CategoriesScreen)))
        .colorScheme
        .outlineVariant;
    expect(widget.color, outline);
    // Разделитель стоит под кнопками «Кафе» и над следующей строкой.
    expect(
      tester.getCenter(divider).dy,
      greaterThan(
        tester
            .getCenter(
              find.descendant(
                of: find.byKey(const ValueKey<String>('cafe')),
                matching: find.text(categoriesArchiveAction),
              ),
            )
            .dy,
      ),
    );
    expect(
      tester.getCenter(divider).dy,
      lessThan(tester.getCenter(find.text('Транспорт')).dy),
    );
  });

  group('подкатегории в строке', () {
    /// Текстовая кнопка «Подкатегории» в строке категории [id].
    Finder subButton(String id) => find.descendant(
      of: find.byKey(ValueKey<String>(id)),
      matching: find.widgetWithText(TextButton, categoriesSubcategoriesAction),
    );

    testWidgets('у живой категории есть кнопка «Подкатегории» от 48 dp, идёт '
        'после «В архив»; тап открывает подкатегории этой категории', (
      tester,
    ) async {
      await _pump(tester, _fixture());

      expect(subButton('cafe'), findsOneWidget);
      final size = tester.getSize(subButton('cafe'));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
      final archiveY = tester
          .getCenter(
            find.descendant(
              of: find.byKey(const ValueKey<String>('cafe')),
              matching: find.text(categoriesArchiveAction),
            ),
          )
          .dy;
      final handleX = tester
          .getCenter(
            find.descendant(
              of: find.byKey(const ValueKey<String>('cafe')),
              matching: find.byIcon(Icons.drag_handle),
            ),
          )
          .dx;
      // Обе текстовые кнопки идут одна за другой под именем, левее ручки.
      expect(tester.getCenter(subButton('cafe')).dy, closeTo(archiveY, 1));
      expect(tester.getCenter(subButton('cafe')).dx, lessThan(handleX));

      await tester.tap(subButton('cafe'));
      await tester.pumpAndSettle();
      expect(openedSubcategories.map((c) => c.id), ['cafe']);
    });

    testWidgets('подпись «Подкатегории: имя» доступна скринридеру', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, _fixture());

      expect(
        tester.getSemantics(subButton('cafe')),
        isSemantics(
          label: categoriesSubcategoriesLabel('Кафе'),
          isButton: true,
          hasTapAction: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('счётчик «Подкатегорий: N» только у категорий с живыми '
        'подкатегориями', (tester) async {
      final food = _c('food', 'Продукты', 0);
      await _pump(tester, [
        food,
        _c('cafe', 'Кафе', 1),
        Category.subcategoryOf(
          id: 'milk',
          parent: food,
          name: 'Молоко',
          iconKey: 'shopping_cart',
          sortOrder: 0,
        ),
        Category.subcategoryOf(
          id: 'bread',
          parent: food,
          name: 'Хлеб',
          iconKey: 'shopping_cart',
          sortOrder: 1,
        ),
        Category.subcategoryOf(
          id: 'old',
          parent: food,
          name: 'Старое',
          iconKey: 'shopping_cart',
          sortOrder: 2,
        ).archived(DateTime.utc(2026, 9, 1)),
      ]);

      // Архивная подкатегория не считается.
      expect(find.text(categoriesSubcategoryCount(2)), findsOneWidget);
      expect(find.textContaining('Подкатегорий:'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('food')),
          matching: find.text('Подкатегорий: 2'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('у архивной категории кнопки подкатегорий нет', (tester) async {
      await _pump(tester, _fixture());
      await _openArchive(tester);

      expect(find.text('Одежда'), findsOneWidget);
      expect(subButton('clothes'), findsNothing);
      expect(subButton('food'), findsOneWidget);
    });

    testWidgets('двойной тап по кнопке открывает один экран подкатегорий', (
      tester,
    ) async {
      final gate = Completer<void>();
      formGate = gate.future;
      await _pump(tester, _fixture());

      await tester.tap(subButton('cafe'));
      await tester.pump();
      await tester.tap(subButton('cafe'));
      await tester.pump();
      expect(openedSubcategories.map((c) => c.id), ['cafe']);

      gate.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('масштаб 200 %: строка с четырьмя элементами без '
        'переполнения', (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final parent = _c('long', 'Очень длинное название категории', 0);
      await _pump(tester, [
        parent,
        Category.subcategoryOf(
          id: 'sub',
          parent: parent,
          name: 'Подкатегория',
          iconKey: 'shopping_cart',
          sortOrder: 0,
        ),
      ], textScale: 2);

      expect(find.text(categoriesSubcategoryCount(1)), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('кнопка «Добавить категорию» передаёт вид открытой вкладки', (
    tester,
  ) async {
    await _pump(tester, _fixture());

    await tester.tap(find.text(categoriesAddAction));
    await tester.pumpAndSettle();
    await tester.tap(find.text(categoriesIncomeTab));
    await tester.pumpAndSettle();
    await tester.tap(find.text(categoriesAddAction));
    await tester.pumpAndSettle();

    expect(created, [CategoryKind.expense, CategoryKind.income]);
  });

  testWidgets('«Переименовать» есть и у живых категорий, и у архивных', (
    tester,
  ) async {
    await _pump(tester, _fixture());

    Finder rename(String id) => find.descendant(
      of: find.byKey(ValueKey<String>(id)),
      matching: find.byTooltip(categoriesRenameLabel(_nameOf(id))),
    );
    expect(rename('cafe'), findsOneWidget);
    expect(tester.getSize(rename('cafe')).width, greaterThanOrEqualTo(48));
    expect(tester.getSize(rename('cafe')).height, greaterThanOrEqualTo(48));

    await tester.tap(rename('cafe'));
    await tester.pumpAndSettle();
    expect(renamed.map((c) => c.id), ['cafe']);

    await _openArchive(tester);
    expect(rename('clothes'), findsOneWidget);
    // Строки стали выше (кнопки под именем): архивная внизу, прокручиваем до
    // конца списка, чтобы её не закрывала кнопка «Добавить».
    await tester.drag(
      find.byType(ReorderableListView).first,
      const Offset(0, -2000),
    );
    await tester.pumpAndSettle();
    await tester.tap(rename('clothes'));
    await tester.pumpAndSettle();
    expect(renamed.map((c) => c.id), ['cafe', 'clothes']);
  });

  testWidgets('двойной тап по «Добавить категорию» открывает одну форму', (
    tester,
  ) async {
    final gate = Completer<void>();
    formGate = gate.future;
    await _pump(tester, _fixture());

    await tester.tap(find.text(categoriesAddAction));
    await tester.pump();
    await tester.tap(find.text(categoriesAddAction));
    await tester.pump();
    expect(created, [CategoryKind.expense]);

    // Форму закрыли: снова можно открыть.
    gate.complete();
    await tester.pumpAndSettle();
    formGate = null;
    await tester.tap(find.text(categoriesAddAction));
    await tester.pumpAndSettle();
    expect(created, hasLength(2));
  });

  testWidgets('двойной тап по карандашу открывает одну форму, и «Добавить» '
      'не открывает вторую поверх', (tester) async {
    final gate = Completer<void>();
    formGate = gate.future;
    await _pump(tester, _fixture());
    final pencil = find.byTooltip(categoriesRenameLabel('Кафе'));

    await tester.tap(pencil);
    await tester.pump();
    await tester.tap(pencil);
    await tester.pump();
    await tester.tap(find.text(categoriesAddAction));
    await tester.pump();

    expect(renamed.map((c) => c.id), ['cafe']);
    expect(created, isEmpty);
    gate.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('в архив: сообщение с именем и «Вернуть» возвращает категорию', (
    tester,
  ) async {
    await _pump(tester, _fixture());

    await tester.tap(_button('cafe'));
    await tester.pumpAndSettle();

    expect(find.text('Категория «Кафе» в архиве'), findsOneWidget);
    expect(find.text('Вернуть'), findsOneWidget);
    expect(find.text('Кафе'), findsNothing);

    await tester.tap(find.text('Вернуть'));
    await tester.pumpAndSettle();
    expect(find.text('Кафе'), findsOneWidget);
    expect(find.text(categoriesArchiveTitle(1)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('«Вернуть» работает и после ухода с экрана', (tester) async {
    final repository = InMemoryCategoriesRepository(_fixture());
    addTearDown(repository.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => CategoriesScreen(
                    categories: repository,
                    onCreate: (_) async {},
                    onRename: (_) async {},
                    onOpenSubcategories: (_) async {},
                  ),
                ),
              ),
              child: const Text('Открыть'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();

    await tester.tap(_button('cafe'));
    await tester.pumpAndSettle();
    expect(find.text('Категория «Кафе» в архиве'), findsOneWidget);
    expect(repository.all.firstWhere((c) => c.id == 'cafe').isArchived, isTrue);

    // Ушли с экрана категорий; сообщение осталось в корневом мессенджере.
    Navigator.of(tester.element(find.byType(CategoriesScreen))).pop();
    await tester.pumpAndSettle();
    expect(find.byType(CategoriesScreen), findsNothing);
    expect(find.text('Вернуть'), findsOneWidget);

    await tester.tap(find.text('Вернуть'));
    await tester.pumpAndSettle();

    expect(
      repository.all.firstWhere((c) => c.id == 'cafe').isArchived,
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('сообщение об архиве исчезает само через положенное время', (
    tester,
  ) async {
    await _pump(tester, _fixture());

    await tester.tap(_button('cafe'));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsOneWidget);

    await tester.pump(categoriesArchivedDuration + const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('второе «В архив» заменяет прежнее сообщение', (tester) async {
    await _pump(tester, _fixture());

    await tester.tap(_button('cafe'));
    await tester.pumpAndSettle();
    await tester.tap(_button('food'));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('Категория «Продукты» в архиве'), findsOneWidget);
    expect(find.text('Категория «Кафе» в архиве'), findsNothing);
  });

  testWidgets('«Вернуть» при занятом имени: объяснение вместо возврата', (
    tester,
  ) async {
    final repository = await _pump(tester, _fixture());

    await tester.tap(_button('cafe'));
    await tester.pumpAndSettle();
    // Пока лежала в архиве, имя заняли.
    await repository.create(_c('cafe2', 'Кафе', 9));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Вернуть'));
    await tester.pumpAndSettle();

    expect(find.text(categoryRestoreDuplicateText), findsOneWidget);
    expect(find.text('Категория «Кафе» в архиве'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('«Вернуть» после ухода с экрана: отказ всё равно виден', (
    tester,
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
                  builder: (_) => CategoriesScreen(
                    categories: repository,
                    onCreate: (_) async {},
                    onRename: (_) async {},
                    onOpenSubcategories: (_) async {},
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

    await tester.tap(_button('cafe'));
    await tester.pumpAndSettle();
    // Уходим с экрана; сообщение с «Вернуть» остаётся на корневом messenger.
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    expect(find.byType(CategoriesScreen), findsNothing);
    await repository.create(_c('cafe2', 'Кафе', 9));

    await tester.tap(find.text('Вернуть'));
    await tester.pumpAndSettle();

    expect(find.text(categoryRestoreDuplicateText), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('в развёрнутом архиве первой строкой пояснение', (tester) async {
    await _pump(tester, _fixture());
    const noteText = 'Старые операции по этим категориям сохранены';
    expect(find.text(noteText), findsNothing);

    await _openArchive(tester);

    expect(find.text(noteText), findsOneWidget);
    expect(
      tester.getTopLeft(find.text(noteText)).dy,
      lessThan(tester.getTopLeft(find.text('Одежда')).dy),
    );
  });

  testWidgets('последняя строка не закрыта кнопкой «Добавить категорию»', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pump(tester, [for (var i = 0; i < 14; i++) _c('c$i', 'Кат $i', i)]);

    await tester.drag(
      find.byType(ReorderableListView).first,
      const Offset(0, -2000),
    );
    await tester.pumpAndSettle();

    final lastRow = tester.getRect(find.byKey(const ValueKey<String>('c13')));
    final fab = tester.getRect(find.byType(FloatingActionButton));
    expect(lastRow.bottom, lessThanOrEqualTo(fab.top));
  });

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
      find.text(
        'В списке уже есть категория с таким названием. Переименуйте её или '
        'оставьте эту в архиве',
      ),
      findsOneWidget,
    );
    expect(
      find.text(categoryRuleMessage(CategoryRule.duplicateName)),
      findsNothing,
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

    // Название переносится на много строк: раздел архива уходит вниз, к нему
    // прокручиваем список (иначе его закрывает кнопка «Добавить»).
    await tester.drag(find.byType(ReorderableListView), const Offset(0, -300));
    await tester.pumpAndSettle();
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

  group('порядок перетаскиванием', () {
    /// Ручка перетаскивания в строке категории [id].
    Finder handleOf(String id) => find.descendant(
      of: find.byKey(ValueKey<String>(id)),
      matching: find.byIcon(Icons.drag_handle),
    );

    /// Названия живых строк сверху вниз.
    List<String> shownOrder(WidgetTester tester, List<String> names) {
      final sorted = [...names]
        ..sort(
          (a, b) => tester
              .getTopLeft(find.text(a))
              .dy
              .compareTo(tester.getTopLeft(find.text(b)).dy),
        );
      return sorted;
    }

    const expenseNames = ['Продукты', 'Кафе', 'Транспорт'];

    testWidgets('перетаскивание за ручку меняет порядок и пишет его целиком', (
      tester,
    ) async {
      final repository = await _pump(tester, _fixture());

      await dragHandle(tester, handleOf('food'), 60);
      await tester.pumpAndSettle();

      expect(repository.reorderCalls, [
        ['cafe', 'food', 'transport'],
      ]);
      expect(shownOrder(tester, expenseNames), [
        'Кафе',
        'Продукты',
        'Транспорт',
      ]);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('ручка не меньше 48 dp; у архивных её нет; архив внизу', (
      tester,
    ) async {
      await _pump(tester, _fixture());

      for (final id in ['food', 'cafe', 'transport']) {
        final size = tester.getSize(handleOf(id).first);
        expect(size.width, greaterThanOrEqualTo(24), reason: id);
        final zone = tester.getSize(
          find
              .ancestor(
                of: handleOf(id),
                matching: find.byType(ReorderableDragStartListener),
              )
              .first,
        );
        expect(zone.width, greaterThanOrEqualTo(48), reason: id);
        expect(zone.height, greaterThanOrEqualTo(48), reason: id);
      }
      expect(find.byIcon(Icons.drag_handle), findsNWidgets(3));

      await _openArchive(tester);
      expect(find.byIcon(Icons.drag_handle), findsNWidgets(3));
      expect(
        tester.getTopLeft(find.text('Одежда')).dy,
        greaterThan(tester.getTopLeft(find.text('Транспорт')).dy),
      );
    });

    testWidgets('порядок доходов не затрагивает расходы', (tester) async {
      final repository = await _pump(tester, _fixture());

      await tester.tap(find.text(categoriesIncomeTab));
      await tester.pumpAndSettle();
      await dragHandle(tester, handleOf('salary'), 60);
      await tester.pumpAndSettle();

      expect(repository.reorderCalls, [
        ['gift', 'salary'],
      ]);
      expect(shownOrder(tester, ['Зарплата', 'Подарки']), [
        'Подарки',
        'Зарплата',
      ]);

      await tester.tap(find.text(categoriesExpenseTab));
      await tester.pumpAndSettle();
      expect(shownOrder(tester, expenseNames), expenseNames);
    });

    testWidgets(
      'запись идёт: порядок не отскакивает, потом совпадает с базой',
      (tester) async {
        final repository = await _pump(tester, _fixture());
        final gate = Completer<void>();
        repository.reorderGate = gate.future;

        await dragHandle(tester, handleOf('food'), 60);
        await tester.pumpAndSettle();
        // База ещё не ответила, а на экране уже новый порядок.
        expect(shownOrder(tester, expenseNames), [
          'Кафе',
          'Продукты',
          'Транспорт',
        ]);

        // Вторую перестановку, пока идёт запись, не принимаем.
        await dragHandle(tester, handleOf('transport'), -60);
        await tester.pumpAndSettle();
        expect(repository.reorderCalls.length, 1);
        expect(shownOrder(tester, expenseNames), [
          'Кафе',
          'Продукты',
          'Транспорт',
        ]);

        gate.complete();
        await tester.pumpAndSettle();
        expect(shownOrder(tester, expenseNames), [
          'Кафе',
          'Продукты',
          'Транспорт',
        ]);
        expect(find.byType(SnackBar), findsNothing);
      },
    );

    testWidgets('ошибка записи: сообщение и возврат к порядку из базы', (
      tester,
    ) async {
      final repository = await _pump(tester, _fixture());
      repository.failWith = Exception('disk');

      await dragHandle(tester, handleOf('food'), 60);
      await tester.pumpAndSettle();

      expect(find.text(categorySaveFailedText), findsOneWidget);
      expect(shownOrder(tester, expenseNames), expenseNames);
      expect(tester.takeException(), isNull);

      // После сбоя перестановка снова работает.
      repository.failWith = null;
      await dragHandle(tester, handleOf('food'), 60);
      await tester.pumpAndSettle();
      expect(shownOrder(tester, expenseNames), [
        'Кафе',
        'Продукты',
        'Транспорт',
      ]);
    });

    /// Подписи действий, которые скринридер видит у строки [id].
    Map<String, int> actionsOf(WidgetTester tester, String id) {
      final data = tester
          .getSemantics(find.byKey(ValueKey<String>(id)))
          .getSemanticsData();
      return {
        for (final actionId in data.customSemanticsActionIds ?? <int>[])
          CustomSemanticsAction.getAction(actionId)!.label!: actionId,
      };
    }

    void perform(WidgetTester tester, String id, String label) {
      final node = tester.getSemantics(find.byKey(ValueKey<String>(id)));
      node.owner!.performAction(
        node.id,
        SemanticsAction.customAction,
        actionsOf(tester, id)[label],
      );
    }

    testWidgets('скринридер: действия «вверх/вниз» по-русски, у крайних без '
        'недоступных', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester, _fixture());

      expect(actionsOf(tester, 'food').keys, {
        'Переместить вниз',
        'Переместить в конец',
      });
      expect(actionsOf(tester, 'cafe').keys, {
        'Переместить в начало',
        'Переместить вверх',
        'Переместить вниз',
        'Переместить в конец',
      });
      expect(actionsOf(tester, 'transport').keys, {
        'Переместить в начало',
        'Переместить вверх',
      });
      semantics.dispose();
    });

    testWidgets('скринридер: «вниз» переставляет и объявляет позицию', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final announcements = <String>[];
      tester.binding.defaultBinaryMessenger
          .setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, (
            message,
          ) async {
            final map = message as Map<Object?, Object?>;
            if (map['type'] == 'announce') {
              final data = map['data']! as Map<Object?, Object?>;
              announcements.add(data['message']! as String);
            }
            return null;
          });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger
            .setMockDecodedMessageHandler<dynamic>(
              SystemChannels.accessibility,
              null,
            ),
      );
      final repository = await _pump(tester, _fixture());

      perform(tester, 'food', 'Переместить вниз');
      await tester.pumpAndSettle();

      expect(repository.reorderCalls, [
        ['cafe', 'food', 'transport'],
      ]);
      expect(announcements, [categoriesMovedAnnouncement('Продукты', 2, 3)]);
      expect(announcements.single, 'Продукты: позиция 2 из 3');

      perform(tester, 'transport', 'Переместить в начало');
      await tester.pumpAndSettle();
      expect(repository.reorderCalls.last, ['transport', 'cafe', 'food']);
      expect(announcements.last, 'Транспорт: позиция 1 из 3');

      perform(tester, 'transport', 'Переместить вниз');
      await tester.pumpAndSettle();
      expect(repository.reorderCalls.last, ['cafe', 'transport', 'food']);
      semantics.dispose();
    });

    testWidgets('масштаб 200 %: ручка есть, переполнения нет', (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _pump(tester, [
        _c('long', 'Очень длинное название категории', 0),
        _c('long2', 'Ещё одно очень длинное название', 1),
      ], textScale: 2);

      expect(find.byIcon(Icons.drag_handle), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });
  });
}
