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

  final deleted = <String>[];
  final restored = <String>[];

  /// Если задан, `softDelete` ждёт его завершения (удаление «в пути»).
  Completer<void>? deleteGate;

  /// Если задана, `softDelete` / `restore` бросают её (запись не меняется).
  Exception? deleteError;
  Exception? restoreError;

  @override
  Future<void> softDelete(String id) async {
    deleted.add(id);
    final g = deleteGate;
    if (g != null) await g.future;
    if (deleteError case final error?) throw error;
    exists = false;
  }

  @override
  Future<void> restore(String id) async {
    if (restoreError case final error?) throw error;
    restored.add(id);
    exists = true;
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

// TextButton.icon создаёт подкласс, поэтому `byType` его не найдёт.
Finder get _deleteButton => find.ancestor(
  of: find.text('Удалить'),
  matching: find.bySubtype<TextButton>(),
);

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

  group('смена типа', () {
    Finder segment(String label) => find.descendant(
      of: find.byType(SegmentedButton<TransactionType>),
      matching: find.text(label),
    );

    Future<void> switchTo(WidgetTester tester, String label) async {
      await tester.tap(segment(label));
      await tester.pumpAndSettle();
    }

    Future<void> pick(WidgetTester tester, String name) async {
      await tester.tap(find.text('Категория'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(name));
      await tester.pumpAndSettle();
    }

    testWidgets('переключатель: слова, знаки, зона не меньше 48 dp', (
      tester,
    ) async {
      await tester.pumpWidget(_app(_Transactions()));
      await _open(tester);

      final button = find.byType(SegmentedButton<TransactionType>);
      expect(segment('Расход'), findsOneWidget);
      expect(segment('Доход'), findsOneWidget);
      expect(
        find.descendant(of: button, matching: find.byIcon(Icons.remove)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: button, matching: find.byIcon(Icons.add)),
        findsOneWidget,
      );
      expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
      expect(find.bySemanticsLabel('Тип операции'), findsOneWidget);
    });

    testWidgets('расход -> доход: заголовок, знак, цвет, категория сброшена', (
      tester,
    ) async {
      await tester.pumpWidget(_app(_Transactions()));
      await _open(tester);
      expect(find.text('Продукты'), findsOneWidget);

      await switchTo(tester, 'Доход');

      final title = find.text('Правка дохода');
      expect(title, findsOneWidget);
      expect(find.text('Правка расхода'), findsNothing);
      final colors = tester
          .element(find.byType(EditTransactionScreen))
          .appColors;
      expect(tester.widget<Text>(title).style?.color, colors.income);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byIcon(Icons.add),
        ),
        findsOneWidget,
      );
      expect(
        tester.widget<AmountField>(find.byType(AmountField)).isIncome,
        isTrue,
      );
      // Старая категория исчезла, поле просит выбрать новую (без красного,
      // пока не нажали «Сохранить»).
      expect(find.text('Продукты'), findsNothing);
      expect(find.text('Выберите категорию'), findsOneWidget);
      // Сумма и комментарий как были.
      expect(
        tester.widget<TextField>(_amountInput).controller!.text,
        isNotEmpty,
      );
      expect(find.text('молоко'), findsOneWidget);
    });

    testWidgets('выбор категории идёт по новому типу', (tester) async {
      await tester.pumpWidget(_app(_Transactions()));
      await _open(tester);
      await switchTo(tester, 'Доход');

      await tester.tap(find.text('Категория'));
      await tester.pumpAndSettle();
      expect(find.text('Категория дохода'), findsOneWidget);
      expect(find.text('Зарплата'), findsOneWidget);
      expect(find.text('Кафе'), findsNothing);
      expect(find.text('Продукты'), findsNothing);
    });

    testWidgets('«Сохранить» без категории не сохраняет и объясняет', (
      tester,
    ) async {
      final repo = _Transactions();
      await tester.pumpWidget(_app(repo));
      await _open(tester);
      await switchTo(tester, 'Доход');

      await tester.tap(_saveButton);
      await tester.pumpAndSettle();

      expect(repo.updateCalls, 0);
      expect(find.byType(EditTransactionScreen), findsOneWidget);
      // Текст ошибки под полем и сама подсказка в поле категории.
      expect(find.text('Выберите категорию'), findsNWidgets(2));

      // После выбора категории ошибка уходит и сохранение проходит.
      await pick(tester, 'Зарплата');
      expect(find.text('Выберите категорию'), findsNothing);
      await tester.tap(_saveButton);
      await tester.pumpAndSettle();
      expect(repo.updated, hasLength(1));
      final saved = repo.updated.single;
      expect(saved.type, TransactionType.income);
      expect(saved.categoryId, 'salary');
      expect(saved.subcategoryId, isNull);
      expect(saved.amount, _original.amount);
      expect(saved.note, 'молоко');
      expect(saved.occurredOn, _original.occurredOn);
      expect(find.text('Изменения сохранены'), findsOneWidget);
    });

    testWidgets('возврат исходного типа восстанавливает исходную категорию', (
      tester,
    ) async {
      final repo = _Transactions();
      await tester.pumpWidget(_app(repo));
      await _open(tester);
      await switchTo(tester, 'Доход');
      await pick(tester, 'Зарплата');
      expect(find.text('Зарплата'), findsOneWidget);

      await switchTo(tester, 'Расход');

      expect(find.text('Правка расхода'), findsOneWidget);
      expect(find.text('Продукты'), findsOneWidget);
      expect(find.text('Зарплата'), findsNothing);
      // Сохранение идёт как обычная правка без смены типа.
      await tester.tap(_saveButton);
      await tester.pumpAndSettle();
      final saved = repo.updated.single;
      expect(saved.type, TransactionType.expense);
      expect(saved.categoryId, 'food');
    });

    testWidgets('масштаб 200 % после смены типа: без overflow', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(_Transactions(), textScale: 2));
      await _open(tester);
      await switchTo(tester, 'Доход');
      await tester.tap(_saveButton);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Выберите категорию'), findsNWidgets(2));
    });
  });

  group('удаление', () {
    testWidgets('«Удалить» отдельно под «Сохранить», зона не меньше 48 dp', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(_app(_Transactions()));
      await _open(tester);

      final save = tester.getRect(_saveButton);
      final delete = tester.getRect(_deleteButton);
      expect(delete.top, greaterThanOrEqualTo(save.bottom + 8));
      expect(delete.height, greaterThanOrEqualTo(48));
      final colors = Theme.of(tester.element(_deleteButton)).colorScheme;
      final style = tester.widget<TextButton>(_deleteButton).style!;
      expect(style.foregroundColor!.resolve({}), colors.error);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
      expect(find.bySemanticsLabel('Удалить операцию'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('тап: мягкое удаление, возврат, сообщение без диалога', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final repo = _Transactions();
      await tester.pumpWidget(_app(repo));
      await _open(tester);
      await tester.tap(_deleteButton);
      await tester.pumpAndSettle();

      expect(repo.deleted, ['tx']);
      expect(find.byType(EditTransactionScreen), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Операция удалена'), findsOneWidget);
      expect(find.text('Отменить'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Операция удалена: расход 350 рублей, Продукты'),
        findsOneWidget,
      );
      final bar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(bar.duration, const Duration(seconds: 6));
      expect(bar.persist, isFalse);
      semantics.dispose();
    });

    testWidgets('«Отменить» восстанавливает именно эту запись', (tester) async {
      final repo = _Transactions();
      await tester.pumpWidget(_app(repo));
      await _open(tester);
      await tester.tap(_deleteButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Отменить'));
      await tester.pumpAndSettle();

      expect(repo.restored, ['tx']);
      expect(find.text('Операция удалена'), findsNothing);
    });

    testWidgets('сообщение исчезает само через 6 секунд', (tester) async {
      await tester.pumpWidget(_app(_Transactions()));
      await _open(tester);
      await tester.tap(_deleteButton);
      await tester.pumpAndSettle();

      await tester.pump(const Duration(seconds: 5));
      expect(find.text('Операция удалена'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('Операция удалена'), findsNothing);
    });

    testWidgets('двойной тап: одно удаление, одно сообщение', (tester) async {
      final repo = _Transactions()..deleteGate = Completer<void>();
      await tester.pumpWidget(_app(repo));
      await _open(tester);
      await tester.tap(_deleteButton);
      await tester.pump();
      await tester.tap(_deleteButton);
      await tester.pump();
      repo.deleteGate!.complete();
      await tester.pumpAndSettle();

      expect(repo.deleted, hasLength(1));
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('Операция удалена'), findsOneWidget);
    });

    testWidgets('ошибка удаления: экран открыт, текст рядом с кнопками, '
        'повтор возможен', (tester) async {
      final repo = _Transactions()..deleteError = Exception('disk');
      await tester.pumpWidget(_app(repo));
      await _open(tester);
      await tester.enterText(_amountInput, '400');
      await tester.tap(_deleteButton);
      await tester.pumpAndSettle();

      expect(find.byType(EditTransactionScreen), findsOneWidget);
      expect(find.text('Не удалось удалить. Попробуйте ещё раз'), findsOne);
      expect(find.byType(SnackBar), findsNothing);
      // Введённое не потеряно.
      expect(
        tester.widget<TextField>(_amountInput).controller!.text,
        contains('400'),
      );

      repo.deleteError = null;
      await tester.tap(_deleteButton);
      await tester.pumpAndSettle();
      expect(find.byType(EditTransactionScreen), findsNothing);
      expect(find.text('Операция удалена'), findsOneWidget);
    });

    testWidgets('запись уже удалена: экран закрыт, «Отменить» нет', (
      tester,
    ) async {
      final repo = _Transactions()..exists = false;
      await tester.pumpWidget(_app(repo));
      await _open(tester);
      await tester.tap(_deleteButton);
      await tester.pumpAndSettle();

      expect(repo.deleted, isEmpty);
      expect(find.byType(EditTransactionScreen), findsNothing);
      expect(find.text('Эта операция уже удалена'), findsOneWidget);
      expect(find.text('Отменить'), findsNothing);
    });

    testWidgets('ошибка отмены: «Не удалось отменить...»', (tester) async {
      final repo = _Transactions()..restoreError = Exception('disk');
      await tester.pumpWidget(_app(repo));
      await _open(tester);
      await tester.tap(_deleteButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Отменить'));
      await tester.pumpAndSettle();

      expect(find.text('Не удалось отменить. Попробуйте ещё раз'), findsOne);
      expect(find.text('Операция удалена'), findsNothing);
    });

    testWidgets('масштаб 200 %: кнопки не перекрываются, без overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(_Transactions(), textScale: 2));
      await _open(tester);

      expect(tester.takeException(), isNull);
      final save = tester.getRect(_saveButton);
      final delete = tester.getRect(_deleteButton);
      expect(save.overlaps(delete), isFalse);
      expect(delete.height, greaterThanOrEqualTo(48));
      expect(delete.bottom, lessThanOrEqualTo(640));

      // С клавиатурой оба ряда кнопок остаются над ней.
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tester.getRect(_deleteButton).bottom, lessThanOrEqualTo(340));
    });
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
