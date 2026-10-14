import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/format/axis_tick.dart';
import 'package:money_app/core/money/money.dart';

String _tick(int major) => formatAxisTick(Money.fromMinor(major * 100, 'RUB'));

void main() {
  final nbsp = String.fromCharCode(0x00A0);

  test('малые значения без суффикса', () {
    expect(_tick(0), '0');
    expect(_tick(500), '500');
    expect(_tick(999), '999');
    expect(_tick(1000), '1${nbsp}000');
  });

  test('тысячи', () {
    expect(_tick(250000), '250$nbspтыс.');
    expect(_tick(200000), '200$nbspтыс.');
    expect(_tick(12500), '12,5$nbspтыс.');
  });

  test('миллионы и больше', () {
    expect(_tick(1500000), '1,5$nbspмлн');
    expect(_tick(2000000), '2$nbspмлн');
    expect(_tick(10000000000), '10${nbsp}000$nbspмлн');
  });

  test('перед «тыс.» неразрывный пробел (код 0xA0)', () {
    final text = _tick(250000);
    expect(text.codeUnitAt(text.indexOf('т') - 1), 0xA0);
  });

  test('копейки отбрасываются, знака валюты нет', () {
    expect(formatAxisTick(Money.fromMinor(99999, 'RUB')), '999');
    expect(formatAxisTick(Money.fromMinor(500, 'USD')), '5');
  });
}
