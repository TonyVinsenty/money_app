import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/features/transactions/domain/history_view.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

Transaction _t(
  String id, {
  TransactionType type = TransactionType.expense,
  String category = 'food',
  String? account,
}) => Transaction(
  id: id,
  type: type,
  amount: Money.fromMinor(100, 'RUB'),
  occurredOn: DateOnly(2026, 9, 1),
  occurredAt: DateTime.utc(2026, 9, 1, 9),
  categoryId: category,
  accountId: account,
);

void main() {
  test('фильтр по счёту: только операции этого счёта', () {
    final filter = HistoryFilter.account('a');
    expect(filter.isActive, isTrue);
    expect(filter.matches(_t('1', account: 'a')), isTrue);
    expect(filter.matches(_t('2', account: 'b')), isFalse);
    expect(filter.matches(_t('3')), isFalse);
    expect(HistoryFilter.off.matches(_t('3')), isTrue);
  });

  test('счёт вместе с типом и категориями', () {
    final filter = HistoryFilter(
      type: HistoryTypeFilter.expense,
      expenseCategoryIds: {'food'},
      accountFilter: const OneAccount('a'),
    );
    expect(filter.matches(_t('1', account: 'a')), isTrue);
    expect(filter.matches(_t('2', account: 'a', category: 'cafe')), isFalse);
    expect(
      filter.matches(_t('3', account: 'a', type: TransactionType.income)),
      isFalse,
    );
    expect(filter.matches(_t('4', account: 'b')), isFalse);
  });

  test('равенство учитывает счёт', () {
    expect(HistoryFilter.account('a'), HistoryFilter.account('a'));
    expect(HistoryFilter.account('a'), isNot(HistoryFilter.account('b')));
    expect(HistoryFilter.account('a'), isNot(HistoryFilter.off));
    expect(
      HistoryFilter.account('a').hashCode,
      HistoryFilter.account('a').hashCode,
    );
  });

  test('applyHistoryView отбирает по счёту', () {
    final shown = applyHistoryView(
      [_t('1', account: 'a'), _t('2', account: 'b'), _t('3')],
      HistoryFilter.account('a'),
      HistorySort.newestFirst,
    );
    expect([for (final t in shown) t.id], ['1']);
  });

  group('три состояния счёта', () {
    final withCard = _t('card', account: 'card');
    final other = _t('cash', account: 'cash');
    final none = _t('none');
    final income = _t('i', type: TransactionType.income);

    test('«Без счёта» - только операции без счёта', () {
      final f = HistoryFilter(accountFilter: const NoAccount());
      expect(f.isActive, isTrue);
      expect([withCard, other, none, income].where(f.matches), [none, income]);
    });

    test('«Все счета» - все операции', () {
      expect([withCard, other, none].where(HistoryFilter.off.matches), [
        withCard,
        other,
        none,
      ]);
    });

    test('«Без счёта» вместе с типом и категориями', () {
      final f = HistoryFilter(
        type: HistoryTypeFilter.expense,
        expenseCategoryIds: {'food'},
        accountFilter: const NoAccount(),
      );
      expect([withCard, none, income].where(f.matches), [none]);
      final g = HistoryFilter(
        type: HistoryTypeFilter.expense,
        expenseCategoryIds: {'cafe'},
        accountFilter: const NoAccount(),
      );
      expect([none].where(g.matches), isEmpty);
    });

    test('равенство и hashCode трёх состояний', () {
      final all = HistoryFilter.off;
      final none1 = HistoryFilter(accountFilter: const NoAccount());
      final none2 = HistoryFilter(accountFilter: const NoAccount());
      final one = HistoryFilter.account('card');
      expect(none1, none2);
      expect(none1.hashCode, none2.hashCode);
      expect(none1, isNot(all));
      expect(none1, isNot(one));
      expect(all, isNot(one));
      expect(one, HistoryFilter(accountFilter: const OneAccount('card')));
      expect(
        one.hashCode,
        HistoryFilter(accountFilter: const OneAccount('card')).hashCode,
      );
    });

    test('withAnyAccount сбрасывает только счёт', () {
      final f = HistoryFilter(
        type: HistoryTypeFilter.expense,
        expenseCategoryIds: {'food'},
        accountFilter: const OneAccount('card'),
      );
      expect(
        f.withAnyAccount(),
        HistoryFilter(
          type: HistoryTypeFilter.expense,
          expenseCategoryIds: {'food'},
        ),
      );
    });
  });
}
