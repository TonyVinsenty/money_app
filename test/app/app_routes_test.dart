import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/app/app.dart';
import 'package:money_app/app/app_routes.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/theme/app_colors.dart';
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';
import 'package:money_app/features/transactions/presentation/quick_add/quick_add_screen.dart';

import '../support/fake_id_generator.dart';
import '../support/fakes.dart';
import '../support/fixed_clock.dart';
import '../support/in_memory_database.dart';

Future<void> _pumpApp(WidgetTester tester) async {
  final settings = AppSettingsController();
  addTearDown(settings.dispose);
  await tester.pumpWidget(
    MoneyApp(settings: settings, openDatabase: openInMemoryDatabase),
  );
  // Первый кадр — загрузка; второй — база открылась.
  await tester.pump();
}

void main() {
  group('onGenerateAppRoute', () {
    test('имя маршрута быстрого ввода — константа', () {
      expect(AppRoutes.quickAdd, '/quick-add');
    });

    test('неизвестный маршрут даёт null', () {
      expect(onGenerateAppRoute(const RouteSettings(name: '/nope')), isNull);
      expect(onGenerateAppRoute(const RouteSettings()), isNull);
    });

    test('маршрут быстрого ввода со своим типом даёт страницу', () {
      final route = onGenerateAppRoute(
        RouteSettings(
          name: AppRoutes.quickAdd,
          arguments: QuickAddRouteArguments(
            type: TransactionType.income,
            clock: FixedClock(DateTime(2026, 9, 20)),
            categories: FakeCategoriesRepository(),
            transactions: FakeTransactionsRepository(),
            idGenerator: FakeIdGenerator(),
          ),
        ),
      );
      expect(route, isA<MaterialPageRoute<void>>());
      expect(route!.settings.name, AppRoutes.quickAdd);
    });

    test('маршрут правки: имя, страница и понятная ArgumentError', () {
      expect(AppRoutes.editTransaction, '/edit-transaction');
      final route = onGenerateAppRoute(
        RouteSettings(
          name: AppRoutes.editTransaction,
          arguments: EditTransactionRouteArguments(
            transaction: Transaction(
              id: 'tx',
              type: TransactionType.expense,
              amount: Money.fromMinor(100, 'RUB'),
              occurredOn: DateOnly(2026, 9, 20),
              occurredAt: DateTime.utc(2026, 9, 20, 12),
              categoryId: 'c',
            ),
            clock: FixedClock(DateTime(2026, 9, 20)),
            categories: FakeCategoriesRepository(),
            transactions: FakeTransactionsRepository(),
          ),
        ),
      );
      expect(route, isA<MaterialPageRoute<void>>());
      expect(route!.settings.name, AppRoutes.editTransaction);
      for (final arguments in <Object?>[null, 'tx', 42]) {
        expect(
          () => onGenerateAppRoute(
            RouteSettings(
              name: AppRoutes.editTransaction,
              arguments: arguments,
            ),
          ),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.toString(),
              'сообщение',
              allOf(
                contains('/edit-transaction'),
                contains('EditTransactionRouteArguments'),
              ),
            ),
          ),
        );
      }
    });

    test('без аргумента или с чужим аргументом — понятная ArgumentError', () {
      for (final arguments in <Object?>[
        null,
        'expense',
        42,
        TransactionType.income,
      ]) {
        expect(
          () => onGenerateAppRoute(
            RouteSettings(name: AppRoutes.quickAdd, arguments: arguments),
          ),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.toString(),
              'сообщение',
              allOf(contains('/quick-add'), contains('QuickAddRouteArguments')),
            ),
          ),
        );
      }
    });
  });

  group('сквозной путь через MoneyApp', () {
    testWidgets('«Главная» показывает кнопки вместо заглушки', (tester) async {
      await _pumpApp(tester);

      expect(find.text('Доход'), findsOneWidget);
      expect(find.text('Расход'), findsOneWidget);
      expect(find.byType(QuickAddScreen), findsNothing);
    });

    testWidgets('«Расход» открывает «Новый расход», «Назад» возвращает', (
      tester,
    ) async {
      await _pumpApp(tester);

      await tester.tap(find.text('Расход'));
      await tester.pumpAndSettle();

      expect(find.byType(QuickAddScreen), findsOneWidget);
      final title = find.text('Новый расход');
      expect(title, findsOneWidget);
      final colors = tester.element(find.byType(QuickAddScreen)).appColors;
      expect(tester.widget<Text>(title).style?.color, colors.expense);
      final icon = find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.remove),
      );
      expect(tester.widget<Icon>(icon).color, colors.expense);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.byType(QuickAddScreen), findsNothing);
      expect(find.text('Доход'), findsOneWidget);
      expect(find.text('Расход'), findsOneWidget);
    });

    testWidgets('«Доход» открывает «Новый доход» цветом дохода', (
      tester,
    ) async {
      await _pumpApp(tester);

      await tester.tap(find.text('Доход'));
      await tester.pumpAndSettle();

      final title = find.text('Новый доход');
      expect(title, findsOneWidget);
      final colors = tester.element(find.byType(QuickAddScreen)).appColors;
      expect(tester.widget<Text>(title).style?.color, colors.income);
      final icon = find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.add),
      );
      expect(tester.widget<Icon>(icon).color, colors.income);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(QuickAddScreen), findsNothing);
    });
  });
}
