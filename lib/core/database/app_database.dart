import 'package:drift/drift.dart';
import 'package:money_app/core/database/converters/date_only_converter.dart';
import 'package:money_app/core/database/converters/transaction_type_converter.dart';
import 'package:money_app/core/database/tables/accounts.dart';
import 'package:money_app/core/database/tables/app_settings.dart';
import 'package:money_app/core/database/tables/categories.dart';
import 'package:money_app/core/database/tables/transactions.dart';
import 'package:money_app/core/database/tables/transfers.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

part 'app_database.g.dart';

/// База данных приложения (ADR 0001).
///
/// Исполнитель запросов ([QueryExecutor]) приходит параметром: в приложении
/// это будет файловая база, в тестах — `NativeDatabase.memory()`.
@DriftDatabase(
  tables: [AppSettings, Categories, Transactions, Accounts, Transfers],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        // v1 -> v2 (ADR 0010, п. 9): данные не меняются, у старых операций
        // account_id = NULL.
        //
        // Всё в одной транзакции: addColumn и createIndex не повторяются, и
        // при сбое посередине база осталась бы наполовину обновлённой и
        // больше не открылась бы. Транзакция откатывает всё целиком.
        await transaction(() async {
          await m.createTable(accounts);
          await m.createTable(transfers);
          await m.addColumn(transactions, transactions.accountId);
          await m.createIndex(accountsOrder);
          await m.createIndex(transactionsAccount);
          await m.createIndex(transfersOccurredOnAt);
          await m.createIndex(transfersFromAccount);
          await m.createIndex(transfersToAccount);
        });
      }
    },
    beforeOpen: (details) async {
      // SQLite по умолчанию не проверяет внешние ключи — включаем.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
