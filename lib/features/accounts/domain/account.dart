import 'package:money_app/core/money/money.dart';
import 'package:money_app/features/accounts/domain/account_rules.dart';

/// Счёт: место, где лежат деньги (карта, наличные, вклад).
///
/// Стартовый остаток [openingBalance] может быть отрицательным (долг,
/// кредитная карта). Текущий остаток здесь не хранится: его считает
/// `computeAccountBalances` по движениям (ADR 0010).
///
/// Объект неизменяемый; правила проверяются при создании и при каждой копии.
final class Account {
  /// Восстанавливает счёт из хранилища (или создаёт по готовым полям).
  ///
  /// Бросает [AccountRuleException] (пустое или слишком длинное имя, пустой
  /// [iconKey], отрицательный [sortOrder]) и [ArgumentError], если
  /// [archivedAt] не в UTC или [currencyDigits] не от 0 до 8. Имя сохраняется без пробелов по краям.
  Account({
    required this.id,
    required String name,
    required String iconKey,
    required this.openingBalance,
    required int sortOrder,
    this.currencyDigits = 2,
    DateTime? archivedAt,
  }) : name = checkedName(name),
       iconKey = _checkedIconKey(iconKey),
       sortOrder = _checkedSortOrder(sortOrder),
       archivedAt = _checkedArchivedAt(archivedAt) {
    if (currencyDigits < 0 || currencyDigits > 8) {
      throw ArgumentError.value(
        currencyDigits,
        'currencyDigits',
        'must be between 0 and 8',
      );
    }
  }

  /// Занято ли [name] среди [existing]: есть ли там не архивный счёт с тем же
  /// именем (см. [accountNameKey]). Счёт с id [selfId] не считается.
  static bool isDuplicateName({
    required String name,
    required Iterable<Account> existing,
    String? selfId,
  }) {
    final key = accountNameKey(name);
    return existing.any(
      (other) =>
          other.id != selfId &&
          !other.isArchived &&
          accountNameKey(other.name) == key,
    );
  }

  /// То же, но при дубле бросает [AccountRuleException] с правилом
  /// [AccountRule.duplicateName].
  static void checkUniqueName({
    required String name,
    required Iterable<Account> existing,
    String? selfId,
  }) {
    if (isDuplicateName(name: name, existing: existing, selfId: selfId)) {
      throw AccountRuleException(AccountRule.duplicateName);
    }
  }

  /// Неизменяемый идентификатор (UUID v7).
  final String id;

  /// Имя без пробелов по краям, 1..[accountNameMaxLength] символов.
  final String name;

  /// Ключ значка (не пустой).
  final String iconKey;

  /// Стартовый остаток; может быть отрицательным. Валюта счёта — его валюта.
  final Money openingBalance;

  /// Порядок в списке (не отрицательный).
  final int sortOrder;

  /// Момент архивации в UTC; `null`, если счёт не в архиве.
  final DateTime? archivedAt;

  /// Знаков после запятой у валюты счёта (0-8, ADR 0010, п. 16.4).
  final int currencyDigits;

  /// Код валюты счёта.
  String get currency => openingBalance.currency;

  /// Счёт в архиве.
  bool get isArchived => archivedAt != null;

  /// Копия с новым именем.
  Account withName(String name) => _copy(name: name);

  /// Копия с новым значком.
  Account withIcon(String iconKey) => _copy(iconKey: iconKey);

  /// Копия с новым стартовым остатком.
  Account withOpeningBalance(Money openingBalance) =>
      _copy(openingBalance: openingBalance);

  /// Копия с новым порядком.
  Account withSortOrder(int sortOrder) => _copy(sortOrder: sortOrder);

  /// Копия, отправленная в архив в момент [at] (UTC, иначе [ArgumentError]).
  Account archived(DateTime at) => _copy(archivedAt: at);

  /// Копия, возвращённая из архива.
  Account restored() => Account(
    id: id,
    name: name,
    iconKey: iconKey,
    openingBalance: openingBalance,
    sortOrder: sortOrder,
    currencyDigits: currencyDigits,
  );

  Account _copy({
    String? name,
    String? iconKey,
    Money? openingBalance,
    int? sortOrder,
    DateTime? archivedAt,
  }) {
    return Account(
      id: id,
      name: name ?? this.name,
      iconKey: iconKey ?? this.iconKey,
      openingBalance: openingBalance ?? this.openingBalance,
      sortOrder: sortOrder ?? this.sortOrder,
      currencyDigits: currencyDigits,
      archivedAt: archivedAt ?? this.archivedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is Account &&
            other.id == id &&
            other.name == name &&
            other.iconKey == iconKey &&
            other.openingBalance == openingBalance &&
            other.sortOrder == sortOrder &&
            other.currencyDigits == currencyDigits &&
            other.archivedAt == archivedAt;
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    iconKey,
    openingBalance,
    sortOrder,
    currencyDigits,
    archivedAt,
  );

  @override
  String toString() {
    return 'Account(id: $id, name: $name, iconKey: $iconKey, '
        'openingBalance: $openingBalance, sortOrder: $sortOrder, '
        'currencyDigits: $currencyDigits, archivedAt: $archivedAt)';
  }

  /// Проверяет имя и возвращает его без пробелов по краям.
  static String checkedName(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      throw AccountRuleException(AccountRule.emptyName);
    }
    if (trimmed.runes.length > accountNameMaxLength) {
      throw AccountRuleException(AccountRule.nameTooLong);
    }
    return trimmed;
  }

  static String _checkedIconKey(String iconKey) {
    if (iconKey.trim().isEmpty) {
      throw AccountRuleException(AccountRule.emptyIconKey);
    }
    return iconKey;
  }

  static int _checkedSortOrder(int sortOrder) {
    if (sortOrder < 0) {
      throw AccountRuleException(AccountRule.negativeSortOrder);
    }
    return sortOrder;
  }

  static DateTime? _checkedArchivedAt(DateTime? archivedAt) {
    if (archivedAt != null && !archivedAt.isUtc) {
      throw ArgumentError.value(archivedAt, 'archivedAt', 'must be in UTC');
    }
    return archivedAt;
  }
}
