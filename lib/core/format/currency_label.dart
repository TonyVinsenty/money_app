import 'package:money_app/core/money/currency_catalog.dart';

/// Валюта строкой: «Российский рубль, ₽»; если символ совпадает с кодом -
/// «Биткоин, BTC».
String currencyNameWithSymbol(CurrencyInfo currency) =>
    '${currency.name}, ${currency.symbol}';
