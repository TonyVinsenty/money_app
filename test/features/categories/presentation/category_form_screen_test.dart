import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/ui/category_icons.dart';
import 'package:money_app/core/ui/category_rule_text.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/categories/domain/category_rules.dart';
import 'package:money_app/features/categories/presentation/category_form_screen.dart';

import '../../../support/fake_id_generator.dart';
import '../../../support/fakes.dart';

Category _c(
  String id,
  String name,
  int order, {
  CategoryKind kind = CategoryKind.expense,
  String iconKey = 'restaurant',
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
  _c('cafe', 'Кафе', 1),
  _c('old', 'Старая', 5, archived: true),
  _c('salary', 'Зарплата', 9, kind: CategoryKind.income, iconKey: 'payments'),
];

/// Репозиторий, у которого `create` ждёт, пока тест не откроет [gate].
class _SlowRepository extends InMemoryCategoriesRepository {
  _SlowRepository(super.initial);

  final gate = Completer<void>();
  int started = 0;

  @override
  Future<void> create(Category category) async {
    started++;
    await gate.future;
    await super.create(category);
  }
}

/// Открывает форму поверх «главной» с кнопкой `open`, чтобы можно было
/// проверить закрытие экрана и кнопку «Назад».
Future<void> _openForm(
  WidgetTester tester,
  InMemoryCategoriesRepository repository, {
  CategoryKind kind = CategoryKind.expense,
  Category? renaming,
  Category? parent,
  double textScale = 1,
}) async {
  tester.view.physicalSize = const Size(360, 740);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => unawaited(
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => CategoryFormScreen(
                      categories: repository,
                      idGenerator: FakeIdGenerator(),
                      initialKind: kind,
                      renaming: renaming,
                      parent: parent,
                    ),
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

InMemoryCategoriesRepository _repo([List<Category>? initial]) {
  final repository = InMemoryCategoriesRepository(initial ?? _fixture());
  return repository;
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump();
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.text(categoryFormSaveLabel));
  await tester.pumpAndSettle();
}

Finder _icon(String key) => find.byKey(ValueKey<String>('icon-$key'));

bool _formIsOpen() => find.text(categoryFormSaveLabel).evaluate().isNotEmpty;

bool isSelected(WidgetTester tester, String key) =>
    tester.getSemantics(_icon(key)).flagsCollection.isSelected ==
    ui.Tristate.isTrue;

void main() {
  late InMemoryCategoriesRepository repository;

  setUp(() {
    repository = _repo();
    addTearDown(repository.dispose);
  });

  testWidgets('новая расходная категория: в конец своего вида, иконка по '
      'умолчанию — первая', (tester) async {
    await _openForm(tester, repository);
    expect(find.text(categoryFormCreateTitle), findsOneWidget);

    await _type(tester, '  Кино  ');
    await _save(tester);

    expect(_formIsOpen(), isFalse);
    final created = repository.all.last;
    expect(created.id, 'id-1');
    expect(created.name, 'Кино');
    expect(created.kind, CategoryKind.expense);
    expect(created.iconKey, categoryIconKeys.first);
    expect(created.isTopLevel, isTrue);
    // Расходы: 0, 1 и архивная 5, значит, следующая — 6; доход (9) не мешает.
    expect(created.sortOrder, 6);
  });

  group('подкатегория', () {
    Category sub(String id, String name, int order, {bool archived = false}) {
      final parent = _c('food', 'Продукты', 0);
      final category = Category.subcategoryOf(
        id: id,
        parent: parent,
        name: name,
        iconKey: 'restaurant',
        sortOrder: order,
      );
      return archived ? category.archived(DateTime.utc(2026, 9, 1)) : category;
    }

    setUp(() {
      repository = _repo([
        ..._fixture(),
        sub('milk', 'Молоко', 0),
        sub('old', 'Старое', 4, archived: true),
        // Подкатегория другого родителя: порядок она не сдвигает.
        Category.subcategoryOf(
          id: 'tea',
          parent: _c('cafe', 'Кафе', 1),
          name: 'Чай',
          iconKey: 'restaurant',
          sortOrder: 20,
        ),
      ]);
      addTearDown(repository.dispose);
    });

    testWidgets('создание: только имя, вид и иконка от родителя, порядок '
        'в конец (архивные считаются)', (tester) async {
      final parent = _c(
        'salary',
        'Зарплата',
        9,
        kind: CategoryKind.income,
        iconKey: 'payments',
      );
      repository = _repo([
        parent,
        Category.subcategoryOf(
          id: 'bonus',
          parent: parent,
          name: 'Бонус',
          iconKey: 'payments',
          sortOrder: 0,
        ),
      ]);
      addTearDown(repository.dispose);
      await _openForm(tester, repository, kind: parent.kind, parent: parent);

      expect(
        find.text(subcategoryFormCreateTitle(parent.name)),
        findsOneWidget,
      );
      expect(find.text(categoryFormCreateTitle), findsNothing);
      expect(find.text(categoryFormKindTitle), findsNothing);
      expect(find.text(categoryFormIconTitle), findsOneWidget);
      expect(find.byType(SegmentedButton<CategoryKind>), findsNothing);
      expect(find.textContaining('Тип:'), findsNothing);
      // Автофокус, как в форме категории.
      expect(
        tester.widget<TextField>(find.byType(TextField)).autofocus,
        isTrue,
      );

      await _type(tester, '  Премия ');
      await _save(tester);

      expect(_formIsOpen(), isFalse);
      final created = repository.all.last;
      expect(created.name, 'Премия');
      expect(created.parentId, 'salary');
      expect(created.kind, CategoryKind.income);
      expect(created.iconKey, 'payments');
      expect(created.sortOrder, 1);
    });

    testWidgets('порядок: после самой большой подкатегории родителя, включая '
        'архивную', (tester) async {
      final parent = _c('food', 'Продукты', 0);
      await _openForm(tester, repository, kind: parent.kind, parent: parent);

      await _type(tester, 'Хлеб');
      await _save(tester);

      expect(repository.all.last.parentId, 'food');
      expect(repository.all.last.sortOrder, 5);
    });

    testWidgets('переименование: свой заголовок, имя подставлено, без типа', (
      tester,
    ) async {
      final parent = _c('food', 'Продукты', 0);
      await _openForm(
        tester,
        repository,
        kind: parent.kind,
        parent: parent,
        renaming: sub('milk', 'Молоко', 0),
      );

      expect(find.text(subcategoryFormRenameTitle), findsOneWidget);
      expect(find.textContaining('Тип:'), findsNothing);
      expect(find.text('Молоко'), findsOneWidget);

      await _type(tester, 'Кефир');
      await _save(tester);

      expect(_formIsOpen(), isFalse);
      expect(repository.all.firstWhere((c) => c.id == 'milk').name, 'Кефир');
    });

    testWidgets('дубль имени внутри родителя: тот же текст под полем; такое '
        'же имя у другого родителя допустимо', (tester) async {
      final parent = _c('food', 'Продукты', 0);
      await _openForm(tester, repository, kind: parent.kind, parent: parent);

      await _type(tester, 'молоко');
      await _save(tester);
      expect(
        find.text('Такая подкатегория уже есть. Выберите другое название'),
        findsOneWidget,
      );
      expect(
        find.text(categoryRuleMessage(CategoryRule.duplicateName)),
        findsNothing,
      );
      expect(_formIsOpen(), isTrue);

      await _type(tester, 'Чай');
      await _save(tester);
      expect(_formIsOpen(), isFalse);
      expect(repository.all.last.name, 'Чай');
    });

    testWidgets('пустое имя: текст под полем, ничего не записано', (
      tester,
    ) async {
      final parent = _c('food', 'Продукты', 0);
      await _openForm(tester, repository, kind: parent.kind, parent: parent);

      await _type(tester, '  ');
      await _save(tester);

      expect(find.text('Введите название подкатегории'), findsOneWidget);
      expect(
        find.text(categoryRuleMessage(CategoryRule.emptyName)),
        findsNothing,
      );
      expect(_formIsOpen(), isTrue);
    });

    testWidgets('переименование с пустым именем: текст про подкатегорию', (
      tester,
    ) async {
      final parent = _c('food', 'Продукты', 0);
      await _openForm(
        tester,
        repository,
        kind: parent.kind,
        parent: parent,
        renaming: sub('milk', 'Молоко', 0),
      );

      await _type(tester, '');
      await _save(tester);

      expect(find.text('Введите название подкатегории'), findsOneWidget);
    });

    testWidgets('двойной тап по «Сохранить» пишет одну подкатегорию', (
      tester,
    ) async {
      final slow = _SlowRepository(_fixture());
      addTearDown(slow.dispose);
      final parent = _c('food', 'Продукты', 0);
      await _openForm(tester, slow, kind: parent.kind, parent: parent);
      await _type(tester, 'Молоко');

      await tester.tap(find.text(categoryFormSaveLabel));
      await tester.pump();
      await tester.tap(find.text(categoryFormSaveLabel), warnIfMissed: false);
      await tester.pump();
      slow.gate.complete();
      await tester.pumpAndSettle();

      expect(slow.started, 1);
      expect(slow.all.where((c) => c.parentId == 'food'), hasLength(1));
    });

    testWidgets('создание: выбран значок родителя, выбор другого пишется', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final parent = _c('food', 'Продукты', 0);
      await _openForm(tester, repository, kind: parent.kind, parent: parent);
      expect(isSelected(tester, 'restaurant'), isTrue);

      await _type(tester, 'Эспрессо');
      await tester.ensureVisible(_icon('local_cafe'));
      await tester.tap(_icon('local_cafe'));
      await tester.pump();
      expect(isSelected(tester, 'local_cafe'), isTrue);
      expect(isSelected(tester, 'restaurant'), isFalse);
      await _save(tester);

      final created = repository.all.last;
      expect(created.name, 'Эспрессо');
      expect(created.iconKey, 'local_cafe');
      expect(created.parentId, 'food');
      expect(
        repository.all.firstWhere((c) => c.id == 'food').iconKey,
        'restaurant',
      );
      handle.dispose();
    });

    testWidgets('правка: выбран свой значок, смена не трогает родителя', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final parent = _c('food', 'Продукты', 0);
      final milk = Category.subcategoryOf(
        id: 'milk2',
        parent: parent,
        name: 'Молоко2',
        iconKey: 'movie',
        sortOrder: 7,
      );
      repository = _repo([..._fixture(), milk]);
      addTearDown(repository.dispose);
      await _openForm(
        tester,
        repository,
        kind: parent.kind,
        parent: parent,
        renaming: milk,
      );
      expect(find.text(subcategoryFormRenameTitle), findsOneWidget);
      expect(isSelected(tester, 'movie'), isTrue);

      await tester.ensureVisible(_icon('local_cafe'));
      await tester.tap(_icon('local_cafe'));
      await tester.pump();
      await _save(tester);

      final edited = repository.all.firstWhere((c) => c.id == 'milk2');
      expect(edited.iconKey, 'local_cafe');
      expect(edited.name, 'Молоко2');
      expect(edited.sortOrder, 7);
      expect(
        repository.all.firstWhere((c) => c.id == 'food').iconKey,
        'restaurant',
      );
      handle.dispose();
    });

    testWidgets('правка: подкатегория из импорта (more_horiz) получает «Ж»', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final parent = _c('food', 'Продукты', 0);
      final imported = Category.subcategoryOf(
        id: 'imp',
        parent: parent,
        name: 'Импортная',
        iconKey: 'more_horiz',
        sortOrder: 8,
      );
      repository = _repo([..._fixture(), imported]);
      addTearDown(repository.dispose);
      await _openForm(
        tester,
        repository,
        kind: parent.kind,
        parent: parent,
        renaming: imported,
      );
      expect(isSelected(tester, 'more_horiz'), isTrue);

      await tester.ensureVisible(_icon('glyph:Ж'));
      await tester.tap(_icon('glyph:Ж'));
      await tester.pump();
      await _save(tester);

      expect(
        repository.all.firstWhere((c) => c.id == 'imp').iconKey,
        'glyph:Ж',
      );
      handle.dispose();
    });

    testWidgets('правка: 360 dp и шрифт 200 % без переполнения', (
      tester,
    ) async {
      final parent = _c('food', 'Продукты', 0);
      await _openForm(
        tester,
        repository,
        kind: parent.kind,
        parent: parent,
        renaming: sub('milk', 'Молоко', 0),
        textScale: 2,
      );
      await tester.ensureVisible(_icon(categoryIconKeys.last));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('масштаб 200 %: без переполнения', (tester) async {
      final parent = _c('food', 'Продукты', 0);
      await _openForm(
        tester,
        repository,
        kind: parent.kind,
        parent: parent,
        textScale: 2,
      );

      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('доходная категория: вид открытой вкладки предвыбран, можно '
      'сменить', (tester) async {
    await _openForm(tester, repository, kind: CategoryKind.income);

    await _type(tester, 'Подработка');
    await _save(tester);

    final created = repository.all.last;
    expect(created.kind, CategoryKind.income);
    expect(created.sortOrder, 10);

    // Вид меняется переключателем.
    await tester.pumpWidget(const SizedBox());
    await _openForm(tester, repository, kind: CategoryKind.income);
    await tester.tap(find.text(categoryFormKindExpense));
    await tester.pump();
    await _type(tester, 'Игры');
    await _save(tester);
    expect(repository.all.last.kind, CategoryKind.expense);
  });

  testWidgets('выбранная иконка сохраняется', (tester) async {
    await _openForm(tester, repository);

    await tester.ensureVisible(_icon('movie'));
    await tester.tap(_icon('movie'));
    await tester.pump();
    await _type(tester, 'Кино');
    await _save(tester);

    expect(repository.all.last.iconKey, 'movie');
  });

  testWidgets('пустое имя: текст под полем, ничего не записано', (
    tester,
  ) async {
    await _openForm(tester, repository);

    await _type(tester, '   ');
    await _save(tester);

    expect(
      find.text(categoryRuleMessage(CategoryRule.emptyName)),
      findsOneWidget,
    );
    expect(_formIsOpen(), isTrue);
    expect(repository.writes, 0);
    expect(repository.all, hasLength(4));
  });

  testWidgets('длинное имя обрезается до 40 символов, счётчик показывает это', (
    tester,
  ) async {
    await _openForm(tester, repository);
    expect(find.text('0/$categoryNameMaxLength'), findsOneWidget);

    await _type(tester, List.filled(45, 'я').join());
    expect(find.text('40/$categoryNameMaxLength'), findsOneWidget);
    await _save(tester);

    expect(repository.all.last.name, List.filled(40, 'я').join());
  });

  testWidgets('слишком длинное имя от репозитория: текст под полем', (
    tester,
  ) async {
    repository.failWith = CategoryRuleException(CategoryRule.nameTooLong);
    await _openForm(tester, repository);

    await _type(tester, 'Кино');
    await _save(tester);

    expect(
      find.text(categoryRuleMessage(CategoryRule.nameTooLong)),
      findsOneWidget,
    );
    expect(_formIsOpen(), isTrue);
  });

  testWidgets('дубль имени: текст под полем, экран остаётся, ввод очищает '
      'ошибку', (tester) async {
    await _openForm(tester, repository);

    await _type(tester, ' кафе ');
    await _save(tester);

    final message = categoryRuleMessage(CategoryRule.duplicateName);
    expect(find.text(message), findsOneWidget);
    expect(_formIsOpen(), isTrue);
    expect(repository.all, hasLength(4));

    await _type(tester, 'Кафе 2');
    expect(find.text(message), findsNothing);
    await _save(tester);
    expect(_formIsOpen(), isFalse);
    expect(repository.all.last.name, 'Кафе 2');
  });

  testWidgets('правка: имя и значок меняются, вид и порядок нет', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final cafe = repository.all.firstWhere((c) => c.id == 'cafe');
    await _openForm(tester, repository, renaming: cafe);

    expect(find.text(categoryFormEditTitle), findsOneWidget);
    expect(find.text('Кафе'), findsOneWidget);
    expect(find.byType(SegmentedButton<CategoryKind>), findsNothing);
    expect(find.text('Тип: Расход'), findsOneWidget);
    // Текущий значок выбран, остальные нет.
    expect(isSelected(tester, 'restaurant'), isTrue);
    expect(isSelected(tester, 'movie'), isFalse);

    await _type(tester, 'Ресторан');
    await tester.ensureVisible(_icon('movie'));
    await tester.pump();
    await tester.tap(_icon('movie'));
    await tester.pump();
    expect(isSelected(tester, 'movie'), isTrue);
    expect(isSelected(tester, 'restaurant'), isFalse);
    await _save(tester);

    expect(_formIsOpen(), isFalse);
    final edited = repository.all.firstWhere((c) => c.id == 'cafe');
    expect(edited.name, 'Ресторан');
    expect(edited.iconKey, 'movie');
    expect(edited.kind, CategoryKind.expense);
    expect(edited.sortOrder, 1);
    expect(repository.all, hasLength(4));
    handle.dispose();
  });

  testWidgets('правка только имени: значок прежний', (tester) async {
    final cafe = repository.all.firstWhere((c) => c.id == 'cafe');
    await _openForm(tester, repository, renaming: cafe);

    await _type(tester, 'Ресторан');
    await _save(tester);

    final edited = repository.all.firstWhere((c) => c.id == 'cafe');
    expect(edited.name, 'Ресторан');
    expect(edited.iconKey, 'restaurant');
  });

  testWidgets(
    'правка: неизвестный ключ — ничего не выбрано, ключ сохраняется',
    (tester) async {
      final handle = tester.ensureSemantics();
      final odd = _c('odd', 'Странная', 7, iconKey: 'no_such_icon');
      final repo = _repo([..._fixture(), odd]);
      addTearDown(repo.dispose);
      await _openForm(tester, repo, renaming: odd);

      await tester.ensureVisible(_icon('movie'));
      expect(isSelected(tester, 'movie'), isFalse);
      expect(isSelected(tester, 'restaurant'), isFalse);

      await _type(tester, 'Странная 2');
      await _save(tester);

      final edited = repo.all.firstWhere((c) => c.id == 'odd');
      expect(edited.name, 'Странная 2');
      expect(edited.iconKey, 'no_such_icon');
      handle.dispose();
    },
  );

  testWidgets('правка: сетка прокручена к выбранному значку glyph:Я', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final ya = _c('ya', 'Яблоки', 8, iconKey: 'glyph:Я');
    final repo = _repo([..._fixture(), ya]);
    addTearDown(repo.dispose);
    await _openForm(tester, repo, renaming: ya);

    final rect = tester.getRect(_icon('glyph:Я'));
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(740));
    expect(isSelected(tester, 'glyph:Я'), isTrue);
    handle.dispose();
  });

  testWidgets(
    'новая подкатегория: сетка прокручена к значку родителя glyph:Я',
    (tester) async {
      final handle = tester.ensureSemantics();
      final ya = _c('ya', 'Яблоки', 8, iconKey: 'glyph:Я');
      final repo = _repo([..._fixture(), ya]);
      addTearDown(repo.dispose);
      await _openForm(tester, repo, kind: ya.kind, parent: ya);

      final rect = tester.getRect(_icon('glyph:Я'));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(740));
      expect(isSelected(tester, 'glyph:Я'), isTrue);
      handle.dispose();
    },
  );

  testWidgets('правка: дубль имени — ошибка под полем, выбранный значок '
      'остаётся', (tester) async {
    final handle = tester.ensureSemantics();
    final cafe = repository.all.firstWhere((c) => c.id == 'cafe');
    await _openForm(tester, repository, renaming: cafe);

    await tester.ensureVisible(_icon('movie'));
    await tester.tap(_icon('movie'));
    await tester.pump();
    await _type(tester, 'продукты');
    await _save(tester);

    expect(
      find.text(categoryRuleMessage(CategoryRule.duplicateName)),
      findsOneWidget,
    );
    expect(_formIsOpen(), isTrue);
    expect(isSelected(tester, 'movie'), isTrue);
    expect(
      repository.all.firstWhere((c) => c.id == 'cafe').iconKey,
      'restaurant',
    );
    handle.dispose();
  });

  testWidgets('правка: 360 dp и шрифт 200 % без переполнения', (tester) async {
    final cafe = repository.all.firstWhere((c) => c.id == 'cafe');
    await _openForm(tester, repository, renaming: cafe, textScale: 2);
    await tester.ensureVisible(_icon(categoryIconKeys.last));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('переименование доходной категории: «Тип: Доход»', (
    tester,
  ) async {
    final salary = repository.all.firstWhere((c) => c.id == 'salary');
    await _openForm(tester, repository, renaming: salary);

    expect(find.text('Тип: Доход'), findsOneWidget);
    expect(find.text('Тип: Расход'), findsNothing);
  });

  testWidgets('при создании подпись выбора называется «Тип»', (tester) async {
    await _openForm(tester, repository);

    expect(find.text('Тип'), findsOneWidget);
    expect(find.text('Вид'), findsNothing);
    expect(find.byType(SegmentedButton<CategoryKind>), findsOneWidget);
  });

  testWidgets('поле названия сразу в фокусе: при создании и переименовании', (
    tester,
  ) async {
    bool nameHasFocus() =>
        tester.widget<TextField>(find.byType(TextField)).focusNode?.hasFocus ??
        tester
            .state<EditableTextState>(find.byType(EditableText))
            .widget
            .focusNode
            .hasFocus;

    await _openForm(tester, repository);
    expect(nameHasFocus(), isTrue);

    await tester.pumpWidget(const SizedBox());
    final cafe = repository.all.firstWhere((c) => c.id == 'cafe');
    await _openForm(tester, repository, renaming: cafe);
    expect(nameHasFocus(), isTrue);
  });

  testWidgets('переименование в занятое имя: сообщение о дубле', (
    tester,
  ) async {
    final cafe = repository.all.firstWhere((c) => c.id == 'cafe');
    await _openForm(tester, repository, renaming: cafe);

    await _type(tester, 'продукты');
    await _save(tester);

    expect(
      find.text(categoryRuleMessage(CategoryRule.duplicateName)),
      findsOneWidget,
    );
    expect(_formIsOpen(), isTrue);
    expect(repository.all.firstWhere((c) => c.id == 'cafe').name, 'Кафе');
  });

  testWidgets('«Назад» без сохранения ничего не меняет', (tester) async {
    await _openForm(tester, repository);
    await _type(tester, 'Кино');

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(_formIsOpen(), isFalse);
    expect(find.text('open'), findsOneWidget);
    expect(repository.writes, 0);
    expect(repository.all, _fixture());
  });

  testWidgets('сбой записи: общий текст, экран остаётся, повтор работает', (
    tester,
  ) async {
    repository.failWith = Exception('disk');
    await _openForm(tester, repository);
    await _type(tester, 'Кино');
    await _save(tester);

    expect(find.text(categorySaveFailedText), findsOneWidget);
    expect(_formIsOpen(), isTrue);
    expect(tester.takeException(), isNull);

    repository.failWith = null;
    await _save(tester);
    expect(_formIsOpen(), isFalse);
    expect(repository.all.last.name, 'Кино');
  });

  testWidgets('двойной тап по «Сохранить» — одна запись', (tester) async {
    final slow = _SlowRepository(_fixture());
    addTearDown(slow.dispose);
    await _openForm(tester, slow);
    await _type(tester, 'Кино');

    await tester.tap(find.text(categoryFormSaveLabel));
    await tester.pump();
    await tester.tap(find.text(categoryFormSaveLabel), warnIfMissed: false);
    await tester.pump();
    slow.gate.complete();
    await tester.pumpAndSettle();

    expect(slow.started, 1);
    expect(slow.all.where((c) => c.name == 'Кино'), hasLength(1));
    expect(_formIsOpen(), isFalse);
  });

  testWidgets('экран закрыт во время записи: без ошибок и без лишнего '
      'закрытия', (tester) async {
    final slow = _SlowRepository(_fixture());
    addTearDown(slow.dispose);
    await _openForm(tester, slow);
    await _type(tester, 'Кино');
    await tester.tap(find.text(categoryFormSaveLabel));
    await tester.pump();

    await tester.pageBack();
    await tester.pumpAndSettle();
    slow.gate.complete();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // «Главная» на месте: чужой экран не закрыт.
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('шрифт 200 %: без переполнения, «Сохранить» достижима', (
    tester,
  ) async {
    await _openForm(tester, repository, textScale: 2);

    expect(tester.takeException(), isNull);
    await _type(tester, 'Очень длинное название категории для проверки');
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(_icon(categoryIconKeys.last));
    await tester.tap(_icon(categoryIconKeys.last));
    await _save(tester);

    expect(_formIsOpen(), isFalse);
    expect(repository.all.last.iconKey, categoryIconKeys.last);
  });

  testWidgets('иконки: подписи для скринридера и зона от 48 dp', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _openForm(tester, repository);

    final first = categoryIconKeys.first;
    expect(
      find.bySemanticsLabel(categoryFormIconLabel(categoryIconName(first))),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        categoryFormIconLabel(categoryIconName('local_cafe')),
      ),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(RegExp('выбрана')), findsNothing);

    for (final key in categoryIconKeys) {
      final size = tester.getSize(_icon(key));
      expect(size.width, greaterThanOrEqualTo(48), reason: key);
      expect(size.height, greaterThanOrEqualTo(48), reason: key);
    }

    await tester.ensureVisible(_icon('local_cafe'));
    await tester.tap(_icon('local_cafe'));
    await tester.pump();
    expect(find.bySemanticsLabel('Иконка: Кофе'), findsOneWidget);
    expect(find.bySemanticsLabel('Иконка: Корзина'), findsOneWidget);
    expect(
      tester.getSemantics(_icon('local_cafe')),
      isSemantics(
        label: 'Иконка: Кофе',
        isButton: true,
        isSelected: true,
        hasTapAction: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('сетка иконок: ячейки одной ширины, столбцы на одном x', (
    tester,
  ) async {
    await _openForm(tester, repository);

    // 360 - 32 (поля) = 328 dp -> 5 столбцов по 65 dp.
    final cells = [
      for (final key in categoryIconGroups.first.keys)
        tester.getRect(
          find.ancestor(of: _icon(key), matching: find.byType(SizedBox)).first,
        ),
    ];
    final width = cells.first.width;
    expect(width, greaterThanOrEqualTo(56));
    for (final r in cells) {
      expect(r.width, width);
    }
    const columns = 5;
    for (var i = columns; i < cells.length; i++) {
      expect(cells[i].left, cells[i - columns].left, reason: 'иконка $i');
    }
    expect(
      tester.getTopLeft(_icon(categoryIconGroups.first.keys[columns])).dx,
      tester.getTopLeft(_icon(categoryIconGroups.first.keys.first)).dx,
    );
  });

  testWidgets('сетка иконок: подсказка с названием значка', (tester) async {
    await _openForm(tester, repository);

    final tooltip = find.descendant(
      of: _icon('local_cafe'),
      matching: find.byType(Tooltip),
    );
    expect(tooltip, findsOneWidget);
    expect(tester.widget<Tooltip>(tooltip).message, 'Кофе');
  });

  testWidgets('сетка иконок: 360 dp и шрифт 200 % без переполнения', (
    tester,
  ) async {
    await _openForm(tester, repository, textScale: 2);
    await tester.ensureVisible(_icon(categoryIconKeys.last));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(_icon(categoryIconKeys.last), findsOneWidget);
  });

  testWidgets('сетка иконок: заголовки групп по порядку и как заголовки', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _openForm(tester, repository);

    var previousTop = double.negativeInfinity;
    for (final group in categoryIconGroups) {
      final title = find.text(group.title);
      expect(title, findsOneWidget, reason: group.title);
      await tester.ensureVisible(title);
      await tester.pump();
      expect(
        tester.getSemantics(title),
        matchesSemantics(label: group.title, isHeader: true),
        reason: group.title,
      );
      // Порядок в прокрутке: каждый следующий заголовок ниже по списку.
      final scrollable = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      final offset = scrollable.position.pixels;
      expect(offset, greaterThanOrEqualTo(previousTop));
      previousTop = offset;
    }
    handle.dispose();
  });

  testWidgets('прокрутка до последней группы, выбор значка из неё', (
    tester,
  ) async {
    await _openForm(tester, repository);
    await _type(tester, 'Штрафы');

    await tester.ensureVisible(_icon('gavel'));
    await tester.tap(_icon('gavel'));
    await _save(tester);

    expect(_formIsOpen(), isFalse);
    expect(repository.all.last.iconKey, 'gavel');
  });

  testWidgets('буквы и цифры в конце сетки: выбор символа сохраняется', (
    tester,
  ) async {
    await _openForm(tester, repository);
    await _type(tester, 'Буква');

    for (final title in ['Русские буквы', 'Латинские буквы', 'Цифры']) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
    expect(
      tester.getTopLeft(find.text('Русские буквы')).dy,
      greaterThan(tester.getTopLeft(find.text('Семья и разное')).dy),
    );

    await tester.ensureVisible(_icon('glyph:Ж'));
    await tester.tap(_icon('glyph:Ж'));
    await tester.pump();
    await _save(tester);

    expect(_formIsOpen(), isFalse);
    expect(repository.all.last.iconKey, 'glyph:Ж');
  });

  testWidgets('символ: подпись для скринридера, selected один раз', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _openForm(tester, repository);

    await tester.ensureVisible(_icon('glyph:D'));
    await tester.pump();
    expect(find.bySemanticsLabel('Иконка: Латинская буква D'), findsOneWidget);
    await tester.tap(_icon('glyph:D'));
    await tester.pump();

    expect(find.bySemanticsLabel('Иконка: Латинская буква D'), findsOneWidget);
    expect(
      tester.getSemantics(_icon('glyph:D')),
      isSemantics(
        label: 'Иконка: Латинская буква D',
        isButton: true,
        isSelected: true,
        hasTapAction: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('символ: подсказка при долгом нажатии', (tester) async {
    await _openForm(tester, repository);
    await tester.ensureVisible(_icon('glyph:Ж'));
    await tester.pump();

    final tooltip = find.descendant(
      of: _icon('glyph:Ж'),
      matching: find.byType(Tooltip),
    );
    expect(tester.widget<Tooltip>(tooltip).message, 'Буква Ж');
    await tester.longPress(_icon('glyph:Ж'));
    await tester.pump();
    expect(find.text('Буква Ж'), findsOneWidget);
  });

  testWidgets('группы: 360 dp и шрифт 200 % без переполнения', (tester) async {
    await _openForm(tester, repository, textScale: 2);
    await tester.ensureVisible(find.text(categoryIconGroups.last.title));
    await tester.pump();
    expect(tester.takeException(), isNull);
    for (final group in categoryIconGroups) {
      await tester.ensureVisible(find.text(group.title));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: group.title);
    }
  });
}
