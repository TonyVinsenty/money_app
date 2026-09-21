import 'dart:async';

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

  testWidgets('переименование: только имя, вид и иконка не трогаются', (
    tester,
  ) async {
    final cafe = repository.all.firstWhere((c) => c.id == 'cafe');
    await _openForm(tester, repository, renaming: cafe);

    expect(find.text(categoryFormRenameTitle), findsOneWidget);
    expect(find.text('Кафе'), findsOneWidget);
    expect(find.byType(SegmentedButton<CategoryKind>), findsNothing);
    expect(_icon('movie'), findsNothing);

    await _type(tester, 'Ресторан');
    await _save(tester);

    expect(_formIsOpen(), isFalse);
    final renamed = repository.all.firstWhere((c) => c.id == 'cafe');
    expect(renamed.name, 'Ресторан');
    expect(renamed.iconKey, 'restaurant');
    expect(renamed.kind, CategoryKind.expense);
    expect(renamed.sortOrder, 1);
    expect(repository.all, hasLength(4));
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
      find.bySemanticsLabel(
        categoryFormIconLabel(categoryIconName(first), selected: true),
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        categoryFormIconLabel(categoryIconName('local_cafe'), selected: false),
      ),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Иконка: Кофе, выбрана'), findsNothing);

    for (final key in categoryIconKeys) {
      final size = tester.getSize(_icon(key));
      expect(size.width, greaterThanOrEqualTo(48), reason: key);
      expect(size.height, greaterThanOrEqualTo(48), reason: key);
    }

    await tester.ensureVisible(_icon('local_cafe'));
    await tester.tap(_icon('local_cafe'));
    await tester.pump();
    expect(find.bySemanticsLabel('Иконка: Кофе, выбрана'), findsOneWidget);
    expect(find.bySemanticsLabel('Иконка: Корзина'), findsOneWidget);
    expect(
      tester.getSemantics(_icon('local_cafe')),
      isSemantics(
        label: 'Иконка: Кофе, выбрана',
        isButton: true,
        isSelected: true,
        hasTapAction: true,
      ),
    );
    handle.dispose();
  });
}
