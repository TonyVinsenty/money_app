import 'package:money_app/core/money/currency.dart';

/// Вид валюты (ADR 0010, п. 16.1).
enum CurrencyKind {
  /// Обычная валюта (ISO 4217): все знаки после запятой показываются всегда.
  fiat,

  /// Криптовалюта: лишние нули в конце срезаются (не меньше двух знаков).
  crypto,

  /// Своя валюта пользователя: нет в каталоге, символ и название - сам код.
  custom,
}

/// Описание валюты: сколько знаков после запятой, как показать и как озвучить.
///
/// `digits` - число знаков после запятой. В базе сумма всегда целое число
/// самых мелких единиц, поэтому `digits` однажды выпущенной валюты менять
/// нельзя: суммы молча «поедут».
final class CurrencyInfo {
  const CurrencyInfo({
    required this.code,
    required this.digits,
    required this.symbol,
    required this.name,
    required this.kind,
    this.forms,
  });

  /// Код валюты (`RUB`, `BTC`).
  final String code;

  /// Знаков после запятой (0-8).
  final int digits;

  /// Символ для экрана: «₽», «$»; если привычного нет - сам код.
  final String symbol;

  /// Название по-русски.
  final String name;

  /// Вид валюты.
  final CurrencyKind kind;

  /// Три формы слова для озвучки (1 / 2-4 / 5+), если название - одно
  /// склоняемое слово; иначе `null`.
  final ({String one, String few, String many})? forms;
}

const _crypto = CurrencyKind.crypto;
const _fiat = CurrencyKind.fiat;

/// Каталог валют. Пока только популярные; остальные добавляются отдельным
/// шагом (ADR 0010, п. 16.1).
const List<CurrencyInfo> currencyCatalog = <CurrencyInfo>[
  CurrencyInfo(
    code: 'RUB',
    digits: 2,
    symbol: '₽',
    name: 'Российский рубль',
    kind: _fiat,
    forms: (one: 'рубль', few: 'рубля', many: 'рублей'),
  ),
  CurrencyInfo(
    code: 'USD',
    digits: 2,
    symbol: r'$',
    name: 'Доллар США',
    kind: _fiat,
    forms: (one: 'доллар', few: 'доллара', many: 'долларов'),
  ),
  CurrencyInfo(
    code: 'EUR',
    digits: 2,
    symbol: '€',
    name: 'Евро',
    kind: _fiat,
    forms: (one: 'евро', few: 'евро', many: 'евро'),
  ),
  CurrencyInfo(
    code: 'CNY',
    digits: 2,
    symbol: '¥',
    name: 'Китайский юань',
    kind: _fiat,
    forms: (one: 'юань', few: 'юаня', many: 'юаней'),
  ),
  CurrencyInfo(
    code: 'BTC',
    digits: 8,
    symbol: 'BTC',
    name: 'Биткоин',
    kind: _crypto,
    forms: (one: 'биткоин', few: 'биткоина', many: 'биткоинов'),
  ),
  CurrencyInfo(
    code: 'ETH',
    digits: 8,
    symbol: 'ETH',
    name: 'Эфир',
    kind: _crypto,
    forms: (one: 'эфир', few: 'эфира', many: 'эфиров'),
  ),
  CurrencyInfo(
    code: 'USDT',
    digits: 8,
    symbol: 'USDT',
    name: 'Tether',
    kind: _crypto,
  ),
  CurrencyInfo(
    code: 'USDC',
    digits: 8,
    symbol: 'USDC',
    name: 'USD Coin',
    kind: _crypto,
  ),
  CurrencyInfo(
    code: 'TON',
    digits: 8,
    symbol: 'TON',
    name: 'Toncoin',
    kind: _crypto,
  ),
  CurrencyInfo(
    code: 'BNB',
    digits: 8,
    symbol: 'BNB',
    name: 'BNB',
    kind: _crypto,
  ),
  CurrencyInfo(
    code: 'SOL',
    digits: 8,
    symbol: 'SOL',
    name: 'Solana',
    kind: _crypto,
  ),
  CurrencyInfo(
    code: 'XRP',
    digits: 8,
    symbol: 'XRP',
    name: 'XRP',
    kind: _crypto,
  ),
  CurrencyInfo(
    code: 'TRX',
    digits: 8,
    symbol: 'TRX',
    name: 'TRON',
    kind: _crypto,
  ),
  CurrencyInfo(
    code: 'DOGE',
    digits: 8,
    symbol: 'DOGE',
    name: 'Dogecoin',
    kind: _crypto,
  ),
  CurrencyInfo(
    code: 'LTC',
    digits: 8,
    symbol: 'LTC',
    name: 'Litecoin',
    kind: _crypto,
  ),
];

final Map<String, CurrencyInfo> _byCode = <String, CurrencyInfo>{
  for (final info in currencyCatalog) info.code: info,
};

/// Запись каталога по коду; `null`, если такой валюты в каталоге нет.
CurrencyInfo? catalogCurrency(String code) => _byCode[code];

/// Описание валюты по коду: запись каталога или своя валюта.
///
/// Для кода из каталога берётся его запись, [digits] игнорируется. Для
/// остальных кодов [digits] обязателен (0-8): символ и название - сам код.
/// Без [digits] срабатывает `assert`; в релизной сборке берётся 2 знака.
CurrencyInfo currencyInfoFor(String code, {int? digits}) {
  final known = _byCode[code];
  if (known != null) return known;
  assert(
    digits != null,
    'Currency $code is not in the catalog: digits are required',
  );
  assert(isValidCurrencyCode(code), 'Invalid currency code: $code');
  return CurrencyInfo(
    code: code,
    digits: digits ?? 2,
    symbol: code,
    name: code,
    kind: CurrencyKind.custom,
  );
}
