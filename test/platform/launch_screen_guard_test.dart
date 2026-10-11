// Сторож экрана запуска (шаг 7.4, ADR 0013): без белой вспышки в тёмной теме.

import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';

const _res = 'android/app/src/main/res';

String _read(String path) => File(path).readAsStringSync();

String _hex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).toUpperCase().padLeft(6, '0')}';

void main() {
  test('iOS storyboard uses systemBackgroundColor, not white', () {
    final sb = _read('ios/Runner/Base.lproj/LaunchScreen.storyboard');
    expect(sb, contains('systemColor="systemBackgroundColor"'));
    expect(sb, isNot(contains('red="1" green="1" blue="1"')));
  });

  test('Android 12+ splash background: light is F3F5F6', () {
    final xml = _read('$_res/values-v31/styles.xml');
    expect(xml, contains('android:windowSplashScreenBackground'));
    expect(xml, contains('#F3F5F6'));
  });

  test('Android 12+ splash background: dark equals theme surface', () {
    final xml = _read('$_res/values-night-v31/styles.xml');
    expect(xml, contains('android:windowSplashScreenBackground'));
    expect(xml, contains(_hex(AppTheme.dark().colorScheme.surface)));
  });
}
