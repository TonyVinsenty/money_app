import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/app/app_services.dart';
import 'package:money_app/core/database/app_database.dart';
import 'package:money_app/core/id/id_generator.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

import '../support/fake_id_generator.dart';
import '../support/fixed_clock.dart';

/// Подписывается на [stream], ждёт первую выдачу, выполняет [write], ждёт
/// обновление и возвращает все выдачи по порядку. Подписка до записи нужна,
/// чтобы увидеть именно «было пусто, стало так».
Future<List<List<T>>> _collect<T>(
  Stream<List<T>> stream,
  Future<void> Function() write,
) async {
  final emissions = <List<T>>[];
  final subscription = stream.listen(emissions.add);
  try {
    await pumpEventQueue();
    await write();
    await pumpEventQueue();
  } finally {
    await subscription.cancel();
  }
  return emissions;
}

void main() {
  group('AppServices.forDatabase', () {
    late AppDatabase db;
    late AppSettingsController settings;
    late FixedClock clock;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      settings = AppSettingsController();
      clock = FixedClock(DateTime.utc(2026, 9, 20, 12));
    });

    tearDown(() async {
      settings.dispose();
      await db.close();
    });

    final food = Category.topLevel(
      id: 'cat-food',
      kind: CategoryKind.expense,
      name: 'Еда',
      iconKey: 'restaurant',
      sortOrder: 0,
    );

    test('passes settings and clock through, id generator is UUID v7', () {
      final services = AppServices.forDatabase(
        db,
        settings: settings,
        clock: clock,
      );

      expect(services.settings, same(settings));
      expect(services.clock, same(clock));
      expect(services.idGenerator, isA<UuidV7Generator>());
    });

    test('uses the given id generator instead of the default one', () {
      final ids = FakeIdGenerator();

      final services = AppServices.forDatabase(
        db,
        settings: settings,
        idGenerator: ids,
      );

      expect(services.idGenerator, same(ids));
    });

    test('uses the system clock when none is given', () {
      final services = AppServices.forDatabase(db, settings: settings);

      final now = DateTime.now();
      expect(services.clock.now().difference(now).inMinutes.abs(), lessThan(1));
    });

    test(
      'a category created via services.categories shows up in its stream',
      () async {
        final services = AppServices.forDatabase(
          db,
          settings: settings,
          clock: clock,
        );

        final emissions = await _collect(
          services.categories.watchTopLevel(CategoryKind.expense),
          () => services.categories.create(food),
        );

        expect(emissions.first, isEmpty);
        expect(emissions.last, [food]);
        expect(await services.categories.findById('cat-food'), food);
      },
    );

    test('a transaction added via services.transactions shows up in '
        'watchRecent', () async {
      final services = AppServices.forDatabase(
        db,
        settings: settings,
        clock: clock,
      );
      await services.categories.create(food);
      final lunch = Transaction(
        id: 'tx-1',
        type: TransactionType.expense,
        amount: Money.fromMinor(35050, 'RUB'),
        occurredOn: DateOnly(2026, 9, 20),
        occurredAt: DateTime.utc(2026, 9, 20, 9),
        categoryId: food.id,
        note: 'Обед',
      );

      final emissions = await _collect(
        services.transactions.watchRecent(),
        () => services.transactions.add(lunch),
      );

      expect(emissions.first, isEmpty);
      expect(emissions.last, [lunch]);
      expect(await services.transactions.findById('tx-1'), lunch);
    });
  });
}
