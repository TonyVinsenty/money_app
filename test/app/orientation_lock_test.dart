import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/app/orientation_lock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'lockPortraitOrientation просит у платформы только portraitUp',
    () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            calls.add(call);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );

      await lockPortraitOrientation();

      final call = calls.singleWhere(
        (c) => c.method == 'SystemChrome.setPreferredOrientations',
      );
      expect(call.arguments, ['DeviceOrientation.portraitUp']);
    },
  );

  test('в Android-манифесте у MainActivity закреплён портрет', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();

    expect(manifest, contains('android:screenOrientation="portrait"'));
  });

  group('iOS Info.plist', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();

    // Значения строк внутри массива под ключом [key].
    List<String> orientationsUnder(String key) {
      final match = RegExp(
        '<key>${RegExp.escape(key)}</key>\\s*<array>(.*?)</array>',
        dotAll: true,
      ).firstMatch(plist);
      expect(match, isNotNull, reason: 'нет ключа $key');
      return RegExp('<string>(.*?)</string>')
          .allMatches(match!.group(1)!)
          .map((m) => m.group(1)!)
          .toList();
    }

    test('на iPhone разрешён только портрет', () {
      expect(orientationsUnder('UISupportedInterfaceOrientations'), [
        'UIInterfaceOrientationPortrait',
      ]);
    });

    test('на iPad разрешён только портрет и экран без разделения', () {
      expect(orientationsUnder('UISupportedInterfaceOrientations~ipad'), [
        'UIInterfaceOrientationPortrait',
      ]);
      // Без этого флага iPad требует поддержки всех ориентаций.
      expect(
        RegExp(r'<key>UIRequiresFullScreen</key>\s*<true/>').hasMatch(plist),
        isTrue,
      );
    });
  });
}
