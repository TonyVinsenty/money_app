import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/money/currency.dart';
import 'package:money_app/core/money/money.dart';

Money rub(int minor) => Money.fromMinor(minor, 'RUB');

Money usd(int minor) => Money.fromMinor(minor, 'USD');

void main() {
  group('создание', () {
    test('zero даёт ноль в нужной валюте', () {
      final zero = Money.zero('RUB');
      expect(zero.minorUnits, 0);
      expect(zero.currency, 'RUB');
      expect(zero.isZero, isTrue);
    });

    test('fromMinor хранит копейки как есть, в том числе отрицательные', () {
      expect(rub(12345).minorUnits, 12345);
      expect(rub(-5).minorUnits, -5);
      expect(rub(12345).currency, 'RUB');
    });

    test('fromMajorParts: 123,45 это 12345 копеек', () {
      expect(Money.fromMajorParts(123, 45, 'RUB'), rub(12345));
    });

    test('fromMajorParts: граничные значения', () {
      expect(Money.fromMajorParts(0, 0, 'RUB'), rub(0));
      expect(Money.fromMajorParts(0, 5, 'RUB'), rub(5));
      expect(Money.fromMajorParts(1, 99, 'RUB'), rub(199));
    });

    test('fromMajorParts: самый большой допустимый major проходит', () {
      // Литерал 9223372036854775807 работает только на VM, как и ниже.
      const maxInt = 9223372036854775807;
      final maxMajor99 = (maxInt - 99) ~/ 100;
      final big = Money.fromMajorParts(maxMajor99, 99, 'RUB');
      expect(big.minorUnits, maxMajor99 * 100 + 99);
      expect(big.minorUnits, isPositive);

      final maxMajor0 = maxInt ~/ 100;
      final big0 = Money.fromMajorParts(maxMajor0, 0, 'RUB');
      expect(big0.minorUnits, maxMajor0 * 100);
      expect(big0.minorUnits, isPositive);
    });

    test(
      'fromMajorParts: на 1 больше границы это ошибка, а не переполнение',
      () {
        const maxInt = 9223372036854775807;
        expect(
          () => Money.fromMajorParts((maxInt - 99) ~/ 100 + 1, 99, 'RUB'),
          throwsA(isA<ArgumentError>()),
        );
        expect(
          () => Money.fromMajorParts(maxInt ~/ 100 + 1, 0, 'RUB'),
          throwsA(isA<ArgumentError>()),
        );
      },
    );

    test('fromMajorParts: копеек 100 или больше это ошибка', () {
      expect(
        () => Money.fromMajorParts(1, 100, 'RUB'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('fromMajorParts: отрицательные копейки это ошибка', () {
      expect(
        () => Money.fromMajorParts(1, -1, 'RUB'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('fromMajorParts: отрицательные рубли это ошибка', () {
      expect(
        () => Money.fromMajorParts(-1, 0, 'RUB'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('невалидный код валюты это ошибка во всех конструкторах', () {
      const bad = [
        '',
        'rub',
        'RU',
        'US',
        'usdt',
        '1AB',
        '1BTC',
        'US-D',
        'RU ',
        'РУБ',
        'ABCDEFGHIJK', // 11 символов
      ];
      for (final code in bad) {
        expect(
          () => Money.fromMinor(1, code),
          throwsA(isA<ArgumentError>()),
          reason: 'fromMinor с кодом "$code"',
        );
        expect(
          () => Money.zero(code),
          throwsA(isA<ArgumentError>()),
          reason: 'zero с кодом "$code"',
        );
        expect(
          () => Money.fromMajorParts(1, 0, code),
          throwsA(isA<ArgumentError>()),
          reason: 'fromMajorParts с кодом "$code"',
        );
      }
    });

    test('Money принимает коды из 3-10 символов: USDT, TON, BTC2', () {
      for (final code in ['USDT', 'TON', 'BTC2', 'ABCDEFGHIJ']) {
        expect(Money.fromMinor(5, code).currency, code);
        expect(Money.zero(code).currency, code);
      }
    });

    test('isIsoCurrencyCode: ровно три заглавные буквы', () {
      expect(isIsoCurrencyCode('RUB'), isTrue);
      expect(isIsoCurrencyCode('USDT'), isFalse);
      expect(isIsoCurrencyCode('BTC2'), isFalse);
      expect(isIsoCurrencyCode('rub'), isFalse);
      expect(isIsoCurrencyCode('RU'), isFalse);
      expect(isIsoCurrencyCode('RUB\n'), isFalse);
    });

    test('rubCurrencyCode и isValidCurrencyCode', () {
      expect(rubCurrencyCode, 'RUB');
      expect(isValidCurrencyCode(rubCurrencyCode), isTrue);
      expect(isValidCurrencyCode('USD'), isTrue);
      expect(isValidCurrencyCode('rub'), isFalse);
      expect(isValidCurrencyCode('RUB\n'), isFalse);
    });

    test('toString показывает копейки и валюту', () {
      expect(rub(12345).toString(), 'Money(12345 RUB)');
      expect(usd(-7).toString(), 'Money(-7 USD)');
    });
  });

  group('арифметика', () {
    test('сложение', () {
      expect(rub(100) + rub(250), rub(350));
    });

    test('вычитание, в том числе в минус', () {
      expect(rub(500) - rub(200), rub(300));
      expect(rub(200) - rub(500), rub(-300));
    });

    test('унарный минус', () {
      expect(-rub(5), rub(-5));
      expect(-rub(-5), rub(5));
      expect(-rub(0), rub(0));
    });

    test('умножение на целое', () {
      expect(rub(250) * 3, rub(750));
      expect(rub(250) * 0, rub(0));
      expect(rub(250) * -2, rub(-500));
      expect(rub(-250) * -2, rub(500));
      expect(rub(250) * 1, rub(250));
    });

    test('операции сохраняют валюту', () {
      expect((usd(1) + usd(2)).currency, 'USD');
      expect((usd(3) - usd(2)).currency, 'USD');
      expect((-usd(3)).currency, 'USD');
      expect((usd(3) * 2).currency, 'USD');
    });

    test('операции не меняют исходные значения', () {
      final a = rub(100);
      final b = rub(50);
      final results = [a + b, a - b, -a, a * 3];
      expect(results, [rub(150), rub(50), rub(-100), rub(300)]);
      expect(a, rub(100));
      expect(b, rub(50));
    });

    test('ноль нейтрален для сложения', () {
      expect(rub(123) + Money.zero('RUB'), rub(123));
    });

    test('isZero и isNegative', () {
      expect(rub(0).isZero, isTrue);
      expect(rub(0).isNegative, isFalse);
      expect(rub(1).isZero, isFalse);
      expect(rub(1).isNegative, isFalse);
      expect(rub(-1).isZero, isFalse);
      expect(rub(-1).isNegative, isTrue);
    });
  });

  group('смешение валют', () {
    test('сложение RUB и USD это ошибка', () {
      expect(() => rub(100) + usd(100), throwsA(isA<ArgumentError>()));
    });

    test('вычитание RUB и USD это ошибка', () {
      expect(() => rub(100) - usd(100), throwsA(isA<ArgumentError>()));
    });

    test('compareTo для разных валют это ошибка', () {
      expect(() => rub(100).compareTo(usd(100)), throwsA(isA<ArgumentError>()));
    });

    test('операторы сравнения для разных валют это ошибка', () {
      expect(() => rub(1) < usd(1), throwsA(isA<ArgumentError>()));
      expect(() => rub(1) > usd(1), throwsA(isA<ArgumentError>()));
      expect(() => rub(1) <= usd(1), throwsA(isA<ArgumentError>()));
      expect(() => rub(1) >= usd(1), throwsA(isA<ArgumentError>()));
    });

    test('== для разных валют это false и не бросает', () {
      expect(rub(100) == usd(100), isFalse);
      expect(rub(100) != usd(100), isTrue);
    });
  });

  group('равенство, hashCode, сравнение', () {
    test('одинаковые суммы равны и имеют одинаковый hashCode', () {
      expect(rub(100), rub(100));
      expect(rub(100).hashCode, rub(100).hashCode);
      expect(Money.zero('RUB'), rub(0));
    });

    test('разные суммы не равны', () {
      expect(rub(100) == rub(101), isFalse);
    });

    test('не равно объекту другого типа', () {
      // Тип Object нужен, чтобы анализатор не отвергал сравнение заранее.
      final Object other = 100;
      expect(rub(100) == other, isFalse);
    });

    test('работает как ключ Set', () {
      final set = {rub(1), rub(1), rub(2), usd(1)};
      expect(set.length, 3);
      expect(set.contains(Money.fromMinor(2, 'RUB')), isTrue);
    });

    test('работает как ключ Map', () {
      final map = {Money.fromMinor(1, 'RUB'): 'one'};
      expect(map[Money.fromMinor(1, 'RUB')], 'one');
      expect(map[Money.fromMinor(1, 'USD')], isNull);
    });

    test('операторы сравнения', () {
      expect(rub(1) < rub(2), isTrue);
      expect(rub(2) < rub(1), isFalse);
      expect(rub(2) > rub(1), isTrue);
      expect(rub(1) > rub(1), isFalse);
      expect(rub(1) <= rub(1), isTrue);
      expect(rub(2) <= rub(1), isFalse);
      expect(rub(1) >= rub(1), isTrue);
      expect(rub(1) >= rub(2), isFalse);
      expect(rub(-1) < rub(0), isTrue);
    });

    test('compareTo возвращает знак разницы', () {
      expect(rub(1).compareTo(rub(2)), isNegative);
      expect(rub(2).compareTo(rub(1)), isPositive);
      expect(rub(2).compareTo(rub(2)), 0);
    });

    test('список сортируется через sort()', () {
      final list = [rub(300), rub(-5), rub(0), rub(100)]..sort();
      expect(list, [rub(-5), rub(0), rub(100), rub(300)]);
    });
  });

  group('allocate', () {
    List<int> minors(List<Money> parts) =>
        parts.map((m) => m.minorUnits).toList();

    test('100,00 на 3 части: 33,34 / 33,33 / 33,33', () {
      expect(minors(rub(10000).allocate(3)), [3334, 3333, 3333]);
    });

    test('на 1 часть возвращает исходную сумму', () {
      expect(rub(10000).allocate(1), [rub(10000)]);
      expect(rub(-7).allocate(1), [rub(-7)]);
    });

    test('на 7 частей', () {
      // 10000 = 7 * 1428 + 4, четыре первые части получают лишнюю копейку.
      expect(minors(rub(10000).allocate(7)), [
        1429,
        1429,
        1429,
        1429,
        1428,
        1428,
        1428,
      ]);
    });

    test('деление без остатка даёт равные части', () {
      expect(minors(rub(9000).allocate(3)), [3000, 3000, 3000]);
    });

    test('частей больше, чем копеек: 2 копейки на 5 частей', () {
      expect(minors(rub(2).allocate(5)), [1, 1, 0, 0, 0]);
    });

    test('нулевая сумма делится на нули', () {
      expect(minors(rub(0).allocate(4)), [0, 0, 0, 0]);
    });

    test('отрицательная сумма: части отрицательные, лишняя копейка первым', () {
      expect(minors(rub(-10000).allocate(3)), [-3334, -3333, -3333]);
      expect(minors(rub(-2).allocate(5)), [-1, -1, 0, 0, 0]);
    });

    test('parts меньше 1 это ошибка', () {
      expect(() => rub(100).allocate(0), throwsA(isA<ArgumentError>()));
      expect(() => rub(100).allocate(-3), throwsA(isA<ArgumentError>()));
    });

    test('валюта сохраняется в каждой части', () {
      final parts = usd(100).allocate(3);
      expect(parts.every((m) => m.currency == 'USD'), isTrue);
    });

    test('сумма частей всегда равна исходной', () {
      const amounts = [
        0,
        1,
        2,
        3,
        99,
        100,
        101,
        12345,
        999999,
        -1,
        -2,
        -99,
        -100,
        -12345,
      ];
      for (final amount in amounts) {
        for (var parts = 1; parts <= 10; parts++) {
          final result = rub(amount).allocate(parts);
          expect(result.length, parts, reason: '$amount на $parts');
          final total = result.fold(Money.zero('RUB'), (sum, m) => sum + m);
          expect(total, rub(amount), reason: '$amount на $parts');
          // Части отличаются друг от друга не больше чем на копейку.
          final values = result.map((m) => m.minorUnits);
          final spread =
              values.reduce((a, b) => a > b ? a : b) -
              values.reduce((a, b) => a < b ? a : b);
          expect(spread <= 1, isTrue, reason: '$amount на $parts');
        }
      }
    });
  });

  group('dividedBy', () {
    test('округление половины от нуля', () {
      expect(rub(5).dividedBy(2), rub(3)); // 2,5 -> 3
      expect(rub(-5).dividedBy(2), rub(-3)); // -2,5 -> -3
      expect(rub(1).dividedBy(2), rub(1)); // 0,5 -> 1
      expect(rub(-1).dividedBy(2), rub(-1)); // -0,5 -> -1
      expect(rub(-3).dividedBy(2), rub(-2)); // -1,5 -> -2
      expect(rub(3).dividedBy(2), rub(2)); // 1,5 -> 2
    });

    test('обычное округление вниз и вверх', () {
      expect(rub(4).dividedBy(3), rub(1)); // 1,33 -> 1
      expect(rub(5).dividedBy(3), rub(2)); // 1,67 -> 2
      expect(rub(-4).dividedBy(3), rub(-1));
      expect(rub(-5).dividedBy(3), rub(-2));
      expect(rub(1).dividedBy(3), rub(0)); // 0,33 -> 0
      expect(rub(2).dividedBy(3), rub(1)); // 0,67 -> 1
    });

    test('точное деление и деление на 1', () {
      expect(rub(6).dividedBy(3), rub(2));
      expect(rub(-6).dividedBy(3), rub(-2));
      expect(rub(12345).dividedBy(1), rub(12345));
      expect(rub(0).dividedBy(7), rub(0));
    });

    test('четный и нечётный делитель: ровно половина', () {
      expect(rub(5).dividedBy(10), rub(1)); // 0,5 -> 1
      expect(rub(-5).dividedBy(10), rub(-1)); // -0,5 -> -1
      expect(rub(4).dividedBy(10), rub(0)); // 0,4 -> 0
      expect(rub(15).dividedBy(10), rub(2)); // 1,5 -> 2
      expect(rub(7).dividedBy(5), rub(1)); // 1,4 -> 1
      expect(rub(8).dividedBy(5), rub(2)); // 1,6 -> 2
    });

    test('валюта сохраняется', () {
      expect(usd(5).dividedBy(2).currency, 'USD');
    });

    test('делитель 0 это ошибка', () {
      expect(() => rub(5).dividedBy(0), throwsA(isA<ArgumentError>()));
    });

    test('отрицательный делитель это ошибка', () {
      expect(() => rub(5).dividedBy(-2), throwsA(isA<ArgumentError>()));
    });
  });

  group('большие значения', () {
    test('сумма около 9 000 000 000 000 000 копеек считается точно', () {
      final a = rub(9000000000000000);
      final b = rub(123456789);
      expect((a + b).minorUnits, 9000000123456789);
      expect((a + b - a), b);
      expect(
        a.allocate(3).map((m) => m.minorUnits).reduce((x, y) => x + y),
        a.minorUnits,
      );
    });

    test('переполнение int молчаливое: результат заворачивается', () {
      // Поведение зафиксировано, не желаемое; для личных финансов не достижимо.
      final wrapped = rub(9223372036854775807) + rub(1);
      expect(wrapped.minorUnits, -9223372036854775808);
      expect(wrapped.isNegative, isTrue);
    });

    test('dividedBy на границе целого: смещение половины переполняется', () {
      // Поведение вне зоны честной работы, не желаемое: maxInt + 1 (сдвиг на
      // половину делителя) заворачивается в отрицательное, и результат
      // получается отрицательным. Зафиксировано как документация.
      final result = rub(9223372036854775807).dividedBy(2);
      expect(result.isNegative, isTrue);
    });
  });
}
