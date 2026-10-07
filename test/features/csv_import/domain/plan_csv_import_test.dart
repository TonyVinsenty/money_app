import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/id/id_generator.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/csv_import/domain/csv_import_failures.dart';
import 'package:money_app/features/csv_import/domain/parse_csv_import.dart';
import 'package:money_app/features/csv_import/domain/plan_csv_import.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

final class _SeqIds implements IdGenerator {
  var _n = 0;

  @override
  String newId() => 'new-${++_n}';
}

const _food = 'cat-food';
const _salary = 'cat-salary';
const _sub = 'sub-cafe';

Category _top(
  String id,
  CategoryKind kind,
  String name, {
  bool archived = false,
}) {
  final c = Category.topLevel(
    id: id,
    kind: kind,
    name: name,
    iconKey: 'x',
    sortOrder: 3,
  );
  return archived ? c.archived(DateTime.utc(2026, 1, 1)) : c;
}

Category _child(String id, Category parent, String name) =>
    Category.subcategoryOf(
      id: id,
      parent: parent,
      name: name,
      iconKey: 'x',
      sortOrder: 0,
    );

ParsedCsvRow _row({
  int line = 2,
  TransactionType type = TransactionType.expense,
  int amount = 10000,
  String category = 'Еда',
  String? sub,
  String? note,
  String? id,
  String? categoryId,
  String? subcategoryId,
}) {
  return ParsedCsvRow(
    line: line,
    day: DateOnly(2026, 10, 1),
    occurredAt: DateTime.utc(2026, 10, 1, 9),
    type: type,
    amount: Money.fromMinor(amount, 'RUB'),
    categoryName: category,
    subcategoryName: sub,
    note: note,
    transactionId: id,
    categoryId: categoryId,
    subcategoryId: subcategoryId,
  );
}

CsvImportPlan _plan(
  List<ParsedCsvRow> rows, {
  List<Category>? categories,
  Set<String> live = const {},
  Set<String> deleted = const {},
}) {
  return planCsvImport(
    rows: rows,
    categories: categories ?? [_top(_food, CategoryKind.expense, 'Еда')],
    liveTransactionIds: live,
    deletedTransactionIds: deleted,
    ids: _SeqIds(),
  );
}

void main() {
  test('id из файла совпал с id мягко удалённой категории: id новый', () {
    final plan = planCsvImport(
      rows: [_row(category: 'Кафе', categoryId: 'gone-1')],
      categories: [_top(_food, CategoryKind.expense, 'Еда')],
      liveTransactionIds: const {},
      deletedTransactionIds: const {},
      deletedCategoryIds: const {'GONE-1'},
      ids: _SeqIds(),
    );
    expect(plan.categoriesToCreate.single.id, 'new-1');
    expect(plan.transactions.single.categoryId, 'new-1');
  });

  test('новые строки добавляются в существующую категорию по имени', () {
    final plan = _plan([_row(category: ' еда ')]);
    expect(plan.transactions.single.categoryId, _food);
    expect(plan.categoriesToCreate, isEmpty);
    expect(plan.errors, isEmpty);
  });

  test('повторный импорт: строки с ID и без ID не добавляются снова', () {
    final rows = [
      _row(id: 'AAAAAAAA-0000-4000-8000-000000000001'),
      _row(amount: 500, note: 'без id'),
      _row(amount: 500, note: 'без id'),
    ];
    final first = _plan(rows);
    expect(first.transactions, hasLength(3));
    final second = _plan(
      rows,
      live: {for (final t in first.transactions) t.id},
    );
    expect(second.transactions, isEmpty);
    expect(second.skippedExisting, 3);
  });

  test('две одинаковые покупки в день остаются двумя разными id', () {
    final plan = _plan([_row(amount: 700), _row(amount: 700)]);
    expect(plan.transactions, hasLength(2));
    expect(plan.transactions[0].id, isNot(plan.transactions[1].id));
  });

  test('отпечаток не зависит от регистра и пробелов в имени категории', () {
    final a = _plan([_row(category: 'Еда')]).transactions.single.id;
    final b = _plan([_row(category: '  ЕДА ')]).transactions.single.id;
    expect(a, b);
  });

  test('удалённая в приложении операция пропускается отдельным счётчиком', () {
    final plan = _plan(
      [_row(id: '0199aaaa-bbbb-7ccc-8ddd-eeeeeeeeeee1')],
      deleted: {'0199aaaa-bbbb-7ccc-8ddd-eeeeeeeeeee1'},
    );
    expect(plan.transactions, isEmpty);
    expect(plan.skippedDeleted, 1);
    expect(plan.skippedExisting, 0);
  });

  test('одноимённые категории дохода и расхода разные', () {
    final plan = _plan([
      _row(category: 'Прочее'),
      _row(type: TransactionType.income, category: 'Прочее'),
    ]);
    expect(plan.categoriesToCreate.map((c) => c.kind), [
      CategoryKind.expense,
      CategoryKind.income,
    ]);
    expect(
      plan.transactions[0].categoryId,
      isNot(plan.transactions[1].categoryId),
    );
  });

  test('одна новая категория в многих строках создаётся один раз', () {
    final plan = _plan([
      _row(category: 'Спорт', sub: 'Зал'),
      _row(category: 'спорт', sub: 'зал', amount: 5),
    ]);
    expect(plan.categoriesToCreate.map((c) => c.name), ['Спорт', 'Зал']);
    expect(plan.categoriesToCreate[1].parentId, plan.categoriesToCreate[0].id);
    expect(plan.transactions[1].subcategoryId, plan.categoriesToCreate[1].id);
  });

  test('категория создаётся с id из файла, если он свободен', () {
    const fileId = 'AAAAAAAA-0000-4000-8000-0000000000AA';
    final plan = _plan([_row(category: 'Спорт', categoryId: fileId)]);
    expect(plan.categoriesToCreate.single.id, fileId.toLowerCase());
    expect(plan.transactions.single.categoryId, fileId.toLowerCase());
  });

  test('id из файла занят - категория получает новый id', () {
    final plan = _plan(
      [_row(category: 'Спорт', categoryId: 'unknown-but-taken')],
      categories: [_top(_food, CategoryKind.expense, 'Еда')],
    );
    // Свободный id берётся из файла...
    expect(plan.categoriesToCreate.single.id, 'unknown-but-taken');
    // ...а занятый другой строкой того же импорта заменяется новым.
    final second = _plan([
      _row(category: 'Спорт', categoryId: 'dup-id'),
      _row(category: 'Кино', categoryId: 'dup-id'),
    ]);
    expect(second.categoriesToCreate.map((c) => c.id), ['dup-id', 'new-1']);
  });

  test('id категории с чужим видом - ошибка строки', () {
    final plan = _plan(
      [_row(line: 5, categoryId: _salary)],
      categories: [_top(_salary, CategoryKind.income, 'Зарплата')],
    );
    expect(plan.errors.single, isA<CsvCategoryKindMismatch>());
    expect(plan.errors.single.line, 5);
    expect(plan.transactions, isEmpty);
    expect(plan.categoriesToCreate, isEmpty);
  });

  test('id категории указывает на подкатегорию - ошибка строки', () {
    final food = _top(_food, CategoryKind.expense, 'Еда');
    final plan = _plan(
      [_row(categoryId: _sub)],
      categories: [food, _child(_sub, food, 'Кафе')],
    );
    expect(plan.errors.single, isA<CsvCategoryIdIsSubcategory>());
  });

  test('подкатегория чужого родителя - ошибка строки', () {
    final food = _top(_food, CategoryKind.expense, 'Еда');
    final home = _top('cat-home', CategoryKind.expense, 'Дом');
    final plan = _plan(
      [_row(category: 'Дом', sub: 'Кафе', subcategoryId: _sub)],
      categories: [food, home, _child(_sub, food, 'Кафе')],
    );
    expect(plan.errors.single, isA<CsvSubcategoryWrongParent>());
    expect(plan.transactions, isEmpty);
  });

  test('id подкатегории указывает на категорию верхнего уровня - ошибка', () {
    final plan = _plan([_row(sub: 'Кафе', subcategoryId: _food)]);
    expect(plan.errors.single, isA<CsvSubcategoryWrongParent>());
  });

  test('подкатегория по id своего родителя находится', () {
    final food = _top(_food, CategoryKind.expense, 'Еда');
    final plan = _plan(
      [_row(sub: 'Другое имя', categoryId: _food, subcategoryId: _sub)],
      categories: [food, _child(_sub, food, 'Кафе')],
    );
    expect(plan.errors, isEmpty);
    expect(plan.transactions.single.subcategoryId, _sub);
    expect(plan.categoriesToCreate, isEmpty);
  });

  test('архивная категория: по id - операция в неё, по имени - новая', () {
    final archived = _top(_food, CategoryKind.expense, 'Еда', archived: true);
    final byId = _plan([_row(categoryId: _food)], categories: [archived]);
    expect(byId.transactions.single.categoryId, _food);
    expect(byId.categoriesToCreate, isEmpty);

    final byName = _plan([_row()], categories: [archived]);
    expect(byName.categoriesToCreate.single.name, 'Еда');
    expect(byName.transactions.single.categoryId, isNot(_food));
  });

  test('пропущенные строки не создают категорий', () {
    final plan = _plan(
      [
        _row(
          category: 'Новая',
          sub: 'Новая под',
          id: '0199aaaa-bbbb-7ccc-8ddd-eeeeeeeeeee1',
        ),
      ],
      live: {'0199aaaa-bbbb-7ccc-8ddd-eeeeeeeeeee1'},
    );
    expect(plan.categoriesToCreate, isEmpty);
    expect(plan.skippedExisting, 1);
  });

  test('новые категории встают в конец списка своего уровня', () {
    final plan = _plan([_row(category: 'Спорт'), _row(category: 'Кино')]);
    expect(plan.categoriesToCreate.map((c) => c.sortOrder), [4, 5]);
  });
}
