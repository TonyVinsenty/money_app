import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/features/recurring/domain/recurring_payment.dart';
import 'package:money_app/features/recurring/domain/recurring_schedule.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

/// Максимум уведомлений в плане (бюджет ADR 0004 при лимите iOS в 64).
const reminderBudget = 40;

/// На сколько дней вперёд планируем (ADR 0011, п. 11).
const reminderHorizonDays = 60;

/// Время дня для напоминаний: одно на всё приложение (ADR 0011, п. 11).
final class ReminderTime {
  /// Бросает [ArgumentError], если [hour] не в 0..23 или [minute] не в 0..59.
  ReminderTime(this.hour, this.minute) {
    if (hour < 0 || hour > 23) {
      throw ArgumentError.value(hour, 'hour', 'must be in 0..23');
    }
    if (minute < 0 || minute > 59) {
      throw ArgumentError.value(minute, 'minute', 'must be in 0..59');
    }
  }

  /// Значение по умолчанию: 10:00.
  factory ReminderTime.defaultTime() => ReminderTime(10, 0);

  final int hour;
  final int minute;

  @override
  bool operator ==(Object other) =>
      other is ReminderTime && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => Object.hash(hour, minute);

  @override
  String toString() =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

/// Одно запланированное уведомление.
///
/// Время - местное «настенное» (год, месяц, день, часы, минуты по часам
/// устройства), без UTC и часовых поясов: iOS и Android сами ставят
/// срабатывание по этим часам.
final class ReminderItem {
  const ReminderItem({
    required this.id,
    required this.year,
    required this.month,
    required this.day,
    required this.hour,
    required this.minute,
    required this.title,
    required this.body,
  });

  /// Код уведомления: 0, 1, 2 ... в порядке дат (на Android это код будильника).
  final int id;
  final int year;
  final int month;
  final int day;
  final int hour;
  final int minute;
  final String title;
  final String body;

  /// Вид для канала: ключи `id`, `year`, `month`, `day`, `hour`, `minute`
  /// (int), `title`, `body` (String).
  Map<String, Object> toMap() => {
    'id': id,
    'year': year,
    'month': month,
    'day': day,
    'hour': hour,
    'minute': minute,
    'title': title,
    'body': body,
  };

  @override
  bool operator ==(Object other) =>
      other is ReminderItem &&
      other.id == id &&
      other.year == year &&
      other.month == month &&
      other.day == day &&
      other.hour == hour &&
      other.minute == minute &&
      other.title == title &&
      other.body == body;

  @override
  int get hashCode =>
      Object.hash(id, year, month, day, hour, minute, title, body);

  @override
  String toString() =>
      'ReminderItem($id, $year-$month-$day $hour:$minute, '
      '$title, $body)';
}

/// План уведомлений (ADR 0011, п. 11).
///
/// У платежей с `remind = true` берутся даты от сегодняшнего дня [now] на
/// [horizonDays] дней вперёд. Не планируются: удалённые платежи; платёж,
/// отмеченный сегодня ([paidTodayIds] - id платежей); сегодняшний платёж, если
/// время [time] уже наступило. Итог идёт по дате (при равенстве - по названию),
/// не длиннее [budget]; коды 0, 1, 2 ... [categoryNames] - названия категорий
/// по id для текста уведомления.
List<ReminderItem> planReminders({
  required List<RecurringPayment> payments,
  required Set<String> paidTodayIds,
  required Map<String, String> categoryNames,
  required DateTime now,
  required ReminderTime time,
  int budget = reminderBudget,
  int horizonDays = reminderHorizonDays,
}) {
  final today = DateOnly.fromDateTime(now);
  final local = now.toLocal();
  final timePassed =
      local.hour * 60 + local.minute >= time.hour * 60 + time.minute;
  final last = today.addDays(horizonDays);

  final entries = <(DateOnly, RecurringPayment)>[];
  for (final p in payments) {
    if (!p.remind || p.isDeleted) continue;
    for (final date in dueDates(p, today, last)) {
      if (date == today && (timePassed || paidTodayIds.contains(p.id))) {
        continue;
      }
      entries.add((date, p));
    }
  }
  entries.sort((a, b) {
    final byDate = a.$1.compareTo(b.$1);
    if (byDate != 0) return byDate;
    final byTitle = a.$2.title.compareTo(b.$2.title);
    return byTitle != 0 ? byTitle : a.$2.id.compareTo(b.$2.id);
  });

  final result = <ReminderItem>[];
  for (final (date, p) in entries.take(budget < 0 ? 0 : budget)) {
    final verb = p.type == TransactionType.income ? 'Доход' : 'Расход';
    final category = categoryNames[p.categoryId];
    result.add(
      ReminderItem(
        id: result.length,
        year: date.year,
        month: date.month,
        day: date.day,
        hour: time.hour,
        minute: time.minute,
        title: 'Платёж сегодня: ${p.title}',
        body:
            '$verb ${formatMoney(p.amount)}'
            '${category == null ? '' : ' · $category'}',
      ),
    );
  }
  return result;
}
