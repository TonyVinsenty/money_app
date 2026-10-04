import 'package:money_app/core/database/app_database.dart';
import 'package:money_app/features/categories/data/categories_repository_impl.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/transactions/data/transactions_repository_impl.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

/// Кладёт тестовый набор операций в базу [db] (обычно в памяти).
///
/// Сначала создаются категории, которых ждут операции: id берутся из строк
/// набора, вид — из типа операции, название равно id (названий в наборе нет).
/// Затем операции записываются через `DriftTransactionsRepository.add`, то
/// есть так же, как это делает приложение, и проверки связей тоже работают.
Future<void> loadFixtureIntoDatabase(
  AppDatabase db,
  List<Transaction> transactions,
) async {
  final categories = DriftCategoriesRepository(db);
  final repo = DriftTransactionsRepository(db);

  // Порядок вставки важен: сначала категории верхнего уровня, потом
  // подкатегории (у каждой есть родитель).
  final topLevel = <String, CategoryKind>{};
  final subcategories = <String, (String parentId, CategoryKind kind)>{};
  for (final t in transactions) {
    final kind = _kindOf(t.type);
    topLevel.putIfAbsent(t.categoryId, () => kind);
    final subcategoryId = t.subcategoryId;
    if (subcategoryId != null) {
      subcategories.putIfAbsent(subcategoryId, () => (t.categoryId, kind));
    }
  }

  var sortOrder = 0;
  for (final entry in topLevel.entries) {
    await categories.create(
      Category.topLevel(
        id: entry.key,
        kind: entry.value,
        name: entry.key,
        iconKey: 'icon',
        sortOrder: sortOrder++,
      ),
    );
  }

  sortOrder = 0;
  for (final entry in subcategories.entries) {
    final (parentId, kind) = entry.value;
    await categories.create(
      Category(
        id: entry.key,
        kind: kind,
        name: entry.key,
        iconKey: 'icon',
        parentId: parentId,
        sortOrder: sortOrder++,
      ),
    );
  }

  for (final t in transactions) {
    await repo.add(t);
  }
}

CategoryKind _kindOf(TransactionType type) => switch (type) {
  TransactionType.income => CategoryKind.income,
  TransactionType.expense => CategoryKind.expense,
};
