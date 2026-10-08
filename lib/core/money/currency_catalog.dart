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

/// Популярные валюты и криптовалюты: идут в каталоге первыми.
/// Остальные обычные валюты - в [_fiatRows].
const List<CurrencyInfo> _popular = <CurrencyInfo>[
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

/// Остальные действующие обычные валюты ISO 4217 (ADR 0010, п. 16.1): код,
/// знаков после запятой (как в CLDR/`intl`; тест сверяет), название, символ
/// (`null` - показывается код). Без фондовых и служебных X-кодов.
const List<(String, int, String, String?)> _fiatRows =
    <(String, int, String, String?)>[
      ('AED', 2, 'Дирхам ОАЭ', null),
      ('AFN', 0, 'Афгани', null),
      ('ALL', 0, 'Албанский лек', null),
      ('AMD', 2, 'Армянский драм', '֏'),
      ('ANG', 2, 'Нидерландский антильский гульден', null),
      ('AOA', 2, 'Ангольская кванза', null),
      ('ARS', 2, 'Аргентинское песо', null),
      ('AUD', 2, 'Австралийский доллар', null),
      ('AWG', 2, 'Арубанский флорин', null),
      ('AZN', 2, 'Азербайджанский манат', '₼'),
      ('BAM', 2, 'Конвертируемая марка', null),
      ('BBD', 2, 'Барбадосский доллар', null),
      ('BDT', 2, 'Бангладешская така', null),
      ('BGN', 2, 'Болгарский лев', null),
      ('BHD', 3, 'Бахрейнский динар', null),
      ('BIF', 0, 'Бурундийский франк', null),
      ('BMD', 2, 'Бермудский доллар', null),
      ('BND', 2, 'Брунейский доллар', null),
      ('BOB', 2, 'Боливиано', null),
      ('BRL', 2, 'Бразильский реал', null),
      ('BSD', 2, 'Багамский доллар', null),
      ('BTN', 2, 'Бутанский нгултрум', null),
      ('BWP', 2, 'Ботсванская пула', null),
      ('BYN', 2, 'Белорусский рубль', null),
      ('BZD', 2, 'Белизский доллар', null),
      ('CAD', 2, 'Канадский доллар', null),
      ('CDF', 2, 'Конголезский франк', null),
      ('CHF', 2, 'Швейцарский франк', null),
      ('CLP', 0, 'Чилийское песо', null),
      ('COP', 0, 'Колумбийское песо', null),
      ('CRC', 2, 'Коста-риканский колон', null),
      ('CUP', 2, 'Кубинское песо', null),
      ('CVE', 2, 'Эскудо Кабо-Верде', null),
      ('CZK', 2, 'Чешская крона', null),
      ('DJF', 0, 'Франк Джибути', null),
      ('DKK', 2, 'Датская крона', null),
      ('DOP', 2, 'Доминиканское песо', null),
      ('DZD', 2, 'Алжирский динар', null),
      ('EGP', 2, 'Египетский фунт', null),
      ('ERN', 2, 'Эритрейская накфа', null),
      ('ETB', 2, 'Эфиопский быр', null),
      ('FJD', 2, 'Доллар Фиджи', null),
      ('FKP', 2, 'Фунт Фолклендских островов', null),
      ('GBP', 2, 'Фунт стерлингов', '£'),
      ('GEL', 2, 'Грузинский лари', '₾'),
      ('GHS', 2, 'Ганский седи', null),
      ('GIP', 2, 'Гибралтарский фунт', null),
      ('GMD', 2, 'Гамбийский даласи', null),
      ('GNF', 0, 'Гвинейский франк', null),
      ('GTQ', 2, 'Гватемальский кетсаль', null),
      ('GYD', 2, 'Гайанский доллар', null),
      ('HKD', 2, 'Гонконгский доллар', null),
      ('HNL', 2, 'Гондурасская лемпира', null),
      ('HTG', 2, 'Гаитянский гурд', null),
      ('HUF', 0, 'Венгерский форинт', null),
      ('IDR', 0, 'Индонезийская рупия', null),
      ('ILS', 2, 'Израильский шекель', '₪'),
      ('INR', 2, 'Индийская рупия', '₹'),
      ('IQD', 0, 'Иракский динар', null),
      ('IRR', 0, 'Иранский риал', null),
      ('ISK', 0, 'Исландская крона', null),
      ('JMD', 2, 'Ямайский доллар', null),
      ('JOD', 3, 'Иорданский динар', null),
      ('JPY', 0, 'Японская иена', null),
      ('KES', 2, 'Кенийский шиллинг', null),
      ('KGS', 2, 'Киргизский сом', null),
      ('KHR', 2, 'Камбоджийский риель', null),
      ('KMF', 0, 'Коморский франк', null),
      ('KPW', 0, 'Севернокорейская вона', null),
      ('KRW', 0, 'Южнокорейская вона', '₩'),
      ('KWD', 3, 'Кувейтский динар', null),
      ('KYD', 2, 'Доллар Островов Кайман', null),
      ('KZT', 2, 'Казахстанский тенге', '₸'),
      ('LAK', 0, 'Лаосский кип', null),
      ('LBP', 0, 'Ливанский фунт', null),
      ('LKR', 2, 'Шри-ланкийская рупия', null),
      ('LRD', 2, 'Либерийский доллар', null),
      ('LSL', 2, 'Лоти Лесото', null),
      ('LYD', 3, 'Ливийский динар', null),
      ('MAD', 2, 'Марокканский дирхам', null),
      ('MDL', 2, 'Молдавский лей', null),
      ('MGA', 0, 'Малагасийский ариари', null),
      ('MKD', 2, 'Македонский денар', null),
      ('MMK', 0, 'Мьянманский кьят', null),
      ('MNT', 2, 'Монгольский тугрик', '₮'),
      ('MOP', 2, 'Патака Макао', null),
      ('MRU', 2, 'Мавританская угия', null),
      ('MUR', 2, 'Маврикийская рупия', null),
      ('MVR', 2, 'Мальдивская руфия', null),
      ('MWK', 2, 'Малавийская квача', null),
      ('MXN', 2, 'Мексиканское песо', null),
      ('MYR', 2, 'Малайзийский ринггит', null),
      ('MZN', 2, 'Мозамбикский метикал', null),
      ('NAD', 2, 'Намибийский доллар', null),
      ('NGN', 2, 'Нигерийская найра', '₦'),
      ('NIO', 2, 'Никарагуанская кордоба', null),
      ('NOK', 2, 'Норвежская крона', null),
      ('NPR', 2, 'Непальская рупия', null),
      ('NZD', 2, 'Новозеландский доллар', null),
      ('OMR', 3, 'Оманский риал', null),
      ('PAB', 2, 'Панамский бальбоа', null),
      ('PEN', 2, 'Перуанский соль', null),
      ('PGK', 2, 'Кина Папуа - Новой Гвинеи', null),
      ('PHP', 2, 'Филиппинское песо', '₱'),
      ('PKR', 0, 'Пакистанская рупия', null),
      ('PLN', 2, 'Польский злотый', null),
      ('PYG', 0, 'Парагвайский гуарани', null),
      ('QAR', 2, 'Катарский риал', null),
      ('RON', 2, 'Румынский лей', null),
      ('RSD', 0, 'Сербский динар', null),
      ('RWF', 0, 'Франк Руанды', null),
      ('SAR', 2, 'Саудовский риял', null),
      ('SBD', 2, 'Доллар Соломоновых Островов', null),
      ('SCR', 2, 'Сейшельская рупия', null),
      ('SDG', 2, 'Суданский фунт', null),
      ('SEK', 2, 'Шведская крона', null),
      ('SGD', 2, 'Сингапурский доллар', null),
      ('SHP', 2, 'Фунт Святой Елены', null),
      ('SLE', 2, 'Леоне Сьерра-Леоне', null),
      ('SOS', 0, 'Сомалийский шиллинг', null),
      ('SRD', 2, 'Суринамский доллар', null),
      ('SSP', 2, 'Южносуданский фунт', null),
      ('STN', 2, 'Добра Сан-Томе и Принсипи', null),
      ('SVC', 2, 'Сальвадорский колон', null),
      ('SYP', 0, 'Сирийский фунт', null),
      ('SZL', 2, 'Свазилендский лилангени', null),
      ('THB', 2, 'Таиландский бат', '฿'),
      ('TJS', 2, 'Таджикский сомони', null),
      ('TMT', 2, 'Туркменский манат', null),
      ('TND', 3, 'Тунисский динар', null),
      ('TOP', 2, 'Тонганская паанга', null),
      ('TRY', 2, 'Турецкая лира', '₺'),
      ('TTD', 2, 'Доллар Тринидада и Тобаго', null),
      ('TWD', 2, 'Новый тайваньский доллар', null),
      ('TZS', 2, 'Танзанийский шиллинг', null),
      ('UAH', 2, 'Украинская гривна', '₴'),
      ('UGX', 0, 'Угандийский шиллинг', null),
      ('UYU', 2, 'Уругвайское песо', null),
      ('UZS', 2, 'Узбекский сум', null),
      ('VES', 2, 'Венесуэльский боливар', null),
      ('VND', 0, 'Вьетнамский донг', '₫'),
      ('VUV', 0, 'Вату Вануату', null),
      ('WST', 2, 'Самоанская тала', null),
      ('XAF', 0, 'Франк КФА BEAC', null),
      ('XCD', 2, 'Восточно-карибский доллар', null),
      ('XOF', 0, 'Франк КФА BCEAO', null),
      ('XPF', 0, 'Франк КФП', null),
      ('YER', 0, 'Йеменский риал', null),
      ('ZAR', 2, 'Южноафриканский рэнд', null),
      ('ZMW', 2, 'Замбийская квача', null),
      ('ZWG', 2, 'Зимбабвийское золото', null),
    ];

/// Слова озвучки (1 / 2-4 / 5+) для остальных валют, чьё название - одно
/// склоняемое слово (ADR 0010, п. 16.1).
const Map<String, ({String one, String few, String many})> _fiatForms =
    <String, ({String one, String few, String many})>{
      'GBP': (one: 'фунт', few: 'фунта', many: 'фунтов'),
      'JPY': (one: 'иена', few: 'иены', many: 'иен'),
      'KZT': (one: 'тенге', few: 'тенге', many: 'тенге'),
      'GEL': (one: 'лари', few: 'лари', many: 'лари'),
      'AMD': (one: 'драм', few: 'драма', many: 'драмов'),
      'UZS': (one: 'сум', few: 'сума', many: 'сумов'),
      'KGS': (one: 'сом', few: 'сома', many: 'сомов'),
      'AZN': (one: 'манат', few: 'маната', many: 'манатов'),
      'TMT': (one: 'манат', few: 'маната', many: 'манатов'),
    };

/// Каталог валют: популярные первыми, затем остальные обычные по алфавиту.
final List<CurrencyInfo> currencyCatalog = List<CurrencyInfo>.unmodifiable(
  <CurrencyInfo>[
    ..._popular,
    for (final (code, digits, name, symbol) in _fiatRows)
      CurrencyInfo(
        code: code,
        digits: digits,
        symbol: symbol ?? code,
        name: name,
        kind: CurrencyKind.fiat,
        forms: _fiatForms[code],
      ),
  ],
);

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
