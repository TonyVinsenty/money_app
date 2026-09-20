import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/app/app.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/amount_field.dart';
import 'package:money_app/core/ui/theme/app_colors.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/core/ui/transaction_rule_text.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_rules.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';
import 'package:money_app/features/transactions/presentation/edit/edit_transaction_screen.dart';

import '../../../../support/fakes.dart';
import '../../../../support/fixed_clock.dart';

/// Репозиторий операций для правки: помнит вызовы, поведение задаёт тест.
class _Transactions extends FakeTransactionsRepository {
  final updated = <Transaction>[];
  int updateCalls = 0;
  bool exists = true;

  /// Если задан, `update` ждёт его завершения (сохранение «в пути»).
  Completer<void>? gate;

  /// Вызывается в `update` до записи и может бросить ошибку.
  void Function()? beforeUpdate;

  @override
  Future<Transaction?> findById(String id) async => exists ? _original : null;

  @override
  Future<void> update(Transaction transaction) async {
    updateCalls++;
    final g = gate;
    if (g != null) await g.future;
    beforeUpdate?.call();
    updated.add(transaction);
  }
}

class _Categories extends FakeCategoriesRepository {
  _Categories(this.all);

  final List<Category> all;

  @override
  Future<Category?> findById(String id) async {
    for (final c in all) {
      if (c.id == id) return c;
    }
    return null;
  }

  @override
  Stream<List<Category>> watchTopLevel(CategoryKind kind) => Stream.value([
    for (final c in all)
      if (c.kind == kind && !c.isArchived) c,
  ]);
}

final _clock = FixedClock(DateTime(2026, 9, 20, 15, 30));

final _original = Transaction(
  id: 'tx',
  type: TransactionType.expense,
  amount: Money.fromMinor(35000, 'RUB'),
  occurredOn: DateOnly(2026, 9, 18),
  occurredAt: DateTime.utc(2026, 9, 18, 7, 45),
  categoryId: 'food',
  note: 'молоко',
);

Category _category(
  String id,
  String name, {
  CategoryKind kind = CategoryKind.expense,
}) => Category.topLevel(
  id: id,
  kind: kind,
  name: name,
  iconKey: 'shopping_cart',
  sortOrder: 0,
);

final _cats = _Categories([
  _category('food', 'Продукты'),
  _category('cafe', 'Кафе'),
  _category('salary', 'Зарплата', kind: CategoryKind.income),
]);

/// «История» с кнопкой и экран правки поверх неё: `pop` возвращает на неё.
Widget _app(
  _Transactions transactions, {
  Transaction? transaction,
  double textScale = 1,
}) {
  return MaterialApp(
    theme: AppTheme.light(),
    locale: MoneyApp.appLocale,
    supportedLocales: MoneyApp.supportedLocales,
    localizationsDelegates: MoneyApp.localizationsDelegates,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => EditTransactionScreen(
                  transaction: transaction ?? _original,
                  clock: _clock,
                  categories: _cats,
                  transactions: transactions,
                ),
              ),
            ),
            child: const Text('Открыть'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('Открыть'));
  await tester.pumpAndSettle();
}

Finder get _amountInput => find.descendant(
  of: find.byType(AmountField),
  matching: find.byType(TextField),
);

Finder get _saveButton => find.widgetWithText(FilledButton, 'Сохранить');

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
  });

  testWidgets('доход: заголовок «Правка дохода», цвет и знак дохода', (
    tester,
  ) async {
    final income = Transaction(
      id: 'in',
      type: TransactionType.income,
      amount: Money.fromMinor(100000, 'RUB'),
      occurredOn: DateOnly(2026, 9, 20),
      occurredAt: DateTime.utc(2026, 9, 20, 10),
      categoryId: 'salary',
    );
    await tester.pumpWidget(_app(_Transactions(), transaction: income));
    await _open(tester);

    final title = find.text('Правка дохода');
    expect(title, findsOneWidget);
    final colors = tester.element(find.byType(EditTransactionScreen)).appColors;
    expect(tester.widget<Text>(title).style?.color, colors.income);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.add),
      ),
      findsOneWidget,
    );
    expect(find.text('Зарплата'), findsOneWidget);
  });

  testWidgets('сохранение отправляет одну обновлённую запись', (tester) async {
    final repo = _Transactions();
    await tester.pumpWidget(_app(repo));
    await _open(tester);
    await tester.enterText(_amountInput, '400');
    await tester.tap(_saveButton);
    await tester.pumpAndSettle();

    expect(repo.updated, hasLength(1));
    final saved = repo.updated.single;
    expect(saved.id, 'tx');
    expect(saved.amount, Money.fromMinor(40000, 'RUB'));
    expect(saved.categoryId, 'food');
    expect(saved.note, 'молоко');
    // День не менялся: день и момент прежние.
    expect(saved.occurredOn, _original.occurredOn);
    expect(saved.occurredAt, _original.occurredAt);
    expect(find.byType(EditTransactionScreen), findsNothing);
    expect(find.text('Изменения сохранены'), findsOneWidget);
  });

  testWidgets('двойной тап по «Сохранить»: одна запись изменения', (
    tester,
  ) async {
    final repo = _Transactions()..gate = Completer<void>();
    await tester.pumpWidget(_app(repo));
    await _open(tester);
    await tester.enterText(_amountInput, '400');

    await tester.tap(_saveButton);
    await tester.pump();
    await tester.tap(_saveButton);
    await tester.pump();
    repo.gate!.complete();
    await tester.pumpAndSettle();

    expect(repo.updateCalls, 1);
    expect(find.byType(EditTransactionScreen), findsNothing);
  });

  testWidgets(
    'ошибка правил: текст из transactionRuleMessage, экран остаётся',
    (tester) async {
      final repo = _Transactions()
        ..beforeUpdate = () =>
            throw TransactionRuleException(TransactionRule.categoryArchived);
      await tester.pumpWidget(_app(repo));
      await _open(tester);
      await tester.enterText(_amountInput, '400');
      await tester.tap(_saveButton);
      await tester.pumpAndSettle();

      expect(
        find.text(
          transactionRuleMessage(
            TransactionRule.categoryArchived,
            type: TransactionType.expense,
          ),
        ),
        findsOneWidget,
      );
      expect(find.byType(EditTransactionScreen), findsOneWidget);
      // Введённое не потеряно.
      expect(tester.widget<TextField>(_amountInput).controller!.text, '400');
      // Кнопка снова работает: повтор проходит.
      repo.beforeUpdate = null;
      await tester.tap(_saveButton);
      await tester.pumpAndSettle();
      expect(repo.updated, hasLength(1));
      expect(find.byType(EditTransactionScreen), findsNothing);
    },
  );

  testWidgets('любая другая ошибка: общий текст, экран остаётся', (
    tester,
  ) async {
    final repo = _Transactions()..beforeUpdate = () => throw StateError('boom');
    await tester.pumpWidget(_app(repo));
    await _open(tester);
    await tester.tap(_saveButton);
    await tester.pumpAndSettle();

    expect(find.text(transactionSaveFailedText), findsOneWidget);
    expect(find.byType(EditTransactionScreen), findsOneWidget);
    expect(repo.updated, isEmpty);
  });

  testWidgets('операции уже нет в базе: понятный текст, без записи', (
    tester,
  ) async {
    final repo = _Transactions()..exists = false;
    await tester.pumpWidget(_app(repo));
    await _open(tester);
    await tester.tap(_saveButton);
    await tester.pumpAndSettle();

    expect(find.text(EditTransactionScreen.goneText), findsOneWidget);
    expect(repo.updateCalls, 0);
    expect(find.byType(EditTransactionScreen), findsOneWidget);
  });

  testWidgets('масштаб 200 %, клавиатура: без overflow, «Сохранить» видна', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(_Transactions(), textScale: 2));
    await _open(tester);
    expect(tester.takeException(), isNull);

    // Клавиатура: снизу отъедает 300 dp.
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final button = tester.getRect(_saveButton);
    expect(button.bottom, lessThanOrEqualTo(640 - 300));
    expect(button.top, greaterThanOrEqualTo(0));

    // Прокрутка доходит до комментария.
    await tester.ensureVisible(find.text('Комментарий (необязательно)'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
