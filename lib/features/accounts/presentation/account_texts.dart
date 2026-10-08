import 'package:money_app/core/format/money_spoken.dart';
import 'package:money_app/core/money/money.dart';

// Черновик текстов раздела «Счета»: пользователь их ещё утверждает.

const String accountsSectionTitle = 'Счета';
const String accountsTotalLabel = 'Всего на счетах';
const String accountsEmptyText =
    'Добавьте счёт: карту, наличные, вклад — и укажите, сколько на нём сейчас';
const String accountsAddButton = 'Добавить счёт';
const String accountsLoadError = 'Не удалось загрузить счета';

/// Строка счёта для скринридера: «Карта, остаток 12000 рублей». «Минус» для
/// отрицательной суммы добавляет `spokenMoney`.
String accountRowSemantics(String name, Money balance) =>
    '$name, остаток ${spokenMoney(balance)}';

/// «Всего на счетах» для скринридера; для плюса приставку ставим тут, как в
/// центре кольца «Главной».
String accountsTotalSemantics(Money total) => total.isNegative || total.isZero
    ? '$accountsTotalLabel: ${spokenMoney(total)}'
    : '$accountsTotalLabel: плюс ${spokenMoney(total)}';
