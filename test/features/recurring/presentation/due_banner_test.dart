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

  testWidgets('360 dp и шрифт 200 %: длинное название без переполнения', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dues = ValueNotifier([
      _due('1', 'Очень длинное название платежа за связь'),
    ]);
    addTearDown(dues.dispose);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(360, 640),
          textScaler: TextScaler.linear(2),
        ),
        child: _host(dues, () {}),
      ),
    );
    expect(find.byKey(DueBanner.bannerKey), findsOneWidget);
    expect(tester.takeException(), isNull);
    // Сумма видна целиком, в правой части плашки; название сокращено.
    final tail = find.text(
      ' $dash ${formatMoney(Money.fromMinor(65000, 'RUB'))}',
    );
    expect(tail, findsOneWidget);
    final banner = tester.getRect(find.byKey(DueBanner.bannerKey));
    expect(tester.getRect(tail).right, lessThanOrEqualTo(banner.right));
    final head = tester.renderObject<RenderParagraph>(
      find.text('К оплате: Очень длинное название платежа за связь'),
    );
    expect(head.didExceedMaxLines, isTrue);
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
