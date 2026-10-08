import 'package:money_app/core/money/currency.dart';
import 'package:money_app/core/money/currency_catalog.dart';
import 'package:money_app/core/money/money.dart';

/// Наибольшая допустимая введённая сумма в основных единицах (рублях):
/// 1 000 000 000 000 (триллион) включительно. Всё, что больше, — ошибка
/// [AmountParseFailure.tooLarge].
const int maxInputMajorUnits = 1000000000000;

/// Предел ввода для любой валюты в минимальных единицах: 10^14 (ADR 0010,
/// п. 16.5). Для рубля это прежний триллион, для BTC — миллион монет.
const int maxInputMinorUnits = 100000000000000;

/// Почему введённый текст не удалось разобрать в сумму.
enum AmountParseFailure {
  /// Пустая строка или одни пробелы.
  empty,

  /// Не число: буквы, «+5», «5 ₽», «1e5», арабские цифры, одиночная запятая.
  notANumber,

  /// Ведущий минус. Направление задаёт тип операции, а не знак суммы.
  negative,

  /// После разделителя больше знаков, чем у валюты (у рубля — двух).
  tooManyDecimals,

  /// Запятых и точек в сумме вместе больше одной.
  tooManySeparators,

  /// Сумма больше [maxInputMinorUnits] минимальных единиц.
  tooLarge,
}

/// Результат разбора: либо сумма, либо причина отказа. Исключений разбор
/// пользовательского текста не бросает.
sealed class AmountParseResult {
  const AmountParseResult();
}

/// Успех: введённый текст превращён в [amount] (ноль или больше).
final class AmountParsed extends AmountParseResult {
  const AmountParsed(this.amount);

  final Money amount;
}

/// Отказ с причиной [failure].
final class AmountParseFailed extends AmountParseResult {
  const AmountParseFailed(this.failure);

  final AmountParseFailure failure;
}

/// Пробельные символы: обычные, переводы строк, а также неразрывный (U+00A0)
/// и узкий неразрывный (U+202F) пробелы — их ставят как разделитель тысяч.
final RegExp _whitespace = RegExp(r'[\s\u00A0\u202F]');

/// Допустимы только ASCII-цифры и два разделителя.
final RegExp _allowedChars = RegExp(r'^[0-9.,]+$');

final RegExp _separator = RegExp(r'[.,]');

const String _asciiMinus = '-';
const String _unicodeMinus = '\u2212';

/// Разбирает введённую пользователем сумму в [Money] в валюте [currency].
///
/// Порядок проверок (первая сработавшая определяет ответ):
/// 1. Все пробельные символы (по краям и внутри) выбрасываются.
/// 2. Пусто — [AmountParseFailure.empty].
/// 3. Ведущий минус (`-` или `\u2212`): если остаток состоит только из цифр и
///    разделителей (или пуст) — [AmountParseFailure.negative]; если в остатке
///    есть посторонние символы — [AmountParseFailure.notANumber].
/// 4. Посторонние символы — [AmountParseFailure.notANumber].
/// 5. Больше одного разделителя — [AmountParseFailure.tooManySeparators].
/// 6. Больше двух цифр после разделителя — [AmountParseFailure.tooManyDecimals]
///    (лишние цифры не отбрасываются молча).
/// 7. Ни одной цифры (`,` или `.`) — [AmountParseFailure.notANumber].
/// 8. Сумма больше [maxInputMajorUnits] — [AmountParseFailure.tooLarge].
///
/// Допустимо: `5,` даёт 5,00; `,5` даёт 0,50; `0` даёт ноль; лишние нули
/// впереди (`00012,3`) не мешают. Разбор не «угадывает»: неоднозначный ввод
/// вроде `1.234` — ошибка, а не 1,23 и не 1234.
///
/// Знаков после разделителя — сколько у валюты ([currencyInfo], по умолчанию
/// запись каталога по коду [currency]); для своей валюты передайте её
/// [CurrencyInfo]. Сумма собирается целыми (`BigInt`), без дробных чисел.
///
/// Неверный код [currency] — ошибка программиста, а не пользователя:
/// [Money] бросит `ArgumentError`.
AmountParseResult parseAmount(
  String input, {
  String currency = rubCurrencyCode,
  CurrencyInfo? currencyInfo,
}) {
  assert(
    currencyInfo == null || currencyInfo.code == currency,
    'currencyInfo ${currencyInfo.code} does not match currency $currency',
  );
  final digits = (currencyInfo ?? currencyInfoFor(currency)).digits;
  final text = input.replaceAll(_whitespace, '');
  if (text.isEmpty) {
    return const AmountParseFailed(AmountParseFailure.empty);
  }

  if (text.startsWith(_asciiMinus) || text.startsWith(_unicodeMinus)) {
    final rest = text.substring(1);
    if (rest.isEmpty || _allowedChars.hasMatch(rest)) {
      return const AmountParseFailed(AmountParseFailure.negative);
    }
    return const AmountParseFailed(AmountParseFailure.notANumber);
  }

  if (!_allowedChars.hasMatch(text)) {
    return const AmountParseFailed(AmountParseFailure.notANumber);
  }

  final separatorCount = _separator.allMatches(text).length;
  if (separatorCount > 1) {
    return const AmountParseFailed(AmountParseFailure.tooManySeparators);
  }

  final parts = text.split(_separator);
  final wholeText = parts[0];
  final decimalsText = parts.length > 1 ? parts[1] : '';

  if (decimalsText.length > digits) {
    return const AmountParseFailed(AmountParseFailure.tooManyDecimals);
  }
  if (wholeText.isEmpty && decimalsText.isEmpty) {
    return const AmountParseFailed(AmountParseFailure.notANumber);
  }

  // Целая часть может быть сколь угодно длинной, поэтому сначала считаем
  // в BigInt (не переполняется) и только после проверки предела переходим
  // к обычному int.
  final whole = wholeText.isEmpty ? BigInt.zero : BigInt.parse(wholeText);
  final fraction = decimalsText.isEmpty
      ? BigInt.zero
      : BigInt.parse(decimalsText.padRight(digits, '0'));
  final totalMinor = whole * BigInt.from(10).pow(digits) + fraction;
  if (totalMinor > BigInt.from(maxInputMinorUnits)) {
    return const AmountParseFailed(AmountParseFailure.tooLarge);
  }

  return AmountParsed(Money.fromMinor(totalMinor.toInt(), currency));
}
