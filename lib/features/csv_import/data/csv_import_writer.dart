import 'package:money_app/core/database/app_database.dart';
import 'package:money_app/core/id/id_generator.dart';
import 'package:money_app/features/accounts/domain/accounts_repository.dart';
import 'package:money_app/features/categories/domain/categories_repository.dart';
import 'package:money_app/features/csv_import/domain/csv_import_store.dart';
import 'package:money_app/features/csv_import/domain/parse_csv_import.dart';
import 'package:money_app/features/csv_import/domain/plan_csv_import.dart';
import 'package:money_app/features/transactions/domain/transactions_repository.dart';

/// Подготовка и запись импорта CSV (ADR 0009, п. 6).
///
/// Репозитории обязаны работать с той же [AppDatabase]: вложенная транзакция
/// drift присоединяется к внешней, поэтому откат отменяет всё сразу.
class CsvImportWriter implements CsvImportStore {
  CsvImportWriter({
    required this._db,
    required this._categories,
    required this._accounts,
    required this._transactions,
    required this._ids,
    required this._isKnownIconKey,
  });

  final AppDatabase _db;
  final CategoriesRepository _categories;
  final AccountsRepository _accounts;
  final TransactionsRepository _transactions;
  final IdGenerator _ids;

  /// Знает ли приложение значок (список значков живёт в `core/ui`).
  final bool Function(String iconKey) _isKnownIconKey;

  /// Читает из базы всё нужное и строит план. В базу ничего не пишет.
  @override
  Future<CsvImportPlan> prepare(
    List<ParsedCsvRow> rows, {
    List<ParsedOpeningBalance> openingBalances = const [],
  }) async {
    final categories = await _categories.watchAll().first;
    final accounts = await _accounts.watchAll().first;

    final acc = _db.accounts;
    final deletedAccounts =
        await (_db.selectOnly(acc)
              ..addColumns([acc.id])
              ..where(acc.deletedAt.isNotNull()))
            .map((row) => row.read(acc.id)!)
            .get();

    final cat = _db.categories;
    final deletedCategories =
        await (_db.selectOnly(cat)
              ..addColumns([cat.id])
              ..where(cat.deletedAt.isNotNull()))
            .map((row) => row.read(cat.id)!)
            .get();

    final tx = _db.transactions;
    final txRows = await (_db.selectOnly(
      tx,
    )..addColumns([tx.id, tx.deletedAt])).get();
    final live = <String>{};
    final deleted = <String>{};
    for (final row in txRows) {
      (row.read(tx.deletedAt) == null ? live : deleted).add(row.read(tx.id)!);
    }

    return planCsvImport(
      rows: rows,
      categories: categories,
      liveTransactionIds: live,
      deletedTransactionIds: deleted,
      deletedCategoryIds: deletedCategories.toSet(),
      ids: _ids,
      isKnownIconKey: _isKnownIconKey,
      openingBalances: openingBalances,
      accounts: accounts,
      deletedAccountIds: deletedAccounts.toSet(),
    );
  }

  /// Пишет [plan] одной транзакцией: сначала счета, потом категории и
  /// операции. Основным счёт не становится.
  /// Любая ошибка (в том числе уже существующий id операции) откатывает всё
  /// и выходит наружу. Пустой план ничего не делает.
  @override
  Future<void> write(CsvImportPlan plan) async {
    if (plan.errors.isNotEmpty) {
      throw StateError('Нельзя записывать план с ошибками');
    }
    if (plan.accountsToCreate.isEmpty &&
        plan.categoriesToCreate.isEmpty &&
        plan.transactions.isEmpty) {
      return;
    }
    await _db.transaction(() async {
      for (final account in plan.accountsToCreate) {
        await _accounts.create(account);
      }
      for (final category in plan.categoriesToCreate) {
        await _categories.create(category);
      }
      for (final transaction in plan.transactions) {
        // Отдельный метод: он разрешает архивные категории (история).
        await _transactions.addImported(transaction);
      }
    });
  }
}
