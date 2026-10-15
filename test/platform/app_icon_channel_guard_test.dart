// Сторож канала иконки (шаги 8.37–8.38, ADR 0014, п. 2–4 и 6): имя канала, методы
// и ключ в Dart, Kotlin и Swift совпадают; id вариантов в Dart, Kotlin, Swift,
// манифесте и project.pbxproj одни и те же; включён ровно ярлык иконки по
// умолчанию; фильтр запуска — только у ярлыков. Нативный код на Windows не
// собирается — проверяем текстом.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/features/settings/data/app_icon_channel.dart';
import 'package:money_app/features/settings/domain/app_icon_choice.dart';

/// id варианта -> ярлык Android. Менять нельзя (ADR 0014, п. 6).
const _aliases = {
  'ring': '.IconRing',
  'ring_blue': '.IconRingBlue',
  'coins': '.IconCoins',
  'wallet': '.IconWallet',
};

/// id альтернативной иконки -> набор iOS (у иконки по умолчанию — `AppIcon`).
const _iosSets = {
  'ring_blue': 'AppIcon-RingBlue',
  'coins': 'AppIcon-Coins',
  'wallet': 'AppIcon-Wallet',
};

/// Ярлык -> ресурс иконки.
const _aliasIcons = {
  '.IconRing': '@mipmap/ic_launcher',
  '.IconRingBlue': '@mipmap/ic_launcher_ring_blue',
  '.IconCoins': '@mipmap/ic_launcher_coins',
  '.IconWallet': '@mipmap/ic_launcher_wallet',
};

void main() {
  final kotlin = File(
    'android/app/src/main/kotlin/com/tonyvinsenty/zuno/MainActivity.kt',
  ).readAsStringSync();
  final manifest = File('android/app/src/main/AndroidManifest.xml')
      .readAsStringSync();

  test('Dart: id вариантов совпадают с таблицей ADR 0014', () {
    expect(AppIconChoice.values.map((c) => c.id), _aliases.keys);
  });

  test('MainActivity.kt: канал, методы, ключ и все id с ярлыками', () {
    for (final needle in [
      '"$appIconChannelName"',
      '"$appIconCurrentMethod"',
      '"$appIconSetMethod"',
      '"$appIconSupportedMethod"',
      '"$appIconIdArg"',
      'appIconChannelName)',
      'DONT_KILL_APP',
      'appIconDefault = "${AppIconChoice.defaultChoice.id}"',
    ]) {
      expect(kotlin, contains(needle), reason: needle);
    }
    _aliases.forEach((id, alias) {
      expect(kotlin, contains('"$id" to "$alias"'), reason: id);
    });
  });

  test('MainActivity.kt: сначала включаем новый ярлык, потом выключаем', () {
    final enable = kotlin.indexOf('COMPONENT_ENABLED_STATE_ENABLED,');
    final disable = kotlin.indexOf('COMPONENT_ENABLED_STATE_DISABLED,');
    expect(enable, greaterThan(0));
    expect(disable, greaterThan(enable));
  });

  final aliasBlocks = RegExp(r'<activity-alias([\s\S]*?)</activity-alias>')
      .allMatches(manifest)
      .map((m) => m[1]!)
      .toList();

  String? attr(String block, String name) =>
      RegExp('android:$name="([^"]*)"').firstMatch(block)?[1];

  test('манифест: четыре ярлыка с иконками, включён только по умолчанию', () {
    expect(aliasBlocks.map((b) => attr(b, 'name')), _aliases.values);
    for (final block in aliasBlocks) {
      final name = attr(block, 'name')!;
      expect(attr(block, 'targetActivity'), '.MainActivity', reason: name);
      expect(attr(block, 'exported'), 'true', reason: name);
      expect(attr(block, 'icon'), _aliasIcons[name], reason: name);
      expect(
        attr(block, 'enabled'),
        name == _aliases[AppIconChoice.defaultChoice.id] ? 'true' : 'false',
        reason: name,
      );
      expect(block, contains('android.intent.category.LAUNCHER'));
      expect(block, contains('android.intent.action.MAIN'));
    }
  });

  // Шаг 8.38: iOS.
  final swift = File('ios/Runner/AppDelegate.swift').readAsStringSync();
  final pbxproj = File('ios/Runner.xcodeproj/project.pbxproj')
      .readAsStringSync();
  final workflow = File('.github/workflows/ios-build.yml').readAsStringSync();

  test('AppDelegate.swift: канал, методы, ключ и наборы для всех id', () {
    for (final needle in [
      '"$appIconChannelName"',
      '"$appIconCurrentMethod"',
      '"$appIconSetMethod"',
      '"$appIconSupportedMethod"',
      '"$appIconIdArg"',
      'appIconDefault = "${AppIconChoice.defaultChoice.id}"',
      'setAlternateIconName(name)',
      'alternateIconName',
      'supportsAlternateIcons',
    ]) {
      expect(swift, contains(needle), reason: needle);
    }
    _iosSets.forEach((id, set) {
      expect(swift, contains('"$id": "$set"'), reason: id);
    });
    final start = swift.indexOf('func didInitializeImplicitFlutterEngine');
    final end = swift.indexOf('\n  }\n', start);
    expect(
      swift.substring(start, end),
      contains('name: appIconChannelName'),
      reason: 'канал создаётся вместе с движком',
    );
  });

  test('project.pbxproj: три альтернативных набора в каждой конфигурации', () {
    final names = _iosSets.values.join(' ');
    final setting = 'ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES = "$names";';
    expect(
      setting.allMatches(pbxproj).length,
      'ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;'
          .allMatches(pbxproj)
          .length,
    );
    expect(setting.allMatches(pbxproj).length, 3);
    for (final set in _iosSets.values) {
      expect(
        File('ios/Runner/Assets.xcassets/$set.appiconset/Contents.json')
            .existsSync(),
        isTrue,
        reason: set,
      );
    }
  });

  test('ios-build.yml: сборка проверяет CFBundleAlternateIcons', () {
    expect(workflow, contains(':CFBundleIcons:CFBundleAlternateIcons:'));
    expect(workflow, contains('for ICON in ${_iosSets.values.join(' ')}; do'));
  });

  test('манифест: у MainActivity нет фильтра запуска, она осталась', () {
    final activity = RegExp(r'<activity\s[\s\S]*?</activity>')
        .firstMatch(manifest)![0]!;
    expect(activity, contains('android:name=".MainActivity"'));
    expect(activity, isNot(contains('LAUNCHER')));
    // LAUNCHER встречается только в ярлыках.
    expect(
      'android.intent.category.LAUNCHER'.allMatches(manifest).length,
      _aliases.length,
    );
  });
}
