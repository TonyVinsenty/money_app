import 'package:money_app/core/money/currency_catalog.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/features/recurring/domain/recurring_rules.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

/// Единица повтора: «каждые N недель / месяцев / лет» (ADR 0011, п. 2).
enum RepeatUnit { week, month, year }

/// Метка «поле не меняется» для копий с обнуляемыми полями.
const Object _keep = Object();

/// Регулярный платёж: правило, по которому появляются записи «к оплате».
///
/// Расписание задают [unit], [every] и якорь [startsOn]: день недели, число
/// месяца или день и месяц года берутся из него. Сами даты считает
/// `dueDates` (ADR 0011, п. 3). Объект неизменяемый; правила проверяются при
/// создании и при каждой копии.
final class RecurringPayment {
  /// Бросает [RecurringRuleException] при нарушении правил (пустое или
  /// слишком длинное название, сумма не больше нуля, [every] вне 1-99,
  /// [endsOn] раньше [startsOn], валюта не обычная, пустые id) и
  /// [ArgumentError], если момент времени не в UTC. Название сохраняется без
  /// пробелов по краям.
  RecurringPayment({
    required this.id,
    required String title,
    required this.type,
    required this.amount,
    required this.categoryId,
    this.subcategoryId,
    this.accountId,
    required this.unit,
    required this.every,
    required this.startsOn,
    this.endsOn,
    this.remind = true,
    this.trackedThrough,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) : title = checkedTitle(title),
       createdAt = _checkedUtc(createdAt, 'createdAt'),
       updatedAt = _checkedUtc(updatedAt, 'updatedAt'),
       deletedAt = _checkedUtc(deletedAt, 'deletedAt') {
    if (amount.minorUnits <= 0) {
      throw RecurringRuleException(RecurringRule.nonPositiveAmount);
    }
    if (catalogCurrency(amount.currency)?.kind != CurrencyKind.fiat) {
      throw RecurringRuleException(RecurringRule.currencyNotRegular);
    }
    if (every < recurringEveryMin || every > recurringEveryMax) {
      throw RecurringRuleException(RecurringRule.everyOutOfRange);
    }
    final end = endsOn;
    if (end != null && end < startsOn) {
      throw RecurringRuleException(RecurringRule.endsBeforeStart);
    }
    if (id.trim().isEmpty ||
        categoryId.trim().isEmpty ||
        (subcategoryId != null && subcategoryId!.trim().isEmpty) ||
        (accountId != null && accountId!.trim().isEmpty)) {
      throw RecurringRuleException(RecurringRule.emptyId);
    }
  }

  /// Неизменяемый идентификатор (UUID v7).
  final String id;

  /// Название без пробелов по краям, 1..[recurringTitleMaxLength] символов;
  /// оно же комментарий создаваемой операции.
  final String title;

  /// Доход или расход.
  final TransactionType type;

  /// Сумма строго больше нуля, в обычной валюте.
  final Money amount;

  /// Категория верхнего уровня.
  final String categoryId;

  /// Подкатегория или `null`.
  final String? subcategoryId;

  /// Счёт или `null` («без счёта»).
  final String? accountId;

  /// Единица повтора.
  final RepeatUnit unit;

  /// «Каждые N» единиц, 1..99.
  final int every;

  /// Дата первого платежа; якорь расписания.
  final DateOnly startsOn;

  /// Последний возможный день включительно; `null` - бессрочно.
  final DateOnly? endsOn;

  /// Напоминать уведомлением.
  final bool remind;

  /// До какого дня включительно уже созданы записи «к оплате» (служебное).
  final DateOnly? trackedThrough;

  /// Момент создания в UTC; обычно задаёт хранилище. В `==` не входит.
  final DateTime? createdAt;

  /// Момент последней правки в UTC; обычно задаёт хранилище. В `==` не входит.
  final DateTime? updatedAt;

  /// Момент мягкого удаления в UTC; `null` у живого платежа.
  final DateTime? deletedAt;

  /// Платёж удалён (мягко).
  bool get isDeleted => deletedAt != null;

  /// Копия с новым названием.
  RecurringPayment withTitle(String title) => _copy(title: title);

  /// Копия с новым типом.
  RecurringPayment withType(TransactionType type) => _copy(type: type);

  /// Копия с новой суммой.
  RecurringPayment withAmount(Money amount) => _copy(amount: amount);

  /// Копия с новой категорией; подкатегория при этом сбрасывается.
  RecurringPayment withCategory(String categoryId) =>
      _copy(categoryId: categoryId, subcategoryId: null);

  /// Копия с новой подкатегорией (`null` - без подкатегории).
  RecurringPayment withSubcategory(String? subcategoryId) =>
      _copy(subcategoryId: subcategoryId);

  /// Копия с новым счётом (`null` - без счёта).
  RecurringPayment withAccount(String? accountId) =>
      _copy(accountId: accountId);

  /// Копия с новым повтором.
  RecurringPayment withRepeat(RepeatUnit unit, int every) =>
      _copy(unit: unit, every: every);

  /// Копия с новой датой первого платежа.
  RecurringPayment withStartsOn(DateOnly startsOn) => _copy(startsOn: startsOn);

  /// Копия с новой датой окончания (`null` - бессрочно).
  RecurringPayment withEndsOn(DateOnly? endsOn) => _copy(endsOn: endsOn);

  /// Копия с другим значением «напоминать».
  RecurringPayment withRemind(bool remind) => _copy(remind: remind);

  /// Копия с новым днём, до которого созданы записи «к оплате».
  RecurringPayment withTrackedThrough(DateOnly? trackedThrough) =>
      _copy(trackedThrough: trackedThrough);

  /// Копия, удалённая в момент [at] (UTC, иначе [ArgumentError]).
  RecurringPayment deleted(DateTime at) => _copy(deletedAt: at);

  /// Копия, восстановленная после удаления.
  RecurringPayment restored() => _copy(deletedAt: null);

  RecurringPayment _copy({
    String? title,
    TransactionType? type,
    Money? amount,
    String? categoryId,
    Object? subcategoryId = _keep,
    Object? accountId = _keep,
    RepeatUnit? unit,
    int? every,
    DateOnly? startsOn,
    Object? endsOn = _keep,
    bool? remind,
    Object? trackedThrough = _keep,
    Object? deletedAt = _keep,
  }) {
    return RecurringPayment(
      id: id,
      title: title ?? this.title,
      type: type ?? this.type,
      amount: amount ?? this.amount,
      categoryId: categoryId ?? this.categoryId,
      subcategoryId: identical(subcategoryId, _keep)
          ? this.subcategoryId
          : subcategoryId as String?,
      accountId: identical(accountId, _keep)
          ? this.accountId
          : accountId as String?,
      unit: unit ?? this.unit,
      every: every ?? this.every,
      startsOn: startsOn ?? this.startsOn,
      endsOn: identical(endsOn, _keep) ? this.endsOn : endsOn as DateOnly?,
      remind: remind ?? this.remind,
      trackedThrough: identical(trackedThrough, _keep)
          ? this.trackedThrough
          : trackedThrough as DateOnly?,
      createdAt: createdAt,
      updatedAt: updatedAt,
      deletedAt: identical(deletedAt, _keep)
          ? this.deletedAt
          : deletedAt as DateTime?,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is RecurringPayment &&
            other.id == id &&
            other.title == title &&
            other.type == type &&
            other.amount == amount &&
            other.categoryId == categoryId &&
            other.subcategoryId == subcategoryId &&
            other.accountId == accountId &&
            other.unit == unit &&
            other.every == every &&
            other.startsOn == startsOn &&
            other.endsOn == endsOn &&
            other.remind == remind &&
            other.trackedThrough == trackedThrough &&
            other.deletedAt == deletedAt;
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    type,
    amount,
    categoryId,
    subcategoryId,
    accountId,
    unit,
    every,
    startsOn,
    endsOn,
    remind,
    trackedThrough,
    deletedAt,
  );

  @override
  String toString() {
    return 'RecurringPayment(id: $id, title: $title, type: ${type.name}, '
        'amount: $amount, categoryId: $categoryId, '
        'subcategoryId: $subcategoryId, accountId: $accountId, '
        'unit: ${unit.name}, every: $every, startsOn: $startsOn, '
        'endsOn: $endsOn, remind: $remind, '
        'trackedThrough: $trackedThrough, deletedAt: $deletedAt)';
  }

  /// Проверяет название и возвращает его без пробелов по краям.
  static String checkedTitle(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      throw RecurringRuleException(RecurringRule.emptyTitle);
    }
    if (trimmed.runes.length > recurringTitleMaxLength) {
      throw RecurringRuleException(RecurringRule.titleTooLong);
    }
    return trimmed;
  }

  static DateTime? _checkedUtc(DateTime? value, String name) {
    if (value != null && !value.isUtc) {
      throw ArgumentError.value(value, name, 'must be in UTC');
    }
    return value;
  }
}
