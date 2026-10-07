import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/transactions/domain/category_kind_mapping.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_rules.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

Category _top({
  String id = 'c-food',
  CategoryKind kind = CategoryKind.expense,
}) {
  return Category.topLevel(
    id: id,
    kind: kind,
    name: 'Cat $id',
    iconKey: 'icon',
    sortOrder: 0,
  );
}

Category _sub(Category parent, {String id = 's-cafe'}) {
  return Category.subcategoryOf(
    id: id,
    parent: parent,
    name: 'Sub $id',
    iconKey: 'icon',
    sortOrder: 0,
  );
}

Money _rub(int minor) => Money.fromMinor(minor, 'RUB');

final _day = DateOnly(2026, 9, 20);
final _moment = DateTime.utc(2026, 9, 20, 10, 30);

Transaction _make({
  String id = 't1',
  TransactionType type = TransactionType.expense,
  Money? amount,
  DateOnly? occurredOn,
  DateTime? occurredAt,
  String categoryId = 'c-food',
  String? subcategoryId,
  String? note,
}) {
  return Transaction(
    id: id,
    type: type,
    amount: amount ?? _rub(15000),
    occurredOn: occurredOn ?? _day,
    occurredAt: occurredAt ?? _moment,
    categoryId: categoryId,
    subcategoryId: subcategoryId,
    note: note,
  );
}

Transaction _create({
  TransactionType type = TransactionType.expense,
  required Category category,
  Category? subcategory,
  Money? amount,
  String? note,
}) {
  return Transaction.create(
    id: 't1',
    type: type,
    amount: amount ?? _rub(15000),
    occurredOn: _day,
    occurredAt: _moment,
    category: category,
    subcategory: subcategory,
    note: note,
  );
}

Matcher _throwsRule(TransactionRule rule) => throwsA(
  isA<TransactionRuleException>().having((e) => e.rule, 'rule', rule),
);

void main() {
  group('сумма', () {
    test('отрицательная сумма запрещена', () {
      expect(
        () => _make(amount: _rub(-1)),
        _throwsRule(TransactionRule.negativeAmount),
      );
    });

    test('ноль допустим и сохраняется', () {
      final t = _make(amount: Money.zero('RUB'));
      expect(t.amount, Money.zero('RUB'));
      expect(t.amount.isZero, isTrue);
    });

    test('положительная сумма сохраняется вместе с валютой', () {
      final t = _make(amount: Money.fromMinor(100, 'USD'));
      expect(t.amount, Money.fromMinor(100, 'USD'));
    });
  });

  group('комментарий', () {
    test('по умолчанию комментария нет', () {
      expect(_make().note, isNull);
    });

    test('пробелы по краям обрезаются', () {
      expect(_make(note: '  Lunch \n').note, 'Lunch');
    });

    test('пустой комментарий становится null', () {
      expect(_make(note: '').note, isNull);
    });

    test('комментарий из одних пробелов становится null', () {
      expect(_make(note: '   \t ').note, isNull);
    });

    test('200 символов принимается', () {
      expect(_make(note: 'a' * 200).note, 'a' * 200);
    });

    test('201 символ запрещён', () {
      expect(
        () => _make(note: 'a' * 201),
        _throwsRule(TransactionRule.noteTooLong),
      );
    });

    test('пробелы по краям не считаются в длину', () {
      expect(_make(note: '  ${'a' * 200}  ').note, 'a' * 200);
    });

    test('кириллица считается символами: 200 можно, 201 нельзя', () {
      expect(_make(note: 'ы' * 200).note, 'ы' * 200);
      expect(
        () => _make(note: 'ы' * 201),
        _throwsRule(TransactionRule.noteTooLong),
      );
    });

    test('эмодзи считается как один символ', () {
      const emoji = '😀';
      expect(emoji.length, 2);
      expect(_make(note: emoji * 200).note, emoji * 200);
      expect(
        () => _make(note: emoji * 201),
        _throwsRule(TransactionRule.noteTooLong),
      );
    });

    test('normalizeTransactionNote: null, пусто, обрезка', () {
      expect(normalizeTransactionNote(null), isNull);
      expect(normalizeTransactionNote(''), isNull);
      expect(normalizeTransactionNote('  '), isNull);
      expect(normalizeTransactionNote(' a b '), 'a b');
    });
  });

  group('момент операции', () {
    test('не UTC запрещён', () {
      expect(
        () => _make(occurredAt: DateTime(2026, 9, 20, 10)),
        _throwsRule(TransactionRule.occurredAtNotUtc),
      );
    });

    test('UTC принимается', () {
      expect(_make(occurredAt: _moment).occurredAt, _moment);
    });
  });

  group('идентификаторы категорий', () {
    test('пустой categoryId запрещён', () {
      expect(
        () => _make(categoryId: ''),
        _throwsRule(TransactionRule.emptyCategoryId),
      );
    });

    test('categoryId из одних пробелов запрещён', () {
      expect(
        () => _make(categoryId: '  '),
        _throwsRule(TransactionRule.emptyCategoryId),
      );
    });

    test('пустой subcategoryId запрещён', () {
      expect(
        () => _make(subcategoryId: ' '),
        _throwsRule(TransactionRule.emptyCategoryId),
      );
    });

    test('subcategoryId может быть null', () {
      expect(_make().subcategoryId, isNull);
    });
  });

  group('конструктор не знает категорий', () {
    test('несогласованные тип и категория принимаются (проверка в create)', () {
      // Категорий под рукой нет, проверять связи нечем: конструктор
      // проверяет только собственные правила.
      final t = _make(type: TransactionType.income, categoryId: 'anything');
      expect(t.type, TransactionType.income);
    });
  });

  group('Transaction.create', () {
    test('успешно без подкатегории', () {
      final food = _top();
      final t = _create(category: food, note: ' hi ');
      expect(t.categoryId, 'c-food');
      expect(t.subcategoryId, isNull);
      expect(t.type, TransactionType.expense);
      expect(t.note, 'hi');
      expect(t.occurredOn, _day);
      expect(t.occurredAt, _moment);
    });

    test('успешно с подкатегорией', () {
      final food = _top();
      final cafe = _sub(food);
      final t = _create(category: food, subcategory: cafe);
      expect(t.categoryId, 'c-food');
      expect(t.subcategoryId, 's-cafe');
    });

    test('доход в категории дохода', () {
      final salary = _top(id: 'c-salary', kind: CategoryKind.income);
      final t = _create(type: TransactionType.income, category: salary);
      expect(t.type, TransactionType.income);
    });

    test('подкатегория вместо категории запрещена', () {
      final cafe = _sub(_top());
      expect(
        () => _create(category: cafe),
        _throwsRule(TransactionRule.categoryMustBeTopLevel),
      );
    });

    test('расход в категории дохода запрещён', () {
      final salary = _top(id: 'c-salary', kind: CategoryKind.income);
      expect(
        () => _create(category: salary),
        _throwsRule(TransactionRule.typeKindMismatch),
      );
    });

    test('доход в категории расхода запрещён', () {
      expect(
        () => _create(type: TransactionType.income, category: _top()),
        _throwsRule(TransactionRule.typeKindMismatch),
      );
    });

    test('подкатегория из чужой категории запрещена', () {
      final food = _top();
      final transport = _top(id: 'c-transport');
      final taxi = _sub(transport, id: 's-taxi');
      expect(
        () => _create(category: food, subcategory: taxi),
        _throwsRule(TransactionRule.subcategoryNotOfCategory),
      );
    });

    test('подкатегория другого вида запрещена', () {
      // Подкатегория доходной категории под расходной категорией операции:
      // она не дочерняя, это «чужая» подкатегория.
      final food = _top();
      final salary = _top(id: 'c-salary', kind: CategoryKind.income);
      final bonus = _sub(salary, id: 's-bonus');
      expect(
        () => _create(category: food, subcategory: bonus),
        _throwsRule(TransactionRule.subcategoryNotOfCategory),
      );
      // Подкатегория с испорченным видом: родитель тот же, вид другой.
      final wrongKind = Category(
        id: 's-wrong',
        kind: CategoryKind.income,
        name: 'Wrong',
        iconKey: 'icon',
        parentId: food.id,
        sortOrder: 0,
      );
      expect(
        () => _create(category: food, subcategory: wrongKind),
        _throwsRule(TransactionRule.typeKindMismatch),
      );
    });

    test('собственные правила тоже проверяются', () {
      expect(
        () => _create(category: _top(), amount: _rub(-5)),
        _throwsRule(TransactionRule.negativeAmount),
      );
      expect(
        () => _create(category: _top(), note: 'a' * 201),
        _throwsRule(TransactionRule.noteTooLong),
      );
    });
  });

  group('withCategory', () {
    test('смена типа расход -> доход с новой категорией дохода проходит', () {
      final original = _create(category: _top(), note: 'n');
      final salary = _top(id: 'c-salary', kind: CategoryKind.income);
      final changed = original.withCategory(
        type: TransactionType.income,
        category: salary,
      );
      expect(changed.type, TransactionType.income);
      expect(changed.categoryId, 'c-salary');
      expect(changed.subcategoryId, isNull);
      // Остальные поля сохранились.
      expect(changed.id, original.id);
      expect(changed.amount, original.amount);
      expect(changed.occurredOn, original.occurredOn);
      expect(changed.occurredAt, original.occurredAt);
      expect(changed.note, 'n');
    });

    test('смена типа со старой (расходной) категорией запрещена', () {
      final food = _top();
      final original = _create(category: food);
      expect(
        () =>
            original.withCategory(type: TransactionType.income, category: food),
        _throwsRule(TransactionRule.typeKindMismatch),
      );
    });

    test('смена подкатегории внутри той же категории', () {
      final food = _top();
      final original = _create(category: food, subcategory: _sub(food));
      final changed = original.withCategory(
        type: TransactionType.expense,
        category: food,
        subcategory: _sub(food, id: 's-lunch'),
      );
      expect(changed.subcategoryId, 's-lunch');
    });

    test('подкатегория сбрасывается, если не передана', () {
      final food = _top();
      final original = _create(category: food, subcategory: _sub(food));
      final changed = original.withCategory(
        type: TransactionType.expense,
        category: food,
      );
      expect(changed.subcategoryId, isNull);
    });

    test('чужая подкатегория запрещена', () {
      final food = _top();
      final taxi = _sub(_top(id: 'c-transport'), id: 's-taxi');
      expect(
        () => _create(category: food).withCategory(
          type: TransactionType.expense,
          category: food,
          subcategory: taxi,
        ),
        _throwsRule(TransactionRule.subcategoryNotOfCategory),
      );
    });

    test('подкатегория вместо категории запрещена', () {
      final cafe = _sub(_top());
      expect(
        () =>
            _create(category: _top())
                .withCategory(type: TransactionType.expense, category: cafe),
        _throwsRule(TransactionRule.categoryMustBeTopLevel),
      );
    });
  });

  group('copyWith и withNote', () {
    test('copyWith меняет только указанные поля', () {
      final original = _make(note: 'n', subcategoryId: 's1');
      final day = DateOnly(2026, 9, 21);
      final at = DateTime.utc(2026, 9, 21, 8);
      final changed = original.copyWith(
        amount: _rub(0),
        occurredOn: day,
        occurredAt: at,
      );
      expect(changed.amount, _rub(0));
      expect(changed.occurredOn, day);
      expect(changed.occurredAt, at);
      expect(changed.id, original.id);
      expect(changed.type, original.type);
      expect(changed.categoryId, original.categoryId);
      expect(changed.subcategoryId, 's1');
      expect(changed.note, 'n');
    });

    test('copyWith без аргументов даёт равную операцию', () {
      final original = _make(note: 'n');
      expect(original.copyWith(), original);
    });

    test('copyWith проверяет сумму и момент', () {
      final t = _make();
      expect(
        () => t.copyWith(amount: _rub(-1)),
        _throwsRule(TransactionRule.negativeAmount),
      );
      expect(
        () => t.copyWith(occurredAt: DateTime(2026, 9, 20)),
        _throwsRule(TransactionRule.occurredAtNotUtc),
      );
    });

    test('withNote нормализует и проверяет', () {
      final t = _make(note: 'old');
      expect(t.withNote('  new ').note, 'new');
      expect(t.withNote(null).note, isNull);
      expect(t.withNote('   ').note, isNull);
      expect(t.withNote('a' * 200).note, 'a' * 200);
      expect(
        () => t.withNote('a' * 201),
        _throwsRule(TransactionRule.noteTooLong),
      );
    });
  });

  group('счёт', () {
    test('по умолчанию без счёта', () {
      expect(_make().accountId, isNull);
    });

    test('withAccount ставит и снимает счёт, остальное сохраняется', () {
      final original = _make(note: 'n', subcategoryId: 's1');
      final withAcc = original.withAccount('acc');
      expect(withAcc.accountId, 'acc');
      expect(withAcc.note, 'n');
      expect(withAcc.subcategoryId, 's1');
      expect(withAcc.withAccount(null).accountId, isNull);
      expect(withAcc.withAccount(null), original);
    });

    test('копии и смена типа сохраняют счёт', () {
      final t = _make().withAccount('acc');
      expect(t.copyWith(amount: _rub(1)).accountId, 'acc');
      expect(t.withNote('x').accountId, 'acc');
      final income = _top(id: 'inc', kind: CategoryKind.income);
      final changed = t.withCategory(
        type: TransactionType.income,
        category: income,
      );
      expect(changed.accountId, 'acc');
    });

    test('Transaction.create принимает счёт', () {
      final t = Transaction.create(
        id: 't1',
        type: TransactionType.expense,
        amount: _rub(1),
        occurredOn: _day,
        occurredAt: _moment,
        category: _top(),
        accountId: 'acc',
      );
      expect(t.accountId, 'acc');
    });

    test('счёт участвует в равенстве, hashCode и toString', () {
      final a = _make().withAccount('acc');
      expect(a, _make().withAccount('acc'));
      expect(a.hashCode, _make().withAccount('acc').hashCode);
      expect(a, isNot(_make()));
      expect(a, isNot(_make().withAccount('other')));
      expect(a.toString(), contains('accountId: acc'));
    });
  });
  group('равенство', () {
    test('одинаковые поля дают равные операции и одинаковый hashCode', () {
      final a = _make(note: 'n', subcategoryId: 's1');
      final b = _make(note: 'n', subcategoryId: 's1');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('заметка после нормализации участвует в равенстве', () {
      expect(_make(note: ' n '), _make(note: 'n'));
      expect(_make(note: ''), _make());
    });

    test('любое отличие в поле даёт неравные операции', () {
      final base = _make(note: 'n', subcategoryId: 's1');
      expect(base, isNot(_make(id: 'other', note: 'n', subcategoryId: 's1')));
      expect(
        base,
        isNot(
          _make(type: TransactionType.income, note: 'n', subcategoryId: 's1'),
        ),
      );
      expect(base, isNot(base.copyWith(amount: _rub(1))));
      expect(base, isNot(base.copyWith(amount: Money.fromMinor(15000, 'USD'))));
      expect(base, isNot(base.copyWith(occurredOn: DateOnly(2026, 9, 19))));
      expect(
        base,
        isNot(base.copyWith(occurredAt: DateTime.utc(2026, 9, 20, 11))),
      );
      expect(
        base,
        isNot(_make(categoryId: 'other', note: 'n', subcategoryId: 's1')),
      );
      expect(base, isNot(_make(note: 'n', subcategoryId: 's2')));
      expect(base, isNot(_make(note: 'n')));
      expect(base, isNot(_make(subcategoryId: 's1')));
    });

    test('toString содержит основные поля', () {
      final text = _make(note: 'n').toString();
      expect(text, contains('t1'));
      expect(text, contains('expense'));
      expect(text, contains('c-food'));
    });
  });

  group('маппинг CategoryKind -> TransactionType', () {
    test('income и expense', () {
      expect(CategoryKind.income.transactionType, TransactionType.income);
      expect(CategoryKind.expense.transactionType, TransactionType.expense);
    });
  });

  group('TransactionRuleException', () {
    test('у каждого правила есть непустое сообщение', () {
      for (final rule in TransactionRule.values) {
        final e = TransactionRuleException(rule);
        expect(e.message, isNotEmpty);
        expect(e.toString(), contains(rule.name));
      }
    });

    test('своё сообщение сохраняется', () {
      final e = TransactionRuleException(TransactionRule.noteTooLong, 'custom');
      expect(e.message, 'custom');
    });
  });
}
