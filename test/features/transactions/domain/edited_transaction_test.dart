import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/transactions/domain/edited_transaction.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_rules.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

import '../../../support/fixed_clock.dart';

final _clock = FixedClock(DateTime(2026, 9, 20, 15, 30));

Category _top(String id, {CategoryKind kind = CategoryKind.expense}) =>
    Category.topLevel(
      id: id,
      kind: kind,
      name: id,
      iconKey: 'shopping_cart',
      sortOrder: 0,
    );

final _original = Transaction(
  id: 'tx',
  type: TransactionType.expense,
  amount: Money.fromMinor(35000, 'RUB'),
  occurredOn: DateOnly(2026, 9, 18),
  occurredAt: DateTime.utc(2026, 9, 18, 7, 45),
  categoryId: 'food',
  subcategoryId: 'food-sub',
  note: 'старое',
);

Transaction _build({
  Money? amount,
  DateOnly? day,
  String? note = 'старое',
  Category? newCategory,
}) => buildEditedTransaction(
  original: _original,
  amount: amount ?? _original.amount,
  day: day ?? _original.occurredOn,
  clock: _clock,
  note: note,
  newCategory: newCategory,
);

void main() {
  test('ничего не менялось: операция равна исходной', () {
    expect(_build(), _original);
  });

  test('сумма и комментарий берутся из полей, id и тип прежние', () {
    final result = _build(amount: Money.fromMinor(0, 'RUB'), note: '  новое ');
    expect(result.amount, Money.fromMinor(0, 'RUB'));
    expect(result.note, 'новое');
    expect(result.id, 'tx');
    expect(result.type, TransactionType.expense);
    expect(result.occurredOn, _original.occurredOn);
    expect(result.occurredAt, _original.occurredAt);
  });

  test('пустой комментарий становится null', () {
    expect(_build(note: '   ').note, isNull);
  });

  test(
    'день не менялся: момент остаётся прежним (время суток не теряется)',
    () {
      final result = _build(amount: Money.fromMinor(1, 'RUB'));
      expect(result.occurredAt, DateTime.utc(2026, 9, 18, 7, 45));
    },
  );

  test('другой прошлый день: полдень этого дня, обе величины согласованы', () {
    final result = _build(day: DateOnly(2026, 9, 10));
    expect(result.occurredOn, DateOnly(2026, 9, 10));
    expect(result.occurredAt, DateTime(2026, 9, 10, 12).toUtc());
  });

  test('день сменён на сегодня: момент берётся из часов', () {
    final result = _build(day: DateOnly(2026, 9, 20));
    expect(result.occurredOn, DateOnly(2026, 9, 20));
    expect(result.occurredAt, DateTime(2026, 9, 20, 15, 30).toUtc());
  });

  test('день позже сегодняшнего: ArgumentError', () {
    expect(
      () => _build(day: DateOnly(2026, 9, 21)),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('та же категория: подкатегория остаётся', () {
    final result = _build(newCategory: _top('food'));
    expect(result.categoryId, 'food');
    expect(result.subcategoryId, 'food-sub');
  });

  test('другая категория: подкатегория сбрасывается в null', () {
    final result = _build(newCategory: _top('cafe'));
    expect(result.categoryId, 'cafe');
    expect(result.subcategoryId, isNull);
  });

  test('категория другого вида отвергается правилом', () {
    expect(
      () => _build(newCategory: _top('salary', kind: CategoryKind.income)),
      throwsA(
        isA<TransactionRuleException>().having(
          (e) => e.rule,
          'rule',
          TransactionRule.typeKindMismatch,
        ),
      ),
    );
  });
}
