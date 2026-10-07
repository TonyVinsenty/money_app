import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/features/accounts/domain/transfer.dart';
import 'package:money_app/features/accounts/domain/transfer_rules.dart';
import 'package:money_app/features/transactions/domain/transaction_rules.dart';

Transfer make({
  String id = 't1',
  String from = 'a',
  String to = 'b',
  int amount = 500000,
  DateTime? occurredAt,
  String? note,
}) => Transfer(
  id: id,
  fromAccountId: from,
  toAccountId: to,
  amount: Money.fromMinor(amount, 'RUB'),
  occurredOn: DateOnly(2026, 10, 7),
  occurredAt: occurredAt ?? DateTime.utc(2026, 10, 7, 9),
  note: note,
);

void expectRule(void Function() body, TransferRule rule) {
  expect(
    body,
    throwsA(isA<TransferRuleException>().having((e) => e.rule, 'rule', rule)),
  );
}

void main() {
  test('корректный перевод создаётся', () {
    final t = make(note: 'снял наличные');
    expect(t.fromAccountId, 'a');
    expect(t.toAccountId, 'b');
    expect(t.amount.minorUnits, 500000);
    expect(t.note, 'снял наличные');
  });

  test('одинаковые счета — ошибка', () {
    expectRule(() => make(from: 'a', to: 'a'), TransferRule.sameAccount);
  });

  test('пустой id счёта — ошибка', () {
    expectRule(() => make(from: ' '), TransferRule.emptyAccountId);
    expectRule(() => make(to: ''), TransferRule.emptyAccountId);
  });

  test('сумма: ноль и минус — ошибка, одна копейка можно', () {
    expectRule(() => make(amount: 0), TransferRule.nonPositiveAmount);
    expectRule(() => make(amount: -1), TransferRule.nonPositiveAmount);
    expect(make(amount: 1).amount.minorUnits, 1);
  });

  test('момент не в UTC — ошибка', () {
    expectRule(
      () => make(occurredAt: DateTime(2026, 10, 7)),
      TransferRule.occurredAtNotUtc,
    );
  });

  group('комментарий', () {
    test('пробелы и пусто превращаются в null', () {
      expect(make(note: '   ').note, isNull);
      expect(make(note: '').note, isNull);
      expect(make().note, isNull);
    });

    test('обрезается по краям', () {
      expect(make(note: '  привет ').note, 'привет');
    });

    test('200 символов можно, 201 нельзя', () {
      expect(make(note: 'я' * transactionNoteMaxLength).note, isNotNull);
      expectRule(
        () => make(note: 'я' * (transactionNoteMaxLength + 1)),
        TransferRule.noteTooLong,
      );
    });
  });

  test('равенство и hashCode', () {
    final a = make(note: ' x ');
    final b = make(note: 'x');
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a == make(to: 'c'), isFalse);
    expect(a == make(amount: 1), isFalse);
    expect(a == make(id: 't2'), isFalse);
    expect(a.toString(), contains('t1'));
  });

  test('исключение хранит правило и сообщение', () {
    for (final rule in TransferRule.values) {
      final e = TransferRuleException(rule);
      expect(e.rule, rule);
      expect(e.message, isNotEmpty);
      expect(e.toString(), contains(rule.name));
    }
    expect(TransferRuleException(TransferRule.sameAccount, 'x').message, 'x');
  });
}
