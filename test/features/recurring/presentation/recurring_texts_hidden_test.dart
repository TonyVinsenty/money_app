import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/masked_amount.dart';
import 'package:money_app/features/recurring/domain/recurring_payment.dart';
import 'package:money_app/features/recurring/domain/recurring_repository.dart';
import 'package:money_app/features/recurring/presentation/recurring_texts.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

final _payment = RecurringPayment(
  id: 'p1',
  title: 'Интернет',
  type: TransactionType.expense,
  amount: Money.fromMinor(65000, 'RUB'),
  categoryId: 'cat',
  unit: RepeatUnit.month,
  every: 1,
  startsOn: DateOnly(2026, 10, 10),
);

final _due = RecurringDue(
  id: 'd1',
  payment: _payment,
  dueOn: DateOnly(2026, 10, 10),
  status: RecurringDueStatus.pending,
);

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
  });

  final shown = formatMoney(_payment.amount);
  final today = DateOnly(2026, 10, 10);

  test('по умолчанию суммы видны', () {
    expect(dueRowText(_payment), contains(shown));
    expect(dueBannerTail(_payment), contains(shown));
    expect(recurringAmountText(_payment), contains(shown));
  });

  test('hidden: вместо суммы три точки', () {
    expect(dueRowText(_payment, hidden: true), 'Интернет · $maskedMoneyText');
    expect(dueBannerTail(_payment, hidden: true), contains(maskedMoneyText));
    expect(dueBannerTail(_payment, hidden: true), isNot(contains(shown)));
    expect(
      dueBannerText([_due], hidden: true),
      allOf(contains(maskedMoneyText), isNot(contains(shown))),
    );
    final amount = recurringAmountText(_payment, hidden: true);
    expect(amount, endsWith(maskedMoneyText));
    expect(amount, isNot(contains(shown)));
  });

  test('hidden: озвучка «сумма скрыта»', () {
    expect(
      dueRowSemantics(_payment, today, today, hidden: true),
      contains(hiddenAmountLabel),
    );
    expect(
      dueBannerSemantics([_due], hidden: true),
      contains(hiddenAmountLabel),
    );
    expect(
      recurringRowSemantics(_payment, today, hidden: true),
      contains(hiddenAmountLabel),
    );
    expect(
      dueRowSemantics(_payment, today, today),
      isNot(contains(hiddenAmountLabel)),
    );
  });
}
