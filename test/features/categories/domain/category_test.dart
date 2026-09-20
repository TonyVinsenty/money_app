import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/categories/domain/category_rules.dart';

Category _top({
  String id = 'c1',
  CategoryKind kind = CategoryKind.expense,
  String name = 'Food',
  String iconKey = 'restaurant',
  int sortOrder = 0,
}) {
  return Category.topLevel(
    id: id,
    kind: kind,
    name: name,
    iconKey: iconKey,
    sortOrder: sortOrder,
  );
}

Category _sub(Category parent, {String id = 's1', String name = 'Cafe'}) {
  return Category.subcategoryOf(
    id: id,
    parent: parent,
    name: name,
    iconKey: 'coffee',
    sortOrder: 0,
  );
}

Matcher _throwsRule(CategoryRule rule) =>
    throwsA(isA<CategoryRuleException>().having((e) => e.rule, 'rule', rule));

void main() {
  group('имя', () {
    test('пустое имя запрещено', () {
      expect(() => _top(name: ''), _throwsRule(CategoryRule.emptyName));
    });

    test('имя из одних пробелов запрещено', () {
      expect(() => _top(name: '   \t '), _throwsRule(CategoryRule.emptyName));
    });

    test('имя из 40 символов допустимо', () {
      expect(_top(name: 'a' * 40).name, 'a' * 40);
    });

    test('имя из 41 символа запрещено', () {
      expect(() => _top(name: 'a' * 41), _throwsRule(CategoryRule.nameTooLong));
    });

    test('кириллица: 40 символов допустимо, 41 нет', () {
      expect(_top(name: 'ы' * 40).name, 'ы' * 40);
      expect(() => _top(name: 'ы' * 41), _throwsRule(CategoryRule.nameTooLong));
    });

    test('эмодзи считается как один символ', () {
      // Одна кодовая точка Юникода, но две единицы UTF-16.
      const emoji = '😀';
      expect(emoji.length, 2);
      expect(_top(name: emoji * 40).name, emoji * 40);
      expect(
        () => _top(name: emoji * 41),
        _throwsRule(CategoryRule.nameTooLong),
      );
    });

    test('пробелы по краям обрезаются и не считаются в длину', () {
      expect(_top(name: '  Food  ').name, 'Food');
      expect(_top(name: ' ${'a' * 40} ').name, 'a' * 40);
    });
  });

  group('ключ иконки и порядок', () {
    test('пустой iconKey запрещён', () {
      expect(() => _top(iconKey: ''), _throwsRule(CategoryRule.emptyIconKey));
      expect(() => _top(iconKey: '  '), _throwsRule(CategoryRule.emptyIconKey));
    });

    test('отрицательный sortOrder запрещён, ноль допустим', () {
      expect(
        () => _top(sortOrder: -1),
        _throwsRule(CategoryRule.negativeSortOrder),
      );
      expect(_top(sortOrder: 0).sortOrder, 0);
    });
  });

  group('способы создания', () {
    test('topLevel: родителя нет, категория не в архиве', () {
      final category = _top();
      expect(category.parentId, isNull);
      expect(category.isTopLevel, isTrue);
      expect(category.isArchived, isFalse);
      expect(category.archivedAt, isNull);
    });

    test('subcategoryOf: родитель и вид берутся от родителя', () {
      final parent = _top(kind: CategoryKind.income);
      final child = _sub(parent);
      expect(child.parentId, parent.id);
      expect(child.kind, CategoryKind.income);
      expect(child.isTopLevel, isFalse);
    });

    test('подкатегория у подкатегории запрещена', () {
      final child = _sub(_top());
      expect(
        () => _sub(child, id: 's2'),
        _throwsRule(CategoryRule.parentMustBeTopLevel),
      );
    });

    test('subcategoryOf проверяет собственные правила подкатегории', () {
      expect(
        () => Category.subcategoryOf(
          id: 's1',
          parent: _top(),
          name: ' ',
          iconKey: 'x',
          sortOrder: 0,
        ),
        _throwsRule(CategoryRule.emptyName),
      );
    });

    test('публичный конструктор восстанавливает все поля', () {
      final at = DateTime.utc(2026, 9, 20, 10);
      final category = Category(
        id: 's1',
        kind: CategoryKind.expense,
        name: ' Cafe ',
        iconKey: 'coffee',
        parentId: 'c1',
        sortOrder: 3,
        archivedAt: at,
      );
      expect(category.name, 'Cafe');
      expect(category.parentId, 'c1');
      expect(category.sortOrder, 3);
      expect(category.archivedAt, at);
      expect(category.isArchived, isTrue);
    });

    test('публичный конструктор проверяет собственные правила', () {
      expect(
        () => Category(
          id: 'x',
          kind: CategoryKind.expense,
          name: '',
          iconKey: 'a',
          parentId: null,
          sortOrder: 0,
        ),
        _throwsRule(CategoryRule.emptyName),
      );
    });
  });

  group('checkParent', () {
    test('согласованная пара проходит', () {
      final parent = _top();
      expect(() => Category.checkParent(_sub(parent), parent), returnsNormally);
    });

    test('вид не совпадает: kindMismatch', () {
      final parent = _top(kind: CategoryKind.expense);
      final child = Category(
        id: 's1',
        kind: CategoryKind.income,
        name: 'Cafe',
        iconKey: 'coffee',
        parentId: parent.id,
        sortOrder: 0,
      );
      expect(
        () => Category.checkParent(child, parent),
        _throwsRule(CategoryRule.kindMismatch),
      );
    });

    test('родитель сам подкатегория: parentMustBeTopLevel', () {
      final grandParent = _top();
      final parent = _sub(grandParent);
      final child = Category(
        id: 's2',
        kind: parent.kind,
        name: 'Deep',
        iconKey: 'x',
        parentId: parent.id,
        sortOrder: 0,
      );
      expect(
        () => Category.checkParent(child, parent),
        _throwsRule(CategoryRule.parentMustBeTopLevel),
      );
    });

    test('чужой родитель: ArgumentError', () {
      final child = _sub(_top());
      final stranger = _top(id: 'other');
      expect(() => Category.checkParent(child, stranger), throwsArgumentError);
    });

    test('категория верхнего уровня не имеет родителя: ArgumentError', () {
      expect(
        () => Category.checkParent(_top(), _top(id: 'p')),
        throwsArgumentError,
      );
    });
  });

  group('copyWith, archived, restored', () {
    test('copyWith меняет имя (с обрезкой) и сохраняет остальное', () {
      final parent = _top();
      final child = _sub(parent);
      final renamed = child.copyWith(name: '  Coffee ');
      expect(renamed.name, 'Coffee');
      expect(renamed.id, child.id);
      expect(renamed.kind, child.kind);
      expect(renamed.parentId, child.parentId);
      expect(renamed.iconKey, child.iconKey);
      expect(renamed.sortOrder, child.sortOrder);
    });

    test('copyWith меняет иконку и порядок', () {
      final changed = _top().copyWith(iconKey: 'home', sortOrder: 5);
      expect(changed.iconKey, 'home');
      expect(changed.sortOrder, 5);
    });

    test('copyWith проходит те же проверки', () {
      final category = _top();
      expect(
        () => category.copyWith(name: ' '),
        _throwsRule(CategoryRule.emptyName),
      );
      expect(
        () => category.copyWith(name: 'a' * 41),
        _throwsRule(CategoryRule.nameTooLong),
      );
      expect(
        () => category.copyWith(iconKey: ''),
        _throwsRule(CategoryRule.emptyIconKey),
      );
      expect(
        () => category.copyWith(sortOrder: -1),
        _throwsRule(CategoryRule.negativeSortOrder),
      );
    });

    test('copyWith не сбрасывает архив', () {
      final at = DateTime.utc(2026, 9, 20);
      final renamed = _top().archived(at).copyWith(name: 'New');
      expect(renamed.archivedAt, at);
    });

    test('archived ставит момент архивации, исходный объект не меняется', () {
      final original = _top();
      final at = DateTime.utc(2026, 9, 20, 12);
      final archived = original.archived(at);
      expect(archived.archivedAt, at);
      expect(archived.isArchived, isTrue);
      expect(original.isArchived, isFalse);
    });

    test('restored сбрасывает архив', () {
      final restored = _top().archived(DateTime.utc(2026, 9, 20)).restored();
      expect(restored.archivedAt, isNull);
      expect(restored.isArchived, isFalse);
      expect(restored, _top());
    });

    test('archived с не-UTC временем: ArgumentError', () {
      expect(() => _top().archived(DateTime(2026, 9, 20)), throwsArgumentError);
    });

    test('конструктор с не-UTC archivedAt: ArgumentError', () {
      expect(
        () => Category(
          id: 'x',
          kind: CategoryKind.expense,
          name: 'A',
          iconKey: 'a',
          parentId: null,
          sortOrder: 0,
          archivedAt: DateTime(2026, 9, 20),
        ),
        throwsArgumentError,
      );
    });
  });

  group('равенство', () {
    test('равные по всем полям объекты равны и дают один hashCode', () {
      final a = _top();
      final b = _top();
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('обрезанное и уже чистое имя дают равные объекты', () {
      expect(_top(name: ' Food '), _top(name: 'Food'));
    });

    test('различие в любом поле делает объекты неравными', () {
      final base = _top();
      expect(base, isNot(_top(id: 'other')));
      expect(base, isNot(_top(kind: CategoryKind.income)));
      expect(base, isNot(_top(name: 'Other')));
      expect(base, isNot(_top(iconKey: 'home')));
      expect(base, isNot(_top(sortOrder: 1)));
      expect(base, isNot(_sub(base)));
      expect(base, isNot(base.archived(DateTime.utc(2026, 9, 20))));
    });

    test('toString содержит имя и вид', () {
      final text = _top().toString();
      expect(text, contains('Food'));
      expect(text, contains('expense'));
    });
  });
}
