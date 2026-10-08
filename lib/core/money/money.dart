import 'package:money_app/core/money/currency.dart';

/// Денежная сумма: целое число минорных единиц (копеек) и код валюты.
///
/// Почему целые: дробные числа не могут точно хранить многие десятичные
/// значения (0,1 + 0,2 не равно 0,3), а в деньгах копейка не должна теряться.
/// Целое число копеек считается точно. Форматирование «123,45 ₽» живёт на
/// границе UI (шаг 1.9), здесь его нет.
///
/// Сумма может быть отрицательной (остаток по источнику, «доходы минус
/// расходы»). Хранимые суммы операций положительны, направление задаёт
/// отдельное поле (ADR 0004).
///
/// Допущение: переполнение целого в Dart молчаливое (значение «заворачивается»
/// в отрицательное). Для личных финансов оно недостижимо (предел около
/// 92 квадриллионов рублей), но текущее поведение зафиксировано тестом.
/// То же относится к `allocate` и `dividedBy` на суммах, близких к границам
/// целого (в том числе минимальное значение `int`: у него `abs()` остаётся
/// отрицательным). Это вне зоны честной работы и не поддерживается.
final class Money implements Comparable<Money> {
  /// Основной конструктор. Не `const`: код валюты проверяется при каждом
  /// создании, а `const`-конструктор не может вызывать функции. Проверка
  /// важнее `const`: неверный код не должен попасть в данные.
  Money.fromMinor(this.minorUnits, String currency)
    : currency = _checkedCurrency(currency);

  /// Ноль в заданной валюте.
  Money.zero(String currency) : this.fromMinor(0, currency);

  /// Из целых рублей и копеек: `fromMajorParts(123, 45, 'RUB')` — это 123,45.
  ///
  /// Только для неотрицательных сумм: [major] >= 0, [minor] в диапазоне 0..99.
  /// Для отрицательных используйте [Money.fromMinor] или унарный минус.
  /// Число знаков после запятой (2) зашито под рубль, доллар, евро (ADR 0004).
  factory Money.fromMajorParts(int major, int minor, String currency) {
    if (major < 0) {
      throw ArgumentError.value(major, 'major', 'Must be >= 0');
    }
    if (minor < 0 || minor > 99) {
      throw ArgumentError.value(minor, 'minor', 'Must be in 0..99');
    }
    // Проверка стоит ДО умножения: после переполнения число уже «завернулось»
    // в отрицательное, и поймать это постфактум нельзя.
    if (major > (_maxInt - minor) ~/ 100) {
      throw ArgumentError.value(major, 'major', 'Too large');
    }
    return Money.fromMinor(major * 100 + minor, currency);
  }

  /// Наибольшее 64-битное целое (2^63 - 1) для проверки границы.
  static const int _maxInt = 0x7FFFFFFFFFFFFFFF;

  /// Внутренний конструктор для результатов операций: валюта уже проверена
  /// у исходной суммы, повторно проверять незачем.
  const Money._(this.minorUnits, this.currency);

  /// Сумма в копейках.
  final int minorUnits;

  /// Код валюты: 3-10 заглавных латинских букв и цифр, первая буква (ISO 4217, крипта, своя валюта;
  /// ADR 0010, п. 16.3), например `RUB`.
  final String currency;

  bool get isZero => minorUnits == 0;

  bool get isNegative => minorUnits < 0;

  /// Сложение. Разные валюты — [ArgumentError], а не молчаливый результат.
  Money operator +(Money other) {
    _requireSameCurrency(other);
    return Money._(minorUnits + other.minorUnits, currency);
  }

  /// Вычитание. Разные валюты — [ArgumentError].
  Money operator -(Money other) {
    _requireSameCurrency(other);
    return Money._(minorUnits - other.minorUnits, currency);
  }

  /// Унарный минус: `-Money.fromMinor(5, 'RUB')` даёт -5 копеек.
  Money operator -() => Money._(-minorUnits, currency);

  /// Умножение на целое, например «×3 месяца».
  Money operator *(int factor) => Money._(minorUnits * factor, currency);

  /// Сравнение по копейкам. Разные валюты — [ArgumentError]: молча сравнивать
  /// рубли с долларами нельзя.
  @override
  int compareTo(Money other) {
    _requireSameCurrency(other);
    return minorUnits.compareTo(other.minorUnits);
  }

  bool operator <(Money other) => compareTo(other) < 0;

  bool operator >(Money other) => compareTo(other) > 0;

  bool operator <=(Money other) => compareTo(other) <= 0;

  bool operator >=(Money other) => compareTo(other) >= 0;

  /// Делит сумму на [parts] частей без потери копеек (метод наибольших
  /// остатков): 100,00 на 3 даёт 33,34 / 33,33 / 33,33.
  ///
  /// Каждая часть получает целую долю, а оставшиеся копейки раздаются по одной
  /// первым частям. Сумма частей всегда равна исходной. Для отрицательной
  /// суммы делится модуль, затем знак возвращается: части отрицательные,
  /// лишняя копейка тоже достаётся первым частям.
  List<Money> allocate(int parts) {
    if (parts < 1) {
      throw ArgumentError.value(parts, 'parts', 'Must be >= 1');
    }
    final absolute = minorUnits.abs();
    final base = absolute ~/ parts;
    final remainder = absolute % parts;
    final sign = isNegative ? -1 : 1;
    return List<Money>.generate(
      parts,
      (index) => Money._(sign * (base + (index < remainder ? 1 : 0)), currency),
      growable: false,
    );
  }

  /// Деление на [divisor] с округлением «половина от нуля»: 0,5 даёт 1,
  /// -0,5 даёт -1. Считается целыми числами, без дробных.
  ///
  /// Делитель должен быть положительным: при отрицательном смещение половины
  /// меняет знак, и округление уезжает. Проверка — исключение, а не `assert`,
  /// чтобы защита работала и в релизной сборке.
  Money dividedBy(int divisor) {
    if (divisor <= 0) {
      throw ArgumentError.value(divisor, 'divisor', 'Must be > 0');
    }
    // Оператор ~/ отбрасывает дробную часть в сторону нуля, поэтому для
    // отрицательных сумм половину нужно вычитать, а не прибавлять.
    final half = divisor ~/ 2;
    final shifted = isNegative ? minorUnits - half : minorUnits + half;
    return Money._(shifted ~/ divisor, currency);
  }

  @override
  bool operator ==(Object other) =>
      other is Money &&
      other.minorUnits == minorUnits &&
      other.currency == currency;

  @override
  int get hashCode => Object.hash(minorUnits, currency);

  /// Для отладки и сообщений об ошибках, например `Money(12345 RUB)`.
  @override
  String toString() => 'Money($minorUnits $currency)';

  void _requireSameCurrency(Money other) {
    if (other.currency != currency) {
      throw ArgumentError('Currency mismatch: $currency and ${other.currency}');
    }
  }

  static String _checkedCurrency(String code) {
    if (!isValidCurrencyCode(code)) {
      throw ArgumentError.value(
        code,
        'currency',
        'Must be 3 uppercase Latin letters (ISO 4217)',
      );
    }
    return code;
  }
}
