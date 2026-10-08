import 'package:money_app/core/format/currency_label.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/format/money_spoken.dart';
import 'package:money_app/core/money/currency_catalog.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/ui/category_rule_text.dart';
import 'package:money_app/features/accounts/domain/account_rules.dart';

// Черновик текстов раздела «Счета»: пользователь их ещё утверждает.

const String accountsSectionTitle = 'Счета';
const String accountsTotalLabel = 'Всего на счетах';
const String accountsEmptyText =
    'Добавьте счёт: карту, наличные, вклад — и укажите, сколько на нём сейчас';
const String accountsAddButton = 'Добавить счёт';
const String accountsLoadError = 'Не удалось загрузить счета';

// Форма счёта (тексты утверждены).
const String accountFormCreateTitle = 'Новый счёт';
const String accountFormEditTitle = 'Изменить счёт';
const String accountFormNameLabel = 'Название';
const String accountFormNameHint = 'Например, Карта';
const String accountFormIconTitle = 'Иконка';
const String accountFormBalanceLabel = 'Сколько на счёте сейчас';
const String accountFormBalanceHelper = 'Можно оставить пустым — будет 0';
const String accountFormMinusTitle = 'Минус (долг)';
const String accountFormMinusHelper = 'Например, долг по кредитной карте';
const String accountFormSaveLabel = 'Сохранить';
const String accountFormCurrencyTitle = 'Валюта';
const String accountCurrencyDigitsMismatchText =
    'У счёта с этой валютой другое число знаков после запятой';

/// Валюта строкой: «Российский рубль, ₽»; если символ совпадает с кодом -
/// «Биткоин, BTC».
String accountFormCurrencyValue(CurrencyInfo currency) =>
    currencyNameWithSymbol(currency);

/// То же для формы правки: валюта не меняется.
String accountFormCurrencyLocked(CurrencyInfo currency) =>
    '${accountFormCurrencyValue(currency)} — не меняется';

// Экран счёта (тексты утверждены).
const String accountBalanceCaption = 'Остаток';
const String accountEditButton = 'Изменить';
const String accountAdjustButton = 'Поправить остаток';
const String accountArchiveButton = 'В архив';
const String accountAdjustTitle = 'Поправить остаток';
const String accountAdjustHelper =
    'Операции не изменятся — поменяется только стартовый остаток счёта';
const String accountCancelLabel = 'Отмена';
const String accountUndoAction = 'Вернуть';
const String accountRestoreDuplicateText =
    'Счёт с таким именем уже есть. Переименуйте его или оставьте этот в архиве';

// Архив счетов (тексты утверждены).
const String accountRestoreAction = 'Вернуть из архива';

String accountsArchiveTitle(int count) => 'Архив ($count)';

String accountRestoredMessage(String name) => 'Счёт «$name» снова в списке';

// Основной счёт (тексты утверждены).
const String accountDefaultLabel = 'Основной';
const String accountMakeDefaultButton = 'Сделать основным';
const String accountDefaultHint =
    'Основной счёт — выбирается сам при вводе операции';

String accountArchiveDialogTitle(String name) => 'Отправить «$name» в архив?';

String accountArchiveDialogText(Money balance, CurrencyInfo currency) =>
    'На счёте ${formatMoney(balance, currency: currency)}. Счёт в архиве не входит во «Всего на '
    'счетах». Операции счёта сохранятся';

String accountArchivedMessage(String name) => 'Счёт «$name» в архиве';

/// Подпись значка в сетке для скринридера: «Иконка: Карта». Выбранность
/// сообщает отдельный признак `selected`, в текст её не кладём.
String accountFormIconSemantics(String label) => 'Иконка: $label';

/// Текст ошибки по нарушенному правилу счёта. Про имя и значок — понятные
/// фразы; «не должно случаться» — общий текст сбоя записи.
String accountRuleMessage(AccountRule rule) {
  switch (rule) {
    case AccountRule.emptyName:
      return 'Введите название счёта';
    case AccountRule.nameTooLong:
      return 'Название слишком длинное: не больше $accountNameMaxLength '
          'символов';
    case AccountRule.duplicateName:
      return 'Такой счёт уже есть. Выберите другое название';
    case AccountRule.currencyDigitsMismatch:
      return accountCurrencyDigitsMismatchText;
    case AccountRule.emptyIconKey:
      return 'Выберите иконку';
    case AccountRule.negativeSortOrder:
      return categorySaveFailedText;
  }
}

/// Строка счёта для скринридера: «Карта, остаток 12000 рублей». «Минус» для
/// отрицательной суммы добавляет `spokenMoney`.
String accountRowSemantics(
  String name,
  Money balance,
  CurrencyInfo currency, {
  bool isDefault = false,
}) =>
    '$name, ${isDefault ? 'основной, ' : ''}'
    'остаток ${spokenMoney(balance, currency: currency)}';

/// Одна сумма «Всего» для скринридера; для плюса приставку ставим тут, как в
/// центре кольца «Главной».
String accountsTotalSpoken(Money total, CurrencyInfo currency) {
  final spoken = spokenMoney(total, currency: currency);
  return total.isNegative || total.isZero ? spoken : 'плюс $spoken';
}

/// «Всего на счетах» для скринридера, по валютам через запятую:
/// «Всего на счетах: плюс 12000 рублей, плюс 150 долларов».
String accountsTotalSemantics(List<(Money, CurrencyInfo)> totals) =>
    '$accountsTotalLabel: '
    '${totals.map((t) => accountsTotalSpoken(t.$1, t.$2)).join(', ')}';

// Диалог «Своя валюта» (тексты утверждены).
const String customCurrencyTitle = 'Своя валюта';
const String customCurrencyExplain =
    'Код и число знаков после запятой потом не поменять';
const String customCurrencyCodeLabel = 'Код';
const String customCurrencyCodeHint = 'Например, ABC';
const String customCurrencyCodeError =
    'Код — от 3 до 10 латинских букв и цифр, первая — буква';
const String customCurrencyDigitsLabel = 'Знаков после запятой';
const String customCurrencyDigitsHelper = 'От 0 до 8';
const String customCurrencyDigitsError = 'Введите число от 0 до 8';
const String customCurrencyDone = 'Готово';

/// Подсказка под заблокированным полем знаков: «Как у счёта «Кошелёк»».
String customCurrencyLikeAccount(String name) => 'Как у счёта «$name»';

/// Подсказка под заблокированным полем знаков, если код есть в каталоге.
String customCurrencyInCatalog(String name, int digits) =>
    'Есть в списке: $name. Знаков после запятой: $digits';
