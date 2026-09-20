import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/database/app_database.dart';
import 'package:money_app/core/errors/data_corrupted_exception.dart';
import 'package:money_app/features/categories/data/category_mapper.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';

void main() {
  CategoryRow row({
    String id = 'row-1',
    String kind = 'expense',
    String name = 'Food',
    String iconKey = 'icon',
    String? parentId,
    int sortOrder = 0,
    int? archivedAt,
  }) {
    return CategoryRow(
      id: id,
      kind: kind,
      name: name,
      iconKey: iconKey,
      parentId: parentId,
      sortOrder: sortOrder,
      archivedAt: archivedAt,
      createdAt: 1,
      updatedAt: 1,
    );
  }

  group('category kind <-> database value', () {
    test('income and expense round-trip', () {
      expect(categoryKindToDb(CategoryKind.income), 'income');
      expect(categoryKindToDb(CategoryKind.expense), 'expense');
      expect(categoryKindFromDb('income'), CategoryKind.income);
      expect(categoryKindFromDb('expense'), CategoryKind.expense);
    });

    test('an unknown value is a FormatException', () {
      expect(() => categoryKindFromDb('transfer'), throwsFormatException);
      expect(() => categoryKindFromDb('Income'), throwsFormatException);
    });
  });

  group('categoryFromRow', () {
    test('maps every field, archivedAt becomes UTC', () {
      final category = categoryFromRow(
        row(
          kind: 'income',
          parentId: 'p',
          sortOrder: 3,
          archivedAt: 1700000000000,
        ),
      );

      expect(category.id, 'row-1');
      expect(category.kind, CategoryKind.income);
      expect(category.name, 'Food');
      expect(category.parentId, 'p');
      expect(category.sortOrder, 3);
      expect(category.archivedAt, DateTime.utc(2023, 11, 14, 22, 13, 20));
      expect(category.archivedAt!.isUtc, isTrue);
    });

    test('an unknown kind is DataCorruptedException with the row id', () {
      expect(
        () => categoryFromRow(row(kind: 'transfer')),
        throwsA(
          isA<DataCorruptedException>()
              .having((e) => e.message, 'message', contains('row-1'))
              .having((e) => e.cause, 'cause', isA<FormatException>()),
        ),
      );
    });

    test('a broken name is DataCorruptedException', () {
      expect(
        () => categoryFromRow(row(name: '')),
        throwsA(isA<DataCorruptedException>()),
      );
      expect(
        () => categoryFromRow(row(name: 'x' * 41)),
        throwsA(isA<DataCorruptedException>()),
      );
    });
  });

  group('categoryToCompanion', () {
    test('writes kind, times and archivedAt as integers', () {
      final companion = categoryToCompanion(
        Category(
          id: 'c',
          kind: CategoryKind.income,
          name: 'Salary',
          iconKey: 'wallet',
          parentId: 'p',
          sortOrder: 2,
          archivedAt: DateTime.utc(2026, 1, 1),
        ),
        createdAt: DateTime.utc(2026, 1, 2),
        updatedAt: DateTime.utc(2026, 1, 3),
      );

      expect(companion.kind.value, 'income');
      expect(companion.parentId.value, 'p');
      expect(companion.sortOrder.value, 2);
      expect(
        companion.archivedAt.value,
        DateTime.utc(2026, 1, 1).millisecondsSinceEpoch,
      );
      expect(
        companion.createdAt.value,
        DateTime.utc(2026, 1, 2).millisecondsSinceEpoch,
      );
      expect(
        companion.updatedAt.value,
        DateTime.utc(2026, 1, 3).millisecondsSinceEpoch,
      );
    });
  });
}
