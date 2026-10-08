import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/money/currency_catalog.dart';
import 'package:money_app/core/ui/currency_picker.dart';

CurrencyInfo? _result;
bool _closed = false;

Future<void> _open(
  WidgetTester tester, {
  String? selected,
  bool fiatOnly = false,
  List<CurrencyInfo> yours = const [],
  Future<CurrencyInfo?> Function()? onCustom,
  double textScale = 1,
  Size size = const Size(400, 800),
}) async {
  _result = null;
  _closed = false;
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                _result = await showCurrencyPicker(
                  context,
                  selected: selected,
                  fiatOnly: fiatOnly,
                  yourCurrencies: yours,
                  onCustom: onCustom,
                );
                _closed = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

List<String> _headers(WidgetTester tester) {
  const names = {
    currencyPickerPopular,
    currencyPickerYours,
    currencyPickerAll,
    currencyPickerCrypto,
  };
  return [
    for (final w in tester.widgetList<Text>(find.byType(Text)))
      if (names.contains(w.data)) w.data!,
  ];
}

void main() {
  const myCoin = CurrencyInfo(
    code: 'MYC',
    digits: 3,
    symbol: 'MYC',
    name: 'MYC',
    kind: CurrencyKind.custom,
  );

  testWidgets('empty search: groups in order, title and hint', (tester) async {
    await _open(tester, yours: [myCoin]);
    expect(find.text(currencyPickerTitle), findsOneWidget);
    expect(find.text(currencyPickerSearchHint), findsOneWidget);
    expect(_headers(tester), [
      currencyPickerPopular,
      currencyPickerYours,
      currencyPickerAll,
    ]);
    // Первая строка - рубль, подпись с символом.
    expect(find.text('Российский рубль'), findsWidgets);
    expect(find.text('RUB · ₽'), findsWidgets);
    // Ниже по списку - крипта.
    await tester.scrollUntilVisible(
      find.text(currencyPickerCrypto),
      500,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text(currencyPickerCrypto), findsOneWidget);
  });

  testWidgets('search by name part finds dollars', (tester) async {
    await _open(tester);
    await tester.enterText(find.byType(TextField), 'ДОЛ');
    await tester.pump();
    expect(find.text('Доллар США'), findsOneWidget);
    expect(find.text('Канадский доллар'), findsOneWidget);
    expect(find.text('Австралийский доллар'), findsOneWidget);
    expect(find.text('Российский рубль'), findsNothing);
    expect(_headers(tester), isEmpty);
  });

  testWidgets('search by code and by symbol finds USD', (tester) async {
    await _open(tester);
    await tester.enterText(find.byType(TextField), 'usd');
    await tester.pump();
    expect(find.text('Доллар США'), findsOneWidget);
    await tester.enterText(find.byType(TextField), r'$');
    await tester.pump();
    expect(find.text('Доллар США'), findsOneWidget);
    expect(find.text('Канадский доллар'), findsNothing);
  });

  testWidgets('nothing found: message and custom row', (tester) async {
    await _open(tester, onCustom: () async => null);
    await tester.enterText(find.byType(TextField), 'qqqqq');
    await tester.pump();
    expect(find.text(currencyPickerNothingFound), findsOneWidget);
    expect(find.text('Ничего не нашлось'), findsNothing);
    expect(find.text(currencyPickerCustom), findsOneWidget);
    expect(find.text(currencyPickerCustomHint), findsOneWidget);
  });

  testWidgets('clear button resets search', (tester) async {
    await _open(tester);
    expect(find.byTooltip(currencyPickerClearSearch), findsNothing);
    await tester.enterText(find.byType(TextField), 'usd');
    await tester.pump();
    await tester.tap(find.byTooltip(currencyPickerClearSearch));
    await tester.pump();
    expect(_headers(tester), isNotEmpty);
  });

  testWidgets('fiatOnly: no crypto, no yours, no custom', (tester) async {
    await _open(
      tester,
      fiatOnly: true,
      yours: [myCoin],
      onCustom: () async => myCoin,
    );
    await tester.scrollUntilVisible(
      find.text('Зимбабвийское золото'),
      500,
      scrollable: find.byType(Scrollable).last,
    );
    expect(_headers(tester), isNot(contains(currencyPickerCrypto)));
    expect(_headers(tester), isNot(contains(currencyPickerYours)));
    expect(find.text(currencyPickerCustom), findsNothing);
    await tester.enterText(find.byType(TextField), 'btc');
    await tester.pump();
    expect(find.text(currencyPickerNothingFound), findsOneWidget);
    expect(find.text(currencyPickerCustom), findsNothing);
  });

  testWidgets('no onCustom: no custom row', (tester) async {
    await _open(tester);
    await tester.enterText(find.byType(TextField), 'qqqqq');
    await tester.pump();
    expect(find.text(currencyPickerCustom), findsNothing);
  });

  testWidgets('tap returns the catalog entry', (tester) async {
    await _open(tester);
    await tester.enterText(find.byType(TextField), 'eur');
    await tester.pump();
    await tester.tap(find.text('Евро'));
    await tester.pumpAndSettle();
    expect(_closed, isTrue);
    expect(_result?.code, 'EUR');
  });

  testWidgets('custom row: result closes the sheet with it', (tester) async {
    await _open(tester, onCustom: () async => myCoin);
    await tester.enterText(find.byType(TextField), 'qqqqq');
    await tester.pump();
    await tester.tap(find.text(currencyPickerCustom));
    await tester.pumpAndSettle();
    expect(_closed, isTrue);
    expect(_result, myCoin);
  });

  testWidgets('custom row: null result keeps the sheet open', (tester) async {
    await _open(tester, onCustom: () async => null);
    await tester.enterText(find.byType(TextField), 'qqqqq');
    await tester.pump();
    await tester.tap(find.text(currencyPickerCustom));
    await tester.pumpAndSettle();
    expect(_closed, isFalse);
    expect(find.text(currencyPickerNothingFound), findsOneWidget);
  });

  testWidgets('semantics: name and code, selected flag once', (tester) async {
    final handle = tester.ensureSemantics();
    await _open(tester, selected: 'BTC');
    await tester.enterText(find.byType(TextField), 'btc');
    await tester.pump();
    final node = tester.getSemantics(find.text('Биткоин'));
    expect(node.label, 'Биткоин, BTC');
    expect(node.label.contains('выбран'), isFalse);
    expect(node.flagsCollection.isSelected.name, 'isTrue');
    await tester.enterText(find.byType(TextField), 'eth');
    await tester.pump();
    final other = tester.getSemantics(find.text('Эфир'));
    expect(other.flagsCollection.isSelected.name, isNot('isTrue'));
    handle.dispose();
  });

  testWidgets('same symbol as code: subtitle is only the code', (tester) async {
    await _open(tester);
    await tester.enterText(find.byType(TextField), 'биткоин');
    await tester.pump();
    expect(find.text('BTC'), findsOneWidget);
    expect(find.textContaining('·'), findsNothing);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('360 dp, font x$scale: no overflow, list scrolls', (
      tester,
    ) async {
      await _open(
        tester,
        textScale: scale,
        size: const Size(360, 640),
        onCustom: () async => null,
      );
      expect(find.byType(TextField), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text(currencyPickerCustom),
        800,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('Нидерландский антильский гульден'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.enterText(find.byType(TextField), 'гульден');
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
}
