import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/format/money_spoken.dart';
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

String accountArchiveDialogTitle(String name) => 'Отправить «$name» в архив?';

String accountArchiveDialogText(Money balance) =>
    'На счёте ${formatMoney(balance)}. Счёт в архиве не входит во «Всего на '
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
    case AccountRule.emptyIconKey:
      return 'Выберите иконку';
    case AccountRule.negativeSortOrder:
      return categorySaveFailedText;
  }
}

/// Строка счёта для скринридера: «Карта, остаток 12000 рублей». «Минус» для
/// отрицательной суммы добавляет `spokenMoney`.
String accountRowSemantics(String name, Money balance) =>
    '$name, остаток ${spokenMoney(balance)}';

/// «Всего на счетах» для скринридера; для плюса приставку ставим тут, как в
/// центре кольца «Главной».
String accountsTotalSemantics(Money total) => total.isNegative || total.isZero
    ? '$accountsTotalLabel: ${spokenMoney(total)}'
    : '$accountsTotalLabel: плюс ${spokenMoney(total)}';
