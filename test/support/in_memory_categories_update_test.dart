import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/categories/domain/category_rules.dart';

import 'fakes.dart';

void main() {
  group('InMemoryCategoriesRepository.update', () {
    Category top(String id, String name, String icon) => Category.topLevel(
      id: id,
      kind: CategoryKind.expense,
      name: name,
      iconKey: icon,
      sortOrder: 0,
    );

    Category child(String id, String parentId, String icon) => Category(
      id: id,
      kind: CategoryKind.expense,
      name: 'Name $id',
      iconKey: icon,
      parentId: parentId,
      sortOrder: 0,
    );

    test('changes name and icon; children with old icon follow', () async {
      final repo = InMemoryCategoriesRepository([
        top('p', 'Food', 'a'),
        child('same', 'p', 'a'),
        child('own', 'p', 'b'),
        top('q', 'Fun', 'a'),
        child('foreign', 'q', 'a'),
      ]);
      addTearDown(repo.dispose);

      await repo.update('p', newName: ' Eat ', iconKey: 'z');

      String icon(String id) => repo.all.firstWhere((c) => c.id == id).iconKey;
      expect(repo.all.firstWhere((c) => c.id == 'p').name, 'Eat');
      expect(icon('p'), 'z');
      expect(icon('same'), 'z');
      expect(icon('own'), 'b');
      expect(icon('foreign'), 'a');
      expect(repo.writes, 1);
    });

    test('watchAll emits the new icon', () async {
      final repo = InMemoryCategoriesRepository([top('p', 'Food', 'a')]);
      addTearDown(repo.dispose);

      final next = repo.watchAll().skip(1).first;
      await repo.update('p', newName: 'Food', iconKey: 'z');

      expect((await next).single.iconKey, 'z');
    });

    test('unknown id is ArgumentError', () async {
      final repo = InMemoryCategoriesRepository([top('p', 'Food', 'a')]);
      addTearDown(repo.dispose);

      await expectLater(
        repo.update('nope', newName: 'X', iconKey: 'z'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('empty icon is checked before duplicate name', () async {
      final repo = InMemoryCategoriesRepository([
        top('p', 'Food', 'a'),
        top('q', 'Fun', 'a'),
      ]);
      addTearDown(repo.dispose);

      await expectLater(
        repo.update('p', newName: 'Fun', iconKey: '  '),
        throwsA(
          isA<CategoryRuleException>().having(
            (e) => e.rule,
            'rule',
            CategoryRule.emptyIconKey,
          ),
        ),
      );
      expect(repo.all.first.iconKey, 'a');
    });

    test('duplicate name is rejected', () async {
      final repo = InMemoryCategoriesRepository([
        top('p', 'Food', 'a'),
        top('q', 'Fun', 'a'),
      ]);
      addTearDown(repo.dispose);

      await expectLater(
        repo.update('p', newName: 'fun', iconKey: 'z'),
        throwsA(
          isA<CategoryRuleException>().having(
            (e) => e.rule,
            'rule',
            CategoryRule.duplicateName,
          ),
        ),
      );
      expect(repo.all.first.iconKey, 'a');
    });
  });
}
