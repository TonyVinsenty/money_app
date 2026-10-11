import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/ui/masked_amount.dart';

Widget _host({required bool? hidden, required Widget child}) {
  final body = Center(child: child);
  return MaterialApp(
    home: Scaffold(
      body: hidden == null
          ? body
          : AmountsVisibility(hidden: hidden, child: body),
    ),
  );
}

void main() {
  testWidgets('без AmountsVisibility сумма видна', (tester) async {
    await tester.pumpWidget(
      _host(hidden: null, child: const MaskedAmount('5 000 ₽')),
    );
    expect(find.text('5 000 ₽'), findsOneWidget);
    expect(find.byKey(const ValueKey('masked-amount-cloud')), findsNothing);
  });

  testWidgets('показано: обычный текст с озвучкой', (tester) async {
    await tester.pumpWidget(
      _host(
        hidden: false,
        child: const MaskedAmount('5 000 ₽', semanticsLabel: '5000 рублей'),
      ),
    );
    expect(find.text('5 000 ₽'), findsOneWidget);
    expect(find.bySemanticsLabel('5000 рублей'), findsOneWidget);
  });

  testWidgets('скрыто: цифр нет, облачко, озвучка «сумма скрыта»', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(
        hidden: true,
        child: const MaskedAmount('5 000 ₽', semanticsLabel: '5000 рублей'),
      ),
    );
    expect(find.text('5 000 ₽'), findsNothing);
    expect(find.textContaining('5'), findsNothing);
    expect(find.byKey(const ValueKey('masked-amount-cloud')), findsOneWidget);
    expect(find.bySemanticsLabel(hiddenAmountLabel), findsOneWidget);
    expect(find.bySemanticsLabel('5000 рублей'), findsNothing);
    handle.dispose();
  });

  testWidgets('скрыто: ширина одна для короткой и длинной суммы', (
    tester,
  ) async {
    Future<Size> sizeOf(String text) async {
      await tester.pumpWidget(
        _host(hidden: true, child: MaskedAmount(text, key: const Key('a'))),
      );
      return tester.getSize(find.byKey(const Key('a')));
    }

    final short = await sizeOf('5 ₽');
    final long = await sizeOf('999 999 999,99 ₽');
    expect(short, long);
  });

  testWidgets('смена флага перестраивает сумму', (tester) async {
    await tester.pumpWidget(
      _host(hidden: false, child: const MaskedAmount('7 ₽')),
    );
    expect(find.text('7 ₽'), findsOneWidget);
    await tester.pumpWidget(
      _host(hidden: true, child: const MaskedAmount('7 ₽')),
    );
    expect(find.text('7 ₽'), findsNothing);
  });

  testWidgets('maskedMoney подменяет сумму во фразе', (tester) async {
    late String shown;
    late String hiddenText;
    await tester.pumpWidget(
      _host(
        hidden: false,
        child: Builder(
          builder: (context) {
            shown = maskedMoney(context, '10 ₽');
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pumpWidget(
      _host(
        hidden: true,
        child: Builder(
          builder: (context) {
            hiddenText = maskedMoney(context, '10 ₽');
            return const SizedBox();
          },
        ),
      ),
    );
    expect(shown, '10 ₽');
    expect(hiddenText, maskedMoneyText);
  });

  testWidgets('maskedSpoken подменяет озвучку', (tester) async {
    late String shown;
    late String hiddenText;
    Widget probe(bool hidden, void Function(String) save) => _host(
      hidden: hidden,
      child: Builder(
        builder: (context) {
          save(maskedSpoken(context, '10 рублей'));
          return const SizedBox();
        },
      ),
    );
    await tester.pumpWidget(probe(false, (s) => shown = s));
    await tester.pumpWidget(probe(true, (s) => hiddenText = s));
    expect(shown, '10 рублей');
    expect(hiddenText, hiddenAmountLabel);
  });

  testWidgets('maxLines, softWrap и overflow доходят до Text', (tester) async {
    await tester.pumpWidget(
      _host(
        hidden: false,
        child: const MaskedAmount(
          '5 ₽',
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
    final text = tester.widget<Text>(find.text('5 ₽'));
    expect(text.maxLines, 1);
    expect(text.softWrap, isFalse);
    expect(text.overflow, TextOverflow.ellipsis);
  });
}
