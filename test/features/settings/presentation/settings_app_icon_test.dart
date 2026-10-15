import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/money/currency_catalog.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/features/settings/domain/app_icon_choice.dart';
import 'package:money_app/features/settings/domain/app_icon_service.dart';
import 'package:money_app/features/settings/domain/home_balance_line.dart';
import 'package:money_app/features/settings/presentation/settings_screen.dart';

/// Подменённая система: помнит текущую иконку и все вызовы `set`.
class _FakeIcons implements AppIconService {
  _FakeIcons({
    this.isSupported = true,
    this.icon = AppIconChoice.ring,
    this.accept = true,
  });

  final bool isSupported;
  final bool accept;
  AppIconChoice icon;
  final sets = <AppIconChoice>[];

  @override
  Future<bool> supported() async => isSupported;

  @override
  Future<AppIconChoice?> current() async => icon;

  @override
  Future<bool> set(AppIconChoice choice) async {
    sets.add(choice);
    if (accept) icon = choice;
    return accept;
  }
}

Widget _screen(
  AppIconService? icons, {
  TargetPlatform platform = TargetPlatform.android,
  double textScale = 1,
}) => MaterialApp(
  theme: ThemeData(platform: platform),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context)
        .copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: Scaffold(
    body: SettingsScreen(
      themeMode: ThemeMode.system,
      onThemeModeChanged: (_) {},
      homeBalanceLine: HomeBalanceLine.allTime,
      onHomeBalanceLineChanged: (_) {},
      onOpenCategories: () {},
      onOpenThanks: () {},
      mainCurrency: currencyInfoFor('RUB'),
      onMainCurrencyChanged: (_) {},
      onExportCsv: () async => '',
      lastExportDay: null,
      today: DateOnly(2026, 10, 15),
      onExportShared: () {},
      onImportCsv: () async => null,
      onClearAll: () async {},
      version: '1.0.0+29',
      onHideAmountsChanged: (_) {},
      appIcons: icons,
    ),
  ),
);

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.text(appIconItemLabel));
  await tester.pumpAndSettle();
}

/// Строка варианта в листе (по названию).
Finder _option(AppIconChoice choice) => find.descendant(
  of: find.byType(BottomSheet),
  matching: find.text(appIconLabel(choice)),
);

void main() {
  testWidgets('в «Внешнем виде» после «Темы», подпись — текущая иконка', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_screen(_FakeIcons(icon: AppIconChoice.coins)));
    await tester.pumpAndSettle();

    expect(find.text(appIconItemLabel), findsOneWidget);
    expect(find.text('Монеты'), findsOneWidget);
    double top(String text) => tester.getTopLeft(find.text(text)).dy;
    expect(top(appIconItemLabel), greaterThan(top(themeDarkLabel)));
    expect(top(appIconItemLabel), lessThan(top(hideAmountsLabel)));
  });

  testWidgets('система не умеет — строки нет', (tester) async {
    await tester.pumpWidget(_screen(_FakeIcons(isSupported: false)));
    await tester.pumpAndSettle();
    expect(find.text(appIconItemLabel), findsNothing);
  });

  testWidgets('без сервиса — строки нет', (tester) async {
    await tester.pumpWidget(_screen(null));
    await tester.pumpAndSettle();
    expect(find.text(appIconItemLabel), findsNothing);
  });

  testWidgets('лист: четыре варианта с картинками, текущий отмечен', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_screen(_FakeIcons(icon: AppIconChoice.wallet)));
    await tester.pumpAndSettle();
    await _openSheet(tester);

    for (final choice in AppIconChoice.values) {
      expect(_option(choice), findsOneWidget, reason: choice.id);
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.image(AssetImage(appIconPreviewAsset(choice))),
        ),
        findsOneWidget,
        reason: choice.id,
      );
    }
    final check = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byIcon(Icons.check),
    );
    expect(check, findsOneWidget);
    expect(
      tester.getCenter(check).dy,
      moreOrLessEquals(
        tester.getCenter(_option(AppIconChoice.wallet)).dy,
        epsilon: 12,
      ),
    );
    expect(
      tester.getSemantics(_option(AppIconChoice.wallet)),
      matchesSemantics(
        label: 'Кошелёк',
        isButton: true,
        hasSelectedState: true,
        isSelected: true,
        hasTapAction: true,
      ),
    );
    semantics.dispose();
  });

  testWidgets('касание другой — set и галочка переезжает', (tester) async {
    final icons = _FakeIcons();
    await tester.pumpWidget(_screen(icons));
    await tester.pumpAndSettle();
    await _openSheet(tester);
    await tester.tap(_option(AppIconChoice.ringBlue));
    await tester.pumpAndSettle();

    expect(icons.sets, [AppIconChoice.ringBlue]);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Кольцо на синем'), findsOneWidget); // подпись строки
    await _openSheet(tester);
    final check = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byIcon(Icons.check),
    );
    expect(
      tester.getCenter(check).dy,
      moreOrLessEquals(
        tester.getCenter(_option(AppIconChoice.ringBlue)).dy,
        epsilon: 12,
      ),
    );
  });

  testWidgets('касание текущей ничего не делает', (tester) async {
    final icons = _FakeIcons();
    await tester.pumpWidget(_screen(icons));
    await tester.pumpAndSettle();
    await _openSheet(tester);
    await tester.tap(_option(AppIconChoice.ring));
    await tester.pumpAndSettle();
    expect(icons.sets, isEmpty);
  });

  testWidgets('отказ системы — сообщение, подпись прежняя', (tester) async {
    final icons = _FakeIcons(accept: false);
    await tester.pumpWidget(_screen(icons));
    await tester.pumpAndSettle();
    await _openSheet(tester);
    await tester.tap(_option(AppIconChoice.coins));
    await tester.pumpAndSettle();

    expect(icons.sets, [AppIconChoice.coins]);
    expect(find.text(appIconFailedMessage), findsOneWidget);
    expect(find.text('Кольцо'), findsOneWidget);
    expect(find.text('Монеты'), findsNothing);
  });

  testWidgets('предупреждение только на Android', (tester) async {
    await tester.pumpWidget(_screen(_FakeIcons()));
    await tester.pumpAndSettle();
    await _openSheet(tester);
    expect(find.text(appIconAndroidWarning), findsOneWidget);

    // Новый экран целиком: прежний лист закрывается вместе с ним.
    await tester.pumpWidget(const SizedBox.shrink());

    await tester.pumpWidget(
      _screen(_FakeIcons(), platform: TargetPlatform.iOS),
    );
    await tester.pumpAndSettle();
    await _openSheet(tester);
    expect(find.text(appIconAndroidWarning), findsNothing);
  });

  testWidgets('200 % на 360 dp — без переполнения, картинки 56 dp', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_screen(_FakeIcons(), textScale: 2));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text(appIconItemLabel), 100);
    await _openSheet(tester);
    expect(tester.takeException(), isNull);
    final image = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(Image),
    );
    expect(tester.getSize(image.first), const Size.square(56));
    expect(tester.takeException(), isNull);
  });
}
