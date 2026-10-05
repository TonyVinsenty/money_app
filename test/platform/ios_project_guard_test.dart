// Сторож-тест iOS-проекта (мини-этап «iPhone», ADR 0009). Файлы iOS мы на
// Windows не собираем, поэтому проверяем текстом: идентификатор приложения,
// имя, ориентации и язык. Образец — test/app/release_signing_test.dart.
// Функции проверки чистые (принимают текст), чтобы проверить и сам сторож.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _bundleId = 'com.tonyvinsenty.zuno';

/// Проверяет project.pbxproj. Конфигурации цели Runner отличаем от
/// RunnerTests по строке `INFOPLIST_FILE = Runner/Info.plist;` (у тестовой
/// цели её нет: там TEST_HOST/BUNDLE_LOADER). Таких конфигураций должно быть
/// ровно 3 (Debug, Release, Profile), и в каждой bundle id точно [_bundleId].
/// Возвращает список ошибок; пустой список — всё в порядке.
List<String> checkPbxproj(String pbxproj) {
  final errors = <String>[];
  final chunks = pbxproj.split('isa = XCBuildConfiguration;').skip(1);
  final runnerConfigs = chunks
      .where((c) => c.contains('INFOPLIST_FILE = Runner/Info.plist;'))
      .toList();
  if (runnerConfigs.length != 3) {
    errors.add(
      'Ожидалось 3 конфигурации Runner, найдено ${runnerConfigs.length}',
    );
  }
  final idPattern = RegExp(r'PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);');
  for (final config in runnerConfigs) {
    final ids = idPattern.allMatches(config).map((m) => m.group(1)).toList();
    if (ids.length != 1 || ids.single != _bundleId) {
      errors.add('Неверный bundle id в конфигурации Runner: $ids');
    }
  }
  return errors;
}

/// Значение ключа plist: строка (`<string>`) или список строк (`<array>`).
/// Простой разбор по тексту: ищем `<key>X</key>` и следующий за ним элемент.
Object? plistValue(String plist, String key) {
  final match = RegExp(
    '<key>${RegExp.escape(key)}</key>\\s*'
    '(?:<string>([^<]*)</string>|<array>(.*?)</array>)',
    dotAll: true,
  ).firstMatch(plist);
  if (match == null) return null;
  if (match.group(1) != null) return match.group(1);
  return RegExp(r'<string>([^<]*)</string>')
      .allMatches(match.group(2)!)
      .map((m) => m.group(1)!)
      .toList();
}

/// Проверяет Info.plist. Возвращает список ошибок; пустой — всё в порядке.
List<String> checkInfoPlist(String plist) {
  final errors = <String>[];
  void expectValue(String key, Object expected) {
    final actual = plistValue(plist, key);
    final same = actual is List && expected is List
        ? actual.join('|') == expected.join('|')
        : actual == expected;
    if (!same) errors.add('$key: ожидалось $expected, найдено $actual');
  }

  expectValue('CFBundleIdentifier', r'$(PRODUCT_BUNDLE_IDENTIFIER)');
  expectValue('CFBundleDisplayName', 'Zuno');
  expectValue('CFBundleName', 'Zuno');
  const portrait = ['UIInterfaceOrientationPortrait'];
  expectValue('UISupportedInterfaceOrientations', portrait);
  expectValue('UISupportedInterfaceOrientations~ipad', portrait);
  final localizations = plistValue(plist, 'CFBundleLocalizations');
  if (localizations is! List || !localizations.contains('ru')) {
    errors.add('CFBundleLocalizations должен содержать ru');
  }
  return errors;
}

void main() {
  final pbxproj = File('ios/Runner.xcodeproj/project.pbxproj');
  final plist = File('ios/Runner/Info.plist');

  test('project.pbxproj: bundle id Runner во всех трёх конфигурациях', () {
    expect(checkPbxproj(pbxproj.readAsStringSync()), isEmpty);
  });

  test('Info.plist: идентификатор, имя, ориентации и язык', () {
    expect(checkInfoPlist(plist.readAsStringSync()), isEmpty);
  });

  group('сам сторож распознаёт нарушения (синтетический текст)', () {
    String config(String name, String id, {bool runner = true}) =>
        '''
		ABC /* $name */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				${runner ? 'INFOPLIST_FILE = Runner/Info.plist;' : 'TEST_HOST = x;'}
				PRODUCT_BUNDLE_IDENTIFIER = $id;
			};
		};
''';

    String pbx({String debugId = _bundleId, bool withProfile = true}) =>
        config('Debug', debugId) +
        config('Release', _bundleId) +
        (withProfile ? config('Profile', _bundleId) : '') +
        config('Debug', '$_bundleId.RunnerTests', runner: false);

    test('чистый текст проходит, RunnerTests не мешает', () {
      expect(checkPbxproj(pbx()), isEmpty);
    });

    test('другой bundle id в одной конфигурации — ошибка', () {
      expect(checkPbxproj(pbx(debugId: 'com.example.app')), isNotEmpty);
    });

    test('пропала конфигурация — ошибка', () {
      expect(checkPbxproj(pbx(withProfile: false)), isNotEmpty);
    });

    const goodPlist = '''
<dict>
	<key>CFBundleDisplayName</key>
	<string>Zuno</string>
	<key>CFBundleIdentifier</key>
	<string>\$(PRODUCT_BUNDLE_IDENTIFIER)</string>
	<key>CFBundleLocalizations</key>
	<array>
		<string>ru</string>
	</array>
	<key>CFBundleName</key>
	<string>Zuno</string>
	<key>UISupportedInterfaceOrientations</key>
	<array>
		<string>UIInterfaceOrientationPortrait</string>
	</array>
	<key>UISupportedInterfaceOrientations~ipad</key>
	<array>
		<string>UIInterfaceOrientationPortrait</string>
	</array>
</dict>
''';

    test('чистый plist проходит', () {
      expect(checkInfoPlist(goodPlist), isEmpty);
    });

    test('добавлена другая ориентация — ошибка', () {
      final bad = goodPlist.replaceFirst(
        '<string>UIInterfaceOrientationPortrait</string>',
        '<string>UIInterfaceOrientationPortrait</string>\n'
            '<string>UIInterfaceOrientationLandscapeLeft</string>',
      );
      expect(checkInfoPlist(bad), isNotEmpty);
    });

    test('нет ru — ошибка', () {
      final bad = goodPlist.replaceFirst('<string>ru</string>', '');
      expect(checkInfoPlist(bad), isNotEmpty);
    });

    test('другое имя — ошибка', () {
      final bad = goodPlist.replaceFirst(
        '<string>Zuno</string>',
        '<string>Other</string>',
      );
      expect(checkInfoPlist(bad), isNotEmpty);
    });

    test('другой CFBundleIdentifier — ошибка', () {
      final bad = goodPlist.replaceFirst(
        r'$(PRODUCT_BUNDLE_IDENTIFIER)',
        'com.example.app',
      );
      expect(checkInfoPlist(bad), isNotEmpty);
    });
  });
}
