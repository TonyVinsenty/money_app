import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/features/transactions/domain/history_view.dart';

bool _matches(String query, {String? comment, String? sub}) =>
    matchesHistorySearch(query, comment: comment, subcategoryName: sub);

void main() {
  group('normalizeHistorySearch', () {
    test('обрезает пробелы, нижний регистр, ё как е', () {
      expect(normalizeHistorySearch('  Ёлка ЗЕЛЁНАЯ  '), 'елка зеленая');
    });

    test('пустая строка и одни пробелы — пусто', () {
      expect(normalizeHistorySearch(''), '');
      expect(normalizeHistorySearch(' \t\n '), '');
    });
  });

  group('matchesHistorySearch', () {
    test('вхождение в комментарий без учёта регистра', () {
      expect(_matches('кофе', comment: 'Утренний КОФЕ с собой'), isTrue);
      expect(_matches('КОФЕ', comment: 'кофе'), isTrue);
      expect(_matches('Coffee', comment: 'big coffee'), isTrue);
    });

    test('ё и е взаимозаменяемы в обе стороны', () {
      expect(_matches('елка', comment: 'Ёлка'), isTrue);
      expect(_matches('ёлка', comment: 'елка'), isTrue);
      expect(_matches('ЁЛКА', sub: 'Ёлочные игрушки'), isFalse);
      expect(_matches('ЁЛОЧ', sub: 'Елочные игрушки'), isTrue);
    });

    test('пробелы по краям запроса не считаются, внутри — считаются', () {
      expect(_matches('  кофе  ', comment: 'кофе'), isTrue);
      expect(_matches('кофе с', comment: 'кофе с собой'), isTrue);
      expect(_matches('кофе  с', comment: 'кофе с собой'), isFalse);
    });

    test('совпадение только в подкатегории', () {
      expect(_matches('пятёр', comment: 'хлеб', sub: 'Пятёрочка'), isTrue);
      expect(_matches('пятер', sub: 'Пятёрочка'), isTrue);
    });

    test('нет совпадения ни в комментарии, ни в подкатегории', () {
      expect(_matches('чай', comment: 'кофе', sub: 'Кафе'), isFalse);
    });

    test('без комментария и подкатегории непустой запрос не подходит', () {
      expect(_matches('кофе'), isFalse);
    });

    test('пустой запрос и одни пробелы подходят всему', () {
      expect(_matches(''), isTrue);
      expect(_matches('   ', comment: 'кофе'), isTrue);
    });

    test('запрос длиннее текста не подходит', () {
      expect(_matches('кофейня', comment: 'кофе'), isFalse);
    });
  });
}
