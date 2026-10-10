import 'package:money_app/core/format/date_format.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/format/money_spoken.dart';
import 'package:money_app/core/format/percent_format.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/features/recurring/domain/recurring_payment.dart';
import 'package:money_app/features/recurring/domain/recurring_repository.dart';
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

// Тексты формы платежа (ROADMAP, Р3-Р6; утверждены 2026-10-10).

const String recurringFormTitle = 'Новый платёж';
const String recurringFormNameLabel = 'Название';
const String recurringFormNameHint = 'Например, Интернет';
const String recurringFormExpense = 'Расход';
const String recurringFormIncome = 'Доход';
const String recurringFormTypeLabel = 'Вид платежа';
const String recurringFormCategoryLabel = 'Категория';
const String recurringFormCategoryHint = 'Выберите категорию';
const String recurringFormAccountLabel = 'Счёт';
const String recurringFormAccountHint = 'Без счёта';
const String recurringFormRepeatLabel = 'Повтор';
const String recurringFormFirstLabel = 'Первый платёж';
const String recurringFormEndLabel = 'Окончание';
const String recurringFormNoEnd = 'Без окончания';
const String recurringFormEndClear = 'Убрать окончание';
const String recurringFormSave = 'Сохранить';

const String recurringErrorCategory = 'Выберите категорию';
const String recurringErrorEmptyTitle = 'Введите название';
const String recurringErrorTitleTooLong = 'Название — не длиннее 40 символов';
const String recurringErrorAmountZero = 'Сумма должна быть больше нуля';
const String recurringErrorEndsBeforeStart =
    'Окончание не может быть раньше первого платежа';

/// Вариант повтора из списка формы (Р4).
typedef RecurringRepeatOption = ({RepeatUnit unit, int every, String label});

/// Шесть вариантов повтора, первый («Каждый месяц») - по умолчанию.
const List<RecurringRepeatOption> recurringRepeatOptions = [
  (unit: RepeatUnit.month, every: 1, label: 'Каждый месяц'),
  (unit: RepeatUnit.week, every: 1, label: 'Каждую неделю'),
  (unit: RepeatUnit.week, every: 2, label: 'Каждые 2 недели'),
  (unit: RepeatUnit.month, every: 3, label: 'Каждые 3 месяца'),
  (unit: RepeatUnit.month, every: 6, label: 'Каждые 6 месяцев'),
  (unit: RepeatUnit.year, every: 1, label: 'Каждый год'),
];

/// Подсказка Р5 для числа [day] (29-31).
String recurringLastDayHint(int day) =>
    'В месяцы, где нет $day-го, — в последний день месяца';

final String _minus = String.fromCharCode(0x2212);
final String _emDash = String.fromCharCode(0x2014);

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

// Правка и удаление платежа (ROADMAP, Р3 и Р7; утверждены 2026-10-10).

const String recurringFormTitleEdit = 'Платёж';
const String recurringFormDelete = 'Удалить платёж';
const String recurringDeleteNote =
    'Уже внесённые операции останутся в «Истории»';
const String recurringUndo = 'Отменить';

/// Сообщение после удаления: «Платёж «Интернет» удалён».
String recurringDeletedMessage(String title) => 'Платёж «$title» удалён';

// Не из утверждённых: служебные сбои удаления и возврата.
const String recurringDeleteFailed = 'Не удалось удалить. Попробуйте ещё раз';

// «К оплате» и лист «Оплата» (ROADMAP, Р8 и Р9; утверждены 2026-10-10).

const String dueSectionTitleBase = 'К оплате';
const String duePayButton = 'Оплачено';
const String dueSkipButton = 'Пропустить';
const String dueEditButton = 'Изменить';
const String dueSheetAmountLabel = 'Сумма';
const String dueSheetDateLabel = 'Дата';
const String dueSheetAccountLabel = 'Счёт';

/// Заголовок блока: «К оплате (2)».
String dueSectionTitle(int count) => '$dueSectionTitleBase ($count)';

/// Заголовок листа: «Оплата: Интернет».
String dueSheetTitle(String title) => 'Оплата: $title';

/// День записи: «Сегодня», «Вчера» или «5 октября» (с годом, если год не
/// текущий).
String dueDayText(DateOnly day, DateOnly today) {
  if (day == today) return 'Сегодня';
  if (day == today.addDays(-1)) return 'Вчера';
  final text = formatDayMonth(day);
  return day.year == today.year ? text : '$text ${day.year}';
}

/// Строка записи: «Интернет · 650,00 ₽».
String dueRowText(RecurringPayment payment) =>
    '${payment.title} · ${formatMoney(payment.amount)}';

/// Озвучка строки: «Интернет, расход 650 рублей, сегодня».
String dueRowSemantics(RecurringPayment payment, DateOnly day, DateOnly today) {
  final kind = payment.type == TransactionType.income ? 'доход' : 'расход';
  return '${payment.title}, $kind ${spokenMoney(payment.amount)}, '
      '${dueDayText(day, today).toLowerCase()}';
}

/// Озвучка кнопок строки: «Оплачено: Интернет» и т. п.
String duePaySemantics(String title) => '$duePayButton: $title';
String dueSkipSemantics(String title) => '$dueSkipButton: $title';
String dueEditSemantics(String title) => '$dueEditButton: $title';

/// После «Пропустить»: «Платёж «Интернет» за 5 октября пропущен».
String dueSkippedMessage(String title, DateOnly day) =>
    'Платёж «$title» за ${formatDayMonth(day)} пропущен';

/// Плашка на «Главной» (Р10): «К оплате: Интернет — 650,00 ₽» или
/// «К оплате: 3 платежа».
String dueBannerText(List<RecurringDue> dues) {
  if (dues.length == 1) {
    final p = dues.single.payment;
    return dueBannerHead(p) + dueBannerTail(p);
  }
  return '$dueSectionTitleBase: ${_dueCountText(dues.length)}';
}

/// Начало плашки с одним платежом: «К оплате: Интернет». Плашка сокращает
/// только его, хвост с суммой показывает всегда.
String dueBannerHead(RecurringPayment p) => '$dueSectionTitleBase: ${p.title}';

/// Хвост плашки с одним платежом: « — 650,00 ₽».
String dueBannerTail(RecurringPayment p) =>
    ' $_emDash ${formatMoney(p.amount)}';

String _dueCountText(int n) =>
    '$n ${pluralRu(n, 'платёж', 'платежа', 'платежей')}';

/// Озвучка плашки. Для нескольких - по Р10: «К оплате 3 платежа. Открыть»;
/// для одного - по Р10б: «К оплате: Интернет, 650 рублей. Открыть».
String dueBannerSemantics(List<RecurringDue> dues) {
  if (dues.length == 1) {
    final p = dues.single.payment;
    return '$dueSectionTitleBase: ${p.title}, ${spokenMoney(p.amount)}. '
        'Открыть';
  }
  return '$dueSectionTitleBase ${_dueCountText(dues.length)}. Открыть';
}

/// Число в кружке на значке «Баланс»: больше 99 - «99+».
String dueBadgeText(int count) => count > 99 ? '99+' : '$count';

/// Озвучка значка, склеивается с подписью вкладки: «Баланс, к оплате: 3».
String dueBadgeSemantics(int count) => 'к оплате: $count';

/// Категория в архиве (Р8); те же тексты в форме платежа и в «К оплате».
String dueCategoryArchivedText(String name) =>
    'Категория «$name» в архиве — выберите другую';

// Не из утверждённых: то же для подкатегории и счёта по образцу Р8.
String dueSubcategoryArchivedText(String name) =>
    'Подкатегория «$name» в архиве — выберите другую';
String dueAccountArchivedText(String name) =>
    'Счёт «$name» в архиве — выберите другой';
