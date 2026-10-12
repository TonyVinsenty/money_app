import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/features/recurring/domain/recurring_payment.dart';
import 'package:money_app/features/recurring/domain/recurring_repository.dart';
import 'package:money_app/features/recurring/presentation/due_banner.dart';
import 'package:money_app/features/recurring/presentation/recurring_texts.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

import '../../../support/roboto_font.dart';

RecurringDue _due(String id, String title, {int minor = 65000}) => RecurringDue(
  id: id,
  payment: RecurringPayment(
    id: 'p-$id',
    title: title,
    type: TransactionType.expense,
    amount: Money.fromMinor(minor, 'RUB'),
    categoryId: 'cat',
    unit: RepeatUnit.month,
    every: 1,
    startsOn: DateOnly(2026, 10, 10),
  ),
  dueOn: DateOnly(2026, 10, 10),
  status: RecurringDueStatus.pending,
);

Widget _host(ValueNotifier<List<RecurringDue>> dues, VoidCallback onTap) =>
    MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            DueBanner(dues: dues, onTap: onTap),
            const Text('below'),
          ],
        ),
      ),
    );

void main() {
  final dash = String.fromCharCode(0x2014);

  testWidgets('нет записей: плашки нет и высота нулевая', (tester) async {
    final dues = ValueNotifier<List<RecurringDue>>(const []);
    addTearDown(dues.dispose);
    await tester.pumpWidget(_host(dues, () {}));
    expect(find.byKey(DueBanner.bannerKey), findsNothing);
    expect(tester.getTopLeft(find.text('below')).dy, 0);
  });

  testWidgets('одна запись: название и сумма; тап вызывает onTap', (
    tester,
  ) async {
    final dues = ValueNotifier([_due('1', 'Интернет')]);
    addTearDown(dues.dispose);
    var taps = 0;
    await tester.pumpWidget(_host(dues, () => taps++));
    final money = formatMoney(Money.fromMinor(65000, 'RUB'));
    expect(find.text('К оплате: Интернет'), findsOneWidget);
    expect(find.text(' $dash $money'), findsOneWidget);
    await tester.tap(find.byKey(DueBanner.bannerKey));
    expect(taps, 1);
  });

  testWidgets('три записи: число; исчезает, когда записи оплачены', (
    tester,
  ) async {
    final dues = ValueNotifier([
      _due('1', 'Интернет'),
      _due('2', 'Аренда'),
      _due('3', 'Спортзал'),
    ]);
    addTearDown(dues.dispose);
    await tester.pumpWidget(_host(dues, () {}));
    expect(find.text('К оплате: 3 платежа'), findsOneWidget);
    dues.value = const [];
    await tester.pump();
    expect(find.byKey(DueBanner.bannerKey), findsNothing);
  });

  testWidgets('озвучка: «К оплате 3 платежа. Открыть»', (tester) async {
    final handle = tester.ensureSemantics();
    final dues = ValueNotifier([
      _due('1', 'Интернет'),
      _due('2', 'Аренда'),
      _due('3', 'Спортзал'),
    ]);
    addTearDown(dues.dispose);
    await tester.pumpWidget(_host(dues, () {}));
    expect(
      find.bySemanticsLabel('К оплате 3 платежа. Открыть'),
      findsOneWidget,
    );
    handle.dispose();
  });

  group('длинное название и большая сумма видны целиком (7.36)', () {
    // Настоящий Roboto: тестовый шрифт рисует буквы квадратами, и ширину
    // текста по нему не проверить.
    setUpAll(loadRoboto);

    const title = 'Квартплата и коммунальные услуги за дачу';
    const minor = 99999999999;
    final head = find.text('К оплате: $title');
    final amount = find.byKey(DueBanner.amountKey);

    Future<void> pumpAt(WidgetTester tester, double scale) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final dues = ValueNotifier([_due('1', title, minor: minor)]);
      addTearDown(dues.dispose);
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(
            size: const Size(360, 800),
            textScaler: TextScaler.linear(scale),
          ),
          child: _host(dues, () {}),
        ),
      );
    }

    /// Текст выведен целиком: ни одна строка не отброшена.
    void expectWhole(WidgetTester tester, Finder text) {
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: text, matching: find.byType(RichText)),
      );
      expect(paragraph.didExceedMaxLines, isFalse);
      final banner = tester.getRect(find.byKey(DueBanner.bannerKey));
      final rect = tester.getRect(text);
      expect(rect.left, greaterThanOrEqualTo(banner.left));
      expect(rect.right, lessThanOrEqualTo(banner.right));
      expect(rect.bottom, lessThanOrEqualTo(banner.bottom));
    }

    test('название из 40 символов', () => expect(title.length, 40));

    testWidgets('100 %: название переносится, сумма в той же строке', (
      tester,
    ) async {
      await pumpAt(tester, 1);
      expect(tester.takeException(), isNull);
      expectWhole(tester, head);
      expectWhole(tester, amount);
      final money = formatMoney(Money.fromMinor(minor, 'RUB'));
      expect(find.text(' $dash $money'), findsOneWidget);
      expect(
        tester.getTopLeft(amount).dx,
        greaterThanOrEqualTo(tester.getTopRight(head).dx),
      );
    });

    for (final scale in [1.3, 2.0]) {
      testWidgets('${scale * 100} %: сумма под названием, без тире', (
        tester,
      ) async {
        await pumpAt(tester, scale);
        expect(tester.takeException(), isNull);
        expectWhole(tester, head);
        expectWhole(tester, amount);
        expect(
          find.text(formatMoney(Money.fromMinor(minor, 'RUB'))),
          findsOneWidget,
        );
        expect(
          tester.getTopLeft(amount).dy,
          greaterThanOrEqualTo(tester.getBottomLeft(head).dy),
        );
        expect(tester.getTopLeft(amount).dx, tester.getTopLeft(head).dx);
      });
    }

    testWidgets('200 %: несколько платежей - текст не обрезан', (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final dues = ValueNotifier([
        for (var i = 0; i < 124; i++) _due('$i', 'Платёж $i'),
      ]);
      addTearDown(dues.dispose);
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 800),
            textScaler: TextScaler.linear(2),
          ),
          child: _host(dues, () {}),
        ),
      );
      expect(tester.takeException(), isNull);
      expectWhole(tester, find.text('К оплате: 124 платежа'));
    });
  });

  testWidgets('озвучка одного платежа: «К оплате: Интернет, 650 рублей. '
      'Открыть»', (tester) async {
    final handle = tester.ensureSemantics();
    final dues = ValueNotifier([_due('1', 'Интернет')]);
    addTearDown(dues.dispose);
    await tester.pumpWidget(_host(dues, () {}));
    expect(
      find.bySemanticsLabel('К оплате: Интернет, 650 рублей. Открыть'),
      findsOneWidget,
    );
    handle.dispose();
  });

  group('склонение «платёж»', () {
    String text(int n) =>
        dueBannerText([for (var i = 0; i < n; i++) _due('$i', 'Платёж $i')]);

    test('формы слова', () {
      expect(text(2), 'К оплате: 2 платежа');
      expect(text(5), 'К оплате: 5 платежей');
      expect(text(11), 'К оплате: 11 платежей');
      expect(text(21), 'К оплате: 21 платёж');
      expect(text(24), 'К оплате: 24 платежа');
    });
  });
}
