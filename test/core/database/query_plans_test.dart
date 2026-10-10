import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/database/app_database.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/features/accounts/data/accounts_repository_impl.dart';
import 'package:money_app/features/accounts/data/transfers_repository_impl.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/transactions/data/transactions_repository_impl.dart';

import '../../support/fixed_clock.dart';

/// Тексты плана зависят от версии SQLite, поэтому тесты сравнивают их по
/// подстрокам (имя индекса), а не по всей строке.
void main() {
  group('query plans use the partial indexes', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await db.customSelect('SELECT 1').get(); // открыть и создать схему

      for (var i = 0; i < 6; i++) {
        await db.customStatement(
          'INSERT INTO categories (id, kind, name, icon_key, parent_id, '
          'sort_order, created_at, updated_at) '
          "VALUES ('c$i', '${i.isEven ? 'expense' : 'income'}', 'Cat $i', "
          "'icon', NULL, $i, 1, 1)",
        );
      }
      // Несколько сотен операций за разные дни, часть удалена мягко.
      for (var i = 0; i < 300; i++) {
        final day = 20260101 + (i % 28);
        await db.customStatement(
          'INSERT INTO transactions (id, type, amount_minor, currency, '
          'occurred_on, occurred_at, category_id, created_at, updated_at, '
          'deleted_at) '
          "VALUES ('t$i', 'expense', ${100 + i}, 'RUB', $day, ${1000 + i}, "
          "'c${i % 6}', 1, 1, ${i % 10 == 0 ? 5 : 'NULL'})",
        );
      }
    });

    tearDown(() async {
      await db.close();
    });

    /// Строки `detail` из `EXPLAIN QUERY PLAN`, склеенные в один текст.
    Future<String> plan(
      String sql, [
      List<Variable<Object>> vars = const [],
    ]) async {
      final rows = await db
          .customSelect('EXPLAIN QUERY PLAN $sql', variables: vars)
          .get();
      return rows.map((r) => r.read<String>('detail')).join('\n');
    }

    final period = [Variable<int>(20260105), Variable<int>(20260120)];

    test('history list (period + sort) uses transactions_occurred_on_at '
        'without a separate sort', () async {
      final text = await plan(
        'SELECT * FROM transactions WHERE deleted_at IS NULL '
        'AND occurred_on BETWEEN ? AND ? '
        'ORDER BY occurred_on DESC, occurred_at DESC',
        period,
      );

      expect(text, contains('USING INDEX transactions_occurred_on_at'));
      // Индекс уже отсортирован по (occurred_on, occurred_at); SQLite умеет
      // читать его в обратном порядке, поэтому отдельная сортировка не нужна.
      expect(text, isNot(contains('USE TEMP B-TREE FOR ORDER BY')));
    });

    test('category totals for a period use an index of transactions', () async {
      final text = await plan(
        'SELECT category_id, SUM(amount_minor) FROM transactions '
        'WHERE deleted_at IS NULL AND occurred_on BETWEEN ? AND ? '
        'GROUP BY category_id',
        period,
      );

      // Какой из двух индексов выберет SQLite, зависит от его оценок
      // стоимости (сейчас — transactions_occurred_on_at: сначала сужает
      // период, потом группирует во временном дереве `USE TEMP B-TREE FOR
      // GROUP BY`, для нескольких категорий это дёшево). Нам важно, что
      // читается частичный индекс, а не вся таблица.
      expect(
        text,
        anyOf(
          contains('USING INDEX transactions_occurred_on_at'),
          contains('USING INDEX transactions_category_occurred_on'),
          contains('USING COVERING INDEX transactions_category_occurred_on'),
        ),
      );
      expect(text, isNot(contains('SCAN transactions')));
    });

    test('live category grid uses categories_kind_level_order', () async {
      final text = await plan(
        'SELECT * FROM categories WHERE deleted_at IS NULL '
        'AND kind = ? AND parent_id IS NULL ORDER BY sort_order',
        [Variable<String>('expense')],
      );

      expect(text, contains('INDEX categories_kind_level_order'));
      expect(text, isNot(contains('USE TEMP B-TREE FOR ORDER BY')));
    });

    test(
      'analytics period list: the SQL drift really builds for '
      'watchInPeriod uses transactions_occurred_on_at, no full scan',
      () async {
        // Ловим настоящий SELECT, который выполняет репозиторий, и его
        // аргументы; публичный API репозитория при этом не меняется.
        final spy = _SelectSpy();
        final spied = AppDatabase(NativeDatabase.memory().interceptWith(spy));
        addTearDown(spied.close);
        await spied.customSelect('SELECT 1').get();
        final repo = DriftTransactionsRepository(
          spied,
          clock: FixedClock(DateTime.utc(2026, 9, 20, 12)),
        );
        await repo
            .watchInPeriod(
              DateRange(DateOnly(2026, 1, 5), DateOnly(2026, 1, 20)),
            )
            .first;

        final select = spy.selects.lastWhere(
          (s) => s.sql.contains('FROM "transactions"'),
        );
        final rows = await spied
            .customSelect(
              'EXPLAIN QUERY PLAN ${select.sql}',
              variables: [for (final a in select.args) Variable<Object>(a)],
            )
            .get();
        final text = rows.map((r) => r.read<String>('detail')).join('\n');

        expect(text, contains('USING INDEX transactions_occurred_on_at'));
        expect(text, isNot(contains('SCAN transactions')));
      },
    );

    test(
      'first day (MIN occurred_on) uses transactions_occurred_on_at',
      () async {
        final text = await plan(
          'SELECT MIN(occurred_on) AS first_day FROM transactions '
          'WHERE deleted_at IS NULL',
        );

        expect(text, contains('INDEX transactions_occurred_on_at'));
        expect(text, isNot(contains('SCAN transactions')));
      },
    );

    test('account balances: every SUM query uses a partial account index, '
        'no full scan', () async {
      final spy = _SelectSpy();
      final spied = AppDatabase(NativeDatabase.memory().interceptWith(spy));
      addTearDown(spied.close);
      await spied.customSelect('SELECT 1').get();
      final accounts = DriftAccountsRepository(
        spied,
        clock: FixedClock(DateTime.utc(2026, 10, 8, 12)),
      );
      // Запросы сумм идут по валютам существующих счетов: нужен хотя бы один.
      await accounts.create(
        Account(
          id: 'a',
          name: 'Карта',
          iconKey: 'card',
          openingBalance: Money.zero('RUB'),
          sortOrder: 0,
          currencyDigits: 2,
        ),
      );
      spy.selects.clear();
      await accounts.watchBalances().first;

      final sums = spy.selects.where((s) => s.sql.contains('SUM(')).toList();
      expect(sums, hasLength(3));
      final expected = [
        'transactions_account',
        'transfers_from_account',
        'transfers_to_account',
      ];
      for (var i = 0; i < sums.length; i++) {
        final rows = await spied
            .customSelect(
              'EXPLAIN QUERY PLAN ${sums[i].sql}',
              variables: [for (final a in sums[i].args) Variable<Object>(a)],
            )
            .get();
        final text = rows.map((r) => r.read<String>('detail')).join('\n');
        expect(text, contains('INDEX ${expected[i]}'), reason: text);
        for (final line in text.split('\n')) {
          if (line.contains('SCAN')) {
            expect(line, contains('INDEX'), reason: 'full scan: $text');
          }
        }
      }
    });

    test('transfers watchAll: the SQL drift builds uses '
        'transfers_occurred_on_at, no full scan', () async {
      final spy = _SelectSpy();
      final spied = AppDatabase(NativeDatabase.memory().interceptWith(spy));
      addTearDown(spied.close);
      await spied.customSelect('SELECT 1').get();
      await DriftTransfersRepository(
        spied,
        clock: FixedClock(DateTime.utc(2026, 10, 10, 12)),
      ).watchAll().first;

      final select = spy.selects.lastWhere(
        (s) => s.sql.contains('FROM "transfers"'),
      );
      final rows = await spied
          .customSelect(
            'EXPLAIN QUERY PLAN ${select.sql}',
            variables: [for (final a in select.args) Variable<Object>(a)],
          )
          .get();
      final text = rows.map((r) => r.read<String>('detail')).join('\n');
      expect(text, contains('INDEX transfers_occurred_on_at'), reason: text);
      // Читаются все живые переводы, поэтому обход есть, но по индексу
      // (уже в нужном порядке); сортировка только по `id` для равных моментов.
      expect(text, contains('SCAN transfers USING INDEX'), reason: text);
    });

    test('documentation: without "deleted_at IS NULL" the partial index is '
        'NOT used (every live-rows query must contain it)', () async {
      final text = await plan(
        'SELECT * FROM transactions '
        'WHERE occurred_on BETWEEN ? AND ? '
        'ORDER BY occurred_on DESC, occurred_at DESC',
        period,
      );

      expect(text, isNot(contains('transactions_occurred_on_at')));
      expect(text, contains('SCAN transactions'));
    });
  });
}

/// Запоминает все SELECT-запросы, которые доходят до базы.
class _SelectSpy extends QueryInterceptor {
  final selects = <({String sql, List<Object?> args})>[];

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    selects.add((sql: statement, args: args));
    return executor.runSelect(statement, args);
  }
}
