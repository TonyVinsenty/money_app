import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/categories/domain/category_rules.dart';

void main() {
  test('максимальная длина имени равна 40', () {
    expect(categoryNameMaxLength, 40);
  });

  test('исключение хранит правило и сообщение по умолчанию', () {
    for (final rule in CategoryRule.values) {
      final e = CategoryRuleException(rule);
      expect(e.rule, rule);
      expect(e.message, isNotEmpty);
    }
  });

  test('можно передать своё сообщение', () {
    final e = CategoryRuleException(CategoryRule.emptyName, 'custom');
    expect(e.message, 'custom');
  });

  test('toString содержит имя правила и сообщение', () {
    final e = CategoryRuleException(CategoryRule.kindMismatch);
    expect(e.toString(), contains('kindMismatch'));
    expect(e.toString(), contains(e.message));
  });

  group('дубли имён', () {
    Category cat(
      String id,
      String name, {
      CategoryKind kind = CategoryKind.expense,
      String? parentId,
      DateTime? archivedAt,
    }) => Category(
      id: id,
      kind: kind,
      name: name,
      iconKey: 'icon',
      parentId: parentId,
      sortOrder: 0,
      archivedAt: archivedAt,
    );

    bool isDuplicate(
      String name,
      List<Category> existing, {
      CategoryKind kind = CategoryKind.expense,
      String? parentId,
      String? selfId,
    }) => Category.isDuplicateName(
      name: name,
      kind: kind,
      parentId: parentId,
      existing: existing,
      selfId: selfId,
    );

    test('ключ имени: без пробелов по краям и без учёта регистра', () {
      expect(categoryNameKey('  Такси '), 'такси');
      expect(categoryNameKey('ТАКСИ'), categoryNameKey('такси'));
    });

    test('регистр и пробелы по краям не важны', () {
      final existing = [cat('a', 'Такси')];
      expect(isDuplicate('Такси', existing), isTrue);
      expect(isDuplicate('такси', existing), isTrue);
      expect(isDuplicate('Такси ', existing), isTrue);
      expect(isDuplicate('Такси 2', existing), isFalse);
    });

    test('другой вид не мешает', () {
      final existing = [cat('a', 'Прочее')];
      expect(
        isDuplicate('Прочее', existing, kind: CategoryKind.income),
        isFalse,
      );
    });

    test('другой уровень и другой родитель не мешают', () {
      final existing = [cat('a', 'Такси'), cat('b', 'Такси', parentId: 'p1')];
      expect(isDuplicate('Такси', existing, parentId: 'p2'), isFalse);
      expect(isDuplicate('Такси', existing, parentId: 'p1'), isTrue);
      expect(isDuplicate('Такси', existing), isTrue);
      expect(isDuplicate('Такси', [existing[1]]), isFalse);
      expect(isDuplicate('Такси', [existing[0]], parentId: 'p1'), isFalse);
    });

    test('архивная категория не мешает', () {
      final existing = [cat('a', 'Такси', archivedAt: DateTime.utc(2026))];
      expect(isDuplicate('Такси', existing), isFalse);
    });

    test('сама себя при переименовании не считается дублем', () {
      final existing = [cat('a', 'Такси')];
      expect(isDuplicate('ТАКСИ', existing, selfId: 'a'), isFalse);
      expect(isDuplicate('ТАКСИ', existing, selfId: 'other'), isTrue);
    });

    test('checkUniqueName бросает duplicateName', () {
      expect(
        () => Category.checkUniqueName(
          name: 'такси',
          kind: CategoryKind.expense,
          parentId: null,
          existing: [cat('a', 'Такси')],
        ),
        throwsA(
          isA<CategoryRuleException>().having(
            (e) => e.rule,
            'rule',
            CategoryRule.duplicateName,
          ),
        ),
      );
    });
  });

  test('это Exception, его можно поймать по типу', () {
    expect(
      () => throw CategoryRuleException(CategoryRule.nameTooLong),
      throwsA(isA<CategoryRuleException>()),
    );
  });
}
