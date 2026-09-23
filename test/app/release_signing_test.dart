// Сторож-тест для подписи релизной сборки Android (ADR 0005,
// docs/decisions/0005-android-release-signing.md). Он не собирает APK — это
// текстовый анализ android/app/build.gradle.kts и обход файлов репозитория,
// как в test/app/orientation_lock_test.dart.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Возвращает true, если в тексте build.gradle.kts релизная сборка снова
/// подписывается отладочным ключом (`signingConfigs.getByName("debug")`).
/// Это ровно та строка из шаблона `flutter create`, которую нельзя допускать
/// обратно: отладочный ключ разный на каждой машине, и Google Play такие APK
/// не принимает (ADR 0005, раздел 5).
bool _fallsBackToDebugSigning(String gradleSource) {
  return gradleSource.contains('signingConfigs.getByName("debug")');
}

/// Возвращает true, если в тексте build.gradle.kts пароль подписи задан
/// литеральной строкой (`storePassword = "..."` / `keyPassword = "..."`)
/// вместо чтения из properties-файла (`properties.getProperty(...)`).
bool _hasHardcodedPassword(String gradleSource) {
  final hardcodedPassword = RegExp(r'(storePassword|keyPassword)\s*=\s*"');
  return hardcodedPassword.hasMatch(gradleSource);
}

/// Имена файлов, которые не должны попадать в репозиторий (сам ключ подписи
/// и файлы с паролями к нему) — по правилу CLAUDE.md, раздел «Соглашения».
bool _isSecretFileName(String fileName) {
  final lower = fileName.toLowerCase();
  return lower.endsWith('.jks') ||
      lower.endsWith('.keystore') ||
      lower.endsWith('.p12') ||
      lower == 'key.properties' ||
      lower.endsWith('keystore.properties');
}

/// Каталоги, которые не нужно обходить: служебные/сгенерированные, не часть
/// исходников репозитория, и способные сильно замедлить обход.
const _excludedDirNames = {'.git', '.dart_tool', 'build', '.gradle', '.idea'};

/// Рекурсивно собирает пути файлов с "секретными" именами внутри [root],
/// пропуская служебные каталоги из [_excludedDirNames].
List<String> _findSecretFiles(Directory root) {
  final found = <String>[];

  void walk(Directory dir) {
    for (final entity in dir.listSync(followLinks: false)) {
      final name = entity.path.replaceAll('\\', '/').split('/').last;
      if (entity is Directory) {
        if (_excludedDirNames.contains(name)) continue;
        // android/.gradle и android/app/.cxx и подобные — тоже служебные,
        // но их имена уже покрыты списком выше (.gradle) или они лежат
        // внутри build/. На всякий случай пропускаем ещё и `.cxx`.
        if (name == '.cxx') continue;
        walk(entity);
      } else if (entity is File) {
        if (_isSecretFileName(name)) {
          found.add(entity.path);
        }
      }
    }
  }

  walk(root);
  return found;
}

void main() {
  final gradleFile = File('android/app/build.gradle.kts');
  final gradleSource = gradleFile.readAsStringSync();

  test('release-сборка не подписывается отладочным ключом (signingConfigs.getByName("debug"))', () {
    expect(_fallsBackToDebugSigning(gradleSource), isFalse);
  });

  test('в build.gradle.kts нет захардкоженных паролей ключа подписи', () {
    expect(_hasHardcodedPassword(gradleSource), isFalse);
  });

  test('build.gradle.kts читает путь к properties-файлу из переменной окружения ZUNO_KEYSTORE_PROPERTIES', () {
    expect(gradleSource, contains('System.getenv("ZUNO_KEYSTORE_PROPERTIES")'));
  });

  test('в рабочем дереве репозитория нет файлов ключа подписи или паролей к нему', () {
    final secretFiles = _findSecretFiles(Directory.current);
    expect(
      secretFiles,
      isEmpty,
      reason:
          'Ключ подписи и пароли должны храниться вне репозитория (ADR 0005): $secretFiles',
    );
  });

  group(
    'сам сторож распознаёт нарушения (проверка на синтетическом тексте)',
    () {
      test('находит откат на отладочную подпись', () {
        const malicious = '''
        buildTypes {
            release {
                signingConfig = signingConfigs.getByName("debug")
            }
        }
      ''';
        expect(_fallsBackToDebugSigning(malicious), isTrue);
      });

      test('находит захардкоженный пароль', () {
        const malicious = '''
        signingConfigs {
            create("release") {
                storePassword = "hunter2"
                keyPassword = "hunter2"
            }
        }
      ''';
        expect(_hasHardcodedPassword(malicious), isTrue);
      });

      test('не находит пароль там, где он читается из properties-файла', () {
        const clean = '''
        signingConfigs {
            create("release") {
                storePassword = zunoKeystoreProperties.getProperty("storePassword")
            }
        }
      ''';
        expect(_hasHardcodedPassword(clean), isFalse);
      });
    },
  );
}
