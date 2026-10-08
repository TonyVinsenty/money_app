import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/money/currency_catalog.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/accounts/domain/account_rules.dart';

Account acc(
  String id,
  String name, {
  int opening = 0,
  DateTime? archivedAt,
  int sortOrder = 0,
  String iconKey = 'card',
}) => Account(
  id: id,
  name: name,
  iconKey: iconKey,
  openingBalance: Money.fromMinor(opening, 'RUB'),
  sortOrder: sortOrder,
  archivedAt: archivedAt,
);

void expectRule(void Function() body, AccountRule rule) {
  expect(
    body,
    throwsA(isA<AccountRuleException>().having((e) => e.rule, 'rule', rule)),
  );
}

void main() {
  currencyInfoTests();
  test('максимальная длина имени равна 40', () {
    expect(accountNameMaxLength, 40);
  });

  group('имя', () {
    test('обрезается по краям', () {
      expect(acc('1', '  Карта  ').name, 'Карта');
    });

    test('пустое и из пробелов — ошибка', () {
      expectRule(() => acc('1', ''), AccountRule.emptyName);
      expectRule(() => acc('1', '   '), AccountRule.emptyName);
    });

    test('40 символов можно, 41 нельзя (кириллица)', () {
      expect(acc('1', 'я' * 40).name.length, 40);
      expectRule(() => acc('1', 'я' * 41), AccountRule.nameTooLong);
    });

    test('эмодзи считается одним символом', () {
      expect(acc('1', '\u{1F4B3}' * 40).name.runes.length, 40);
      expectRule(() => acc('1', '\u{1F4B3}' * 41), AccountRule.nameTooLong);
    });

    test('пробелы по краям не считаются в длину', () {
      expect(acc('1', ' ${'я' * 40} ').name.length, 40);
    });
  });

  group('знаки валюты', () {
    Account withDigits(int digits) => Account(
      id: '1',
      name: 'Карта',
      iconKey: 'card',
      openingBalance: Money.fromMinor(0, 'BTC'),
      sortOrder: 0,
      currencyDigits: digits,
    );

    test('по умолчанию 2, границы 0 и 8 можно', () {
      expect(acc('1', 'Карта').currencyDigits, 2);
      expect(withDigits(0).currencyDigits, 0);
      expect(withDigits(8).currencyDigits, 8);
    });

    test('-1 и 9 — ArgumentError', () {
      expect(() => withDigits(-1), throwsArgumentError);
      expect(() => withDigits(9), throwsArgumentError);
    });

    test('участвуют в равенстве, копиях и toString', () {
      expect(withDigits(4), withDigits(4));
      expect(withDigits(4), isNot(withDigits(8)));
      expect(withDigits(4).hashCode, withDigits(4).hashCode);
      expect(withDigits(4).withName('Другая').currencyDigits, 4);
      expect(
        withDigits(4).archived(DateTime.utc(2026)).restored(),
        withDigits(4),
      );
      expect(withDigits(4).toString(), contains('currencyDigits: 4'));
    });
  });

  group('остальные поля', () {
    test('пустой значок — ошибка', () {
      expectRule(() => acc('1', 'A', iconKey: ' '), AccountRule.emptyIconKey);
    });

    test('отрицательный порядок — ошибка', () {
      expectRule(
        () => acc('1', 'A', sortOrder: -1),
        AccountRule.negativeSortOrder,
      );
    });

    test('архивация не в UTC — ArgumentError', () {
      expect(
        () => acc('1', 'A', archivedAt: DateTime(2026, 10, 7)),
        throwsArgumentError,
      );
    });

    test('стартовый остаток: ноль и минус допустимы', () {
      expect(acc('1', 'A').openingBalance.isZero, isTrue);
      expect(acc('1', 'A', opening: -150000).openingBalance.isNegative, isTrue);
    });

    test('валюта не из трёх букв — ошибка Money', () {
      expect(() => Money.fromMinor(0, 'rub'), throwsArgumentError);
      expect(() => Money.fromMinor(0, 'RU'), throwsArgumentError);
    });

    test('currency берётся из стартового остатка', () {
      expect(acc('1', 'A').currency, 'RUB');
    });
  });

  group('копии', () {
    final base = acc('1', 'Карта', opening: 100, sortOrder: 2);

    test('withName меняет только имя и проверяет его', () {
      final copy = base.withName(' Наличные ');
      expect(copy.name, 'Наличные');
      expect(copy.id, '1');
      expect(copy.openingBalance, base.openingBalance);
      expectRule(() => base.withName(' '), AccountRule.emptyName);
    });

    test('withIcon', () {
      expect(base.withIcon('cash').iconKey, 'cash');
      expectRule(() => base.withIcon(''), AccountRule.emptyIconKey);
    });

    test('withOpeningBalance', () {
      final copy = base.withOpeningBalance(Money.fromMinor(-5, 'RUB'));
      expect(copy.openingBalance.minorUnits, -5);
      expect(copy.name, 'Карта');
    });

    test('withSortOrder', () {
      expect(base.withSortOrder(7).sortOrder, 7);
      expectRule(() => base.withSortOrder(-1), AccountRule.negativeSortOrder);
    });

    test('archived и restored', () {
      final at = DateTime.utc(2026, 10, 7);
      final archived = base.archived(at);
      expect(archived.isArchived, isTrue);
      expect(archived.archivedAt, at);
      expect(archived.restored().isArchived, isFalse);
      expect(archived.restored(), base);
      expect(() => base.archived(DateTime(2026)), throwsArgumentError);
    });

    test('копия архивного счёта остаётся архивной', () {
      final archived = base.archived(DateTime.utc(2026, 10, 7));
      expect(archived.withName('Новое').isArchived, isTrue);
    });
  });

  group('дубли имён', () {
    final live = acc('1', 'Карта');

    test('«Карта» и « карта » — дубль', () {
      expect(
        Account.isDuplicateName(name: ' карта ', existing: [live]),
        isTrue,
      );
      expectRule(
        () => Account.checkUniqueName(name: ' карта ', existing: [live]),
        AccountRule.duplicateName,
      );
    });

    test('архивный счёт не мешает', () {
      final archived = acc('2', 'Карта', archivedAt: DateTime.utc(2026));
      expect(
        Account.isDuplicateName(name: 'Карта', existing: [archived]),
        isFalse,
      );
    });

    test('сам себя не считает', () {
      expect(
        Account.isDuplicateName(name: 'Карта', existing: [live], selfId: '1'),
        isFalse,
      );
    });

    test('другое имя — не дубль', () {
      Account.checkUniqueName(name: 'Наличные', existing: [live]);
    });
  });

  test('равенство и hashCode', () {
    final a = acc('1', 'Карта', opening: 5);
    final b = acc('1', ' Карта ', opening: 5);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a == a.withOpeningBalance(Money.fromMinor(6, 'RUB')), isFalse);
    expect(a == acc('2', 'Карта', opening: 5), isFalse);
    expect(a.toString(), contains('Карта'));
  });

  test('исключение хранит правило и сообщение', () {
    for (final rule in AccountRule.values) {
      final e = AccountRuleException(rule);
      expect(e.rule, rule);
      expect(e.message, isNotEmpty);
      expect(e.toString(), contains(rule.name));
    }
    expect(AccountRuleException(AccountRule.emptyName, 'x').message, 'x');
  });

  test('currencyInfo: валюта каталога и своя со знаками счёта', () {
    expect(acc('1', 'A').currencyInfo.symbol, '₽');
    final custom = Account(
      id: '2',
      name: 'B',
      iconKey: 'card',
      openingBalance: Money.fromMinor(0, 'ABC'),
      sortOrder: 0,
      currencyDigits: 4,
    );
    expect(custom.currencyInfo.digits, 4);
    expect(custom.currencyInfo.code, 'ABC');
  });
}

void currencyInfoTests() {
  test('currencyInfo: знаки из счёта, остальное из каталога', () {
    final account = Account(
      id: 'b',
      name: 'Кошелёк',
      iconKey: 'card',
      currencyDigits: 2,
      openingBalance: Money.fromMinor(150, 'BTC'),
      sortOrder: 0,
    );
    final info = account.currencyInfo;
    final catalog = currencyInfoFor('BTC');
    expect(info.digits, 2);
    expect(info.symbol, catalog.symbol);
    expect(info.name, catalog.name);
    expect(info.kind, catalog.kind);
    expect(info.forms, catalog.forms);
    expect(
      formatMoney(
        account.openingBalance,
        currency: info,
        withCurrencySymbol: false,
      ),
      '1,50',
    );
    // Каталог не тронут.
    expect(catalog.digits, 8);
  });

  test('currencyInfo: знаки каталога, если совпали, и своя валюта', () {
    expect(acc('r', 'Карта').currencyInfo, same(currencyInfoFor('RUB')));
    final custom = Account(
      id: 'c',
      name: 'Своя',
      iconKey: 'card',
      currencyDigits: 4,
      openingBalance: Money.zero('ABC'),
      sortOrder: 0,
    );
    expect(custom.currencyInfo.digits, 4);
    expect(custom.currencyInfo.kind, CurrencyKind.custom);
  });
}
