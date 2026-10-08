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
      accountId: 'a',
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
}
