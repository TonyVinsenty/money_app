import 'package:money_app/core/format/date_format.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/format/money_spoken.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/features/recurring/domain/recurring_payment.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

// Тексты раздела «Регулярные платежи» (ROADMAP, Р1 и Р2; утверждены
// пользователем 2026-10-10). Все в одном файле: они понадобятся и форме.

/// Заголовок раздела на «Баланс».
const String recurringSectionTitle = 'Регулярные платежи';

/// Кнопка «Добавить платёж».
const String recurringAddButton = 'Добавить платёж';

/// Пустое состояние раздела.
const String recurringEmptyText =
    'Добавьте то, что платите регулярно: связь, подписки, аренду. '
    'В день платежа Zuno напомнит о нём';

/// Вторая строка у завершённого платежа.
const String recurringFinishedLabel = 'Завершён';

final String _minus = String.fromCharCode(0x2212);

/// Сумма строки со знаком: у расхода настоящий минус (U+2212), у дохода «+».
String recurringAmountText(RecurringPayment payment) {
  final shown = formatMoney(payment.amount);
  return payment.type == TransactionType.income ? '+$shown' : '$_minus$shown';
}

String _plural(int n, String one, String few, String many) {
  final lastTwo = n % 100;
  if (lastTwo >= 11 && lastTwo <= 14) return many;
  return switch (n % 10) {
    1 => one,
    2 || 3 || 4 => few,
    _ => many,
  };
}

const _weekdayDative = [
  'понедельникам',
  'вторникам',
  'средам',
  'четвергам',
  'пятницам',
  'субботам',
  'воскресеньям',
];

/// Повтор словами: «Каждый месяц, 5-го», «Каждую неделю, по пятницам»,
/// «Каждый год, 12 марта»; при «каждые N» - «Каждые 2 недели, ...».
/// Месяц и день берутся из даты первого платежа.
String recurringRepeatText(RecurringPayment payment) {
  final n = payment.every;
  final start = payment.startsOn;
  switch (payment.unit) {
    case RepeatUnit.week:
      final head = n == 1
          ? 'Каждую неделю'
          : 'Каждые $n ${_plural(n, 'неделю', 'недели', 'недель')}';
      return '$head, по ${_weekdayDative[start.weekday - 1]}';
    case RepeatUnit.month:
      final head = n == 1
          ? 'Каждый месяц'
          : 'Каждые $n ${_plural(n, 'месяц', 'месяца', 'месяцев')}';
      return '$head, ${start.day}-го';
    case RepeatUnit.year:
      final head = n == 1
          ? 'Каждый год'
          : 'Каждые $n ${_plural(n, 'год', 'года', 'лет')}';
      return '$head, ${formatDayMonth(start)}';
  }
}

/// Вторая строка: «Каждый месяц, 5-го · следующий 5 ноября»; у завершённого
/// ([nextDue] равен `null`) - «Завершён».
String recurringSubtitleText(RecurringPayment payment, DateOnly? nextDue) {
  if (nextDue == null) return recurringFinishedLabel;
  return '${recurringRepeatText(payment)} · следующий ${formatDayMonth(nextDue)}';
}

/// Озвучка строки: «Интернет, расход 650 рублей, каждый месяц 5-го,
/// следующий 5 ноября»; у завершённого - «..., завершён».
String recurringRowSemantics(RecurringPayment payment, DateOnly? nextDue) {
  final kind = payment.type == TransactionType.income ? 'доход' : 'расход';
  final head = '${payment.title}, $kind ${spokenMoney(payment.amount)}';
  if (nextDue == null) return '$head, завершён';
  final repeat = recurringRepeatText(payment)
      .toLowerCase()
      .replaceFirst(', ', ' ');
  return '$head, $repeat, следующий ${formatDayMonth(nextDue)}';
}
