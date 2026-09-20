import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/app/app_scope.dart';
import 'package:money_app/app/app_services.dart';
import 'package:money_app/core/database/app_database.dart';
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';

import '../support/fakes.dart';
import '../support/in_memory_database.dart';

void main() {
  late AppSettingsController settings;

  setUp(() {
    settings = AppSettingsController();
  });

  tearDown(() {
    settings.dispose();
  });

  group('AppScope.of', () {
    testWidgets('экран получает из scope тот же объект, что положили', (
      tester,
    ) async {
      final categories = FakeCategoriesRepository();
      final transactions = FakeTransactionsRepository();
      final services = fakeAppServices(
        settings: settings,
        categories: categories,
        transactions: transactions,
      );
      AppServices? seen;

      await tester.pumpWidget(
        AppScope(
          services: services,
          child: Builder(
            builder: (context) {
              seen = AppScope.of(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(seen, same(services));
      expect(seen!.categories, same(categories));
      expect(seen!.transactions, same(transactions));
      expect(seen!.settings, same(settings));
    });

    testWidgets('без AppScope бросает FlutterError с понятным текстом', (
      tester,
    ) async {
      await tester.pumpWidget(const SizedBox());
      final context = tester.element(find.byType(SizedBox));

      expect(
        () => AppScope.of(context),
        throwsA(
          isA<FlutterError>().having(
            (error) => error.toString(),
            'текст',
            allOf(
              contains('AppScope не найден'),
              contains('ниже AppScope'),
              contains('AppScope(services:'),
            ),
          ),
        ),
      );
    });

    testWidgets('maybeOf без AppScope возвращает null', (tester) async {
      await tester.pumpWidget(const SizedBox());
      final context = tester.element(find.byType(SizedBox));

      expect(AppScope.maybeOf(context), isNull);
    });

    testWidgets('maybeOf с AppScope возвращает сервисы', (tester) async {
      final services = fakeAppServices(settings: settings);
      AppServices? seen;

      await tester.pumpWidget(
        AppScope(
          services: services,
          child: Builder(
            builder: (context) {
              seen = AppScope.maybeOf(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(seen, same(services));
    });
  });

  group('перестроение зависимых', () {
    testWidgets('смена настроек перестраивает только вызвавших of', (
      tester,
    ) async {
      final services = fakeAppServices(settings: settings);
      var dependentBuilds = 0;
      var independentBuilds = 0;

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: AppScope(
            services: services,
            child: Column(
              children: [
                Builder(
                  builder: (context) {
                    AppScope.of(context);
                    dependentBuilds++;
                    return const SizedBox();
                  },
                ),
                Builder(
                  builder: (context) {
                    independentBuilds++;
                    return const SizedBox();
                  },
                ),
              ],
            ),
          ),
        ),
      );
      expect(dependentBuilds, 1);
      expect(independentBuilds, 1);

      settings.setThemeMode(ThemeMode.dark);
      await tester.pump();

      expect(dependentBuilds, 2);
      expect(independentBuilds, 1);
    });

    testWidgets('повторная установка той же темы никого не перестраивает', (
      tester,
    ) async {
      final services = fakeAppServices(settings: settings);
      var builds = 0;

      await tester.pumpWidget(
        AppScope(
          services: services,
          child: Builder(
            builder: (context) {
              AppScope.of(context);
              builds++;
              return const SizedBox();
            },
          ),
        ),
      );

      settings.setThemeMode(ThemeMode.system);
      await tester.pump();

      expect(builds, 1);
    });

    testWidgets('подмена набора сервисов перестраивает зависимых', (
      tester,
    ) async {
      final first = fakeAppServices(settings: settings);
      final second = fakeAppServices(settings: settings);
      final seen = <AppServices>[];

      Widget app(AppServices services) {
        return AppScope(
          services: services,
          child: Builder(
            builder: (context) {
              seen.add(AppScope.of(context));
              return const SizedBox();
            },
          ),
        );
      }

      await tester.pumpWidget(app(first));
      await tester.pumpWidget(app(second));

      expect(seen.last, same(second));
      expect(seen.first, same(first));
    });
  });

  group('AppScopeHost', () {
    late AppDatabase first;
    late AppDatabase second;

    setUp(() async {
      // Тесту нужны две базы одновременно (проверка «пришла другая база»),
      // а drift в отладочном режиме предупреждает о нескольких экземплярах
      // одного класса. Здесь это намеренно.
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      first = await openInMemoryDatabase();
      second = await openInMemoryDatabase();
    });

    tearDown(() async {
      await first.close();
      await second.close();
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
    });

    Widget host(AppDatabase database, List<AppServices> seen) {
      return AppScopeHost(
        database: database,
        settings: settings,
        child: Builder(
          builder: (context) {
            seen.add(AppScope.of(context));
            return const SizedBox();
          },
        ),
      );
    }

    testWidgets('репозитории создаются один раз и переживают перерисовки', (
      tester,
    ) async {
      final seen = <AppServices>[];

      await tester.pumpWidget(host(first, seen));
      // Новый экземпляр хозяина с той же базой: перерисовка родителя.
      await tester.pumpWidget(host(first, seen));
      settings.setThemeMode(ThemeMode.dark);
      await tester.pump();

      expect(seen.length, greaterThanOrEqualTo(3));
      for (final services in seen) {
        expect(services, same(seen.first));
      }
      expect(seen.last.categories, same(seen.first.categories));
      expect(seen.last.transactions, same(seen.first.transactions));
      expect(seen.first.settings, same(settings));
    });

    testWidgets('другая база пересоздаёт сервисы', (tester) async {
      final seen = <AppServices>[];

      await tester.pumpWidget(host(first, seen));
      final before = seen.last;
      await tester.pumpWidget(host(second, seen));
      final after = seen.last;

      expect(after, isNot(same(before)));
      expect(after.categories, isNot(same(before.categories)));
      expect(after.transactions, isNot(same(before.transactions)));
    });
  });
}
