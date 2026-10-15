import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/ui/app_card.dart';
import 'package:money_app/core/ui/zuno_mark.dart';
import 'package:money_app/features/settings/domain/thanks.dart';
import 'package:money_app/features/settings/presentation/thanks_screen.dart';

Widget _screen(Thanks thanks, {double textScale = 1}) => MaterialApp(
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context)
        .copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: ThanksScreen(load: () async => thanks),
);

void main() {
  testWidgets('все уровни пусты — заглушка и знак, подзаголовков нет', (
    tester,
  ) async {
    await tester.pumpWidget(_screen(Thanks.empty));
    await tester.pumpAndSettle();

    expect(find.text(thanksTitle), findsOneWidget);
    expect(find.text(thanksEmptyText), findsOneWidget);
    expect(find.byType(ZunoMark), findsOneWidget);
    expect(find.text(thanksIntro), findsNothing);
    for (final tier in [thanksTier3Title, thanksTier2Title, thanksTier1Title]) {
      expect(find.text(tier), findsNothing);
    }
  });

  testWidgets('заглушка — по центру экрана', (tester) async {
    await tester.pumpWidget(_screen(Thanks.empty));
    await tester.pumpAndSettle();
    final body = tester.getRect(find.byType(SingleChildScrollView));
    final text = tester.getCenter(find.text(thanksEmptyText));
    expect(text.dx, moreOrLessEquals(body.center.dx, epsilon: 1));
    // Знак и текст вместе по центру: текст чуть ниже середины.
    expect((text.dy - body.center.dy).abs(), lessThan(48));
  });

  testWidgets('три имени Tier 3 — карточка, имя на строку', (tester) async {
    await tester.pumpWidget(
      _screen(const Thanks(tier3: ['Мария', 'Борис', 'Ли'])),
    );
    await tester.pumpAndSettle();

    expect(find.text(thanksIntro), findsOneWidget);
    expect(find.text(thanksEmptyText), findsNothing);
    expect(find.text(thanksTier3Title), findsOneWidget);
    expect(find.text(thanksTier2Title), findsNothing);
    expect(find.text(thanksTier1Title), findsNothing);
    final card = find.byType(AppCard);
    expect(card, findsOneWidget);
    for (final name in ['Мария', 'Борис', 'Ли']) {
      expect(
        find.descendant(of: card, matching: find.text(name)),
        findsOneWidget,
      );
    }
    double top(String name) => tester.getTopLeft(find.text(name)).dy;
    expect(top('Мария'), lessThan(top('Борис')));
    expect(top('Борис'), lessThan(top('Ли')));
    final style = tester.widget<Text>(find.text('Мария')).style!;
    expect(style.fontWeight, FontWeight.w500);
    expect(
      style.fontSize,
      Theme.of(tester.element(card)).textTheme.titleMedium!.fontSize,
    );
  });

  testWidgets('уровни сверху вниз — от Tier 3 к Tier 1, Tier 2 и 1 абзацем', (
    tester,
  ) async {
    await tester.pumpWidget(
      _screen(
        const Thanks(tier3: ['Мария'], tier2: ['Ким', 'Ян'], tier1: ['Ли']),
      ),
    );
    await tester.pumpAndSettle();

    double top(String text) => tester.getTopLeft(find.text(text)).dy;
    expect(top(thanksTier3Title), lessThan(top(thanksTier2Title)));
    expect(top(thanksTier2Title), lessThan(top(thanksTier1Title)));
    // Карточка только у Tier 3.
    expect(find.byType(AppCard), findsOneWidget);
    expect(
      find.descendant(of: find.byType(Wrap), matching: find.text('Ким')),
      findsOneWidget,
    );
    // «Ким · Ян» — в одной строке.
    expect(top('Ким'), top('Ян'));
    expect(find.text(thanksNameSeparator), findsOneWidget);
  });

  testWidgets('пустой уровень скрыт вместе с подзаголовком', (tester) async {
    await tester.pumpWidget(_screen(const Thanks(tier1: ['Ли'])));
    await tester.pumpAndSettle();
    expect(find.text(thanksTier1Title), findsOneWidget);
    expect(find.text(thanksTier3Title), findsNothing);
    expect(find.text(thanksTier2Title), findsNothing);
    expect(find.byType(AppCard), findsNothing);
  });

  testWidgets('подзаголовки уровней — заголовки для скринридера, точки '
      'не озвучиваются', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _screen(
        const Thanks(tier3: ['Мария'], tier2: ['Ким', 'Ян'], tier1: ['Ли']),
      ),
    );
    await tester.pumpAndSettle();
    for (final tier in [thanksTier3Title, thanksTier2Title, thanksTier1Title]) {
      expect(
        tester.getSemantics(find.text(tier)),
        matchesSemantics(label: tier, isHeader: true),
      );
    }
    expect(find.bySemanticsLabel(RegExp('·')), findsNothing);
    semantics.dispose();
  });

  testWidgets('200 имён в Tier 1 при 200 % и 360 dp — без переполнения, '
      'с прокруткой', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final names = [for (var i = 1; i <= 200; i++) 'Поддержавший_$i'];
    await tester.pumpWidget(
      _screen(
        Thanks(
          tier3: const ['Очень-очень-длинное-имя-без-пробелов'],
          tier1: names,
        ),
        textScale: 2,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text(names.last), findsNothing);
    await tester.scrollUntilVisible(find.text(names.last), 500);
    expect(find.text(names.last), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('на экране нет слов о деньгах и Boosty', (tester) async {
    for (final thanks in [
      Thanks.empty,
      const Thanks(tier3: ['Мария'], tier2: ['Ким'], tier1: ['Ли']),
    ]) {
      await tester.pumpWidget(_screen(thanks));
      await tester.pumpAndSettle();
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data ?? '')
          .join(' ')
          .toLowerCase();
      for (final word in [
        'донат',
        'поддерж',
        'boosty',
        'деньг',
        'оплат',
        '₽',
      ]) {
        expect(texts, isNot(contains(word)), reason: word);
      }
    }
  });
}
