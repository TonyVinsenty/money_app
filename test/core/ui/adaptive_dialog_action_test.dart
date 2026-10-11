import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/ui/adaptive_dialog_action.dart';

/// Кнопка диалога-подтверждения (ADR 0013, п. 6; шаг 7.31).
void main() {
  Future<void> pump(
    WidgetTester tester,
    TargetPlatform platform,
    AdaptiveDialogAction action,
  ) {
    return tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: platform),
        home: Scaffold(body: Center(child: action)),
      ),
    );
  }

  group('iPhone', () {
    testWidgets('системная кнопка с тем же обработчиком', (tester) async {
      var taps = 0;
      await pump(
        tester,
        TargetPlatform.iOS,
        AdaptiveDialogAction(onPressed: () => taps++, label: 'Отмена'),
      );
      expect(find.byType(CupertinoDialogAction), findsOneWidget);
      expect(find.byType(TextButton), findsNothing);
      // Нажатия ловит сам CupertinoAlertDialog; здесь — что обработчик тот же.
      tester
          .widget<CupertinoDialogAction>(find.byType(CupertinoDialogAction))
          .onPressed!();
      expect(taps, 1);
    });

    testWidgets('удаление — красное, главное — жирное', (tester) async {
      await pump(
        tester,
        TargetPlatform.iOS,
        AdaptiveDialogAction(
          onPressed: () {},
          label: 'Удалить',
          destructive: true,
        ),
      );
      var action = tester.widget<CupertinoDialogAction>(
        find.byType(CupertinoDialogAction),
      );
      expect(action.isDestructiveAction, isTrue);
      expect(action.isDefaultAction, isFalse);

      await pump(
        tester,
        TargetPlatform.iOS,
        AdaptiveDialogAction(onPressed: () {}, label: 'В архив', primary: true),
      );
      action = tester.widget<CupertinoDialogAction>(
        find.byType(CupertinoDialogAction),
      );
      expect(action.isDefaultAction, isTrue);
      expect(action.isDestructiveAction, isFalse);
    });
  });

  group('Android — прежние кнопки', () {
    testWidgets('обычная — TextButton', (tester) async {
      var taps = 0;
      await pump(
        tester,
        TargetPlatform.android,
        AdaptiveDialogAction(onPressed: () => taps++, label: 'Отмена'),
      );
      expect(find.byType(CupertinoDialogAction), findsNothing);
      await tester.tap(find.widgetWithText(TextButton, 'Отмена'));
      expect(taps, 1);
    });

    testWidgets('удаление — TextButton цвета ошибки', (tester) async {
      await pump(
        tester,
        TargetPlatform.android,
        AdaptiveDialogAction(
          onPressed: () {},
          label: 'Удалить',
          destructive: true,
        ),
      );
      final context = tester.element(find.text('Удалить'));
      expect(
        DefaultTextStyle.of(context).style.color,
        Theme.of(context).colorScheme.error,
      );
    });

    testWidgets('главное — FilledButton', (tester) async {
      await pump(
        tester,
        TargetPlatform.android,
        AdaptiveDialogAction(onPressed: () {}, label: 'В архив', primary: true),
      );
      expect(find.widgetWithText(FilledButton, 'В архив'), findsOneWidget);
    });
  });
}
