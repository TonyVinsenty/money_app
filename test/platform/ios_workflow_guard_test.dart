// Сторож-тест для .github/workflows/ios-build.yml (ADR 0009). YAML-пакета
// нет, поэтому проверяем текст. Комментарии отбрасываем: правила касаются
// только настоящих строк конфигурации.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Проверяет текст workflow. Возвращает список ошибок; пустой — всё в порядке.
List<String> checkIosWorkflow(String source) {
  final errors = <String>[];
  final text = source
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('#'))
      .join('\n');

  // Единственный триггер — ручной запуск.
  if (!RegExp(
    r'^on:\s*\n\s+workflow_dispatch:',
    multiLine: true,
  ).hasMatch(text)) {
    errors.add('Нет триггера workflow_dispatch');
  }
  final forbiddenTrigger = RegExp(
    r'^\s*(push|pull_request|pull_request_target|schedule|workflow_run)\s*:',
    multiLine: true,
  );
  for (final m in forbiddenTrigger.allMatches(text)) {
    errors.add('Лишний триггер: ${m.group(1)}');
  }

  if (!text.contains('contents: read')) errors.add('Нет contents: read');
  if (RegExp(r':\s*write\b').hasMatch(text)) {
    errors.add('Есть право write');
  }
  if (text.contains('secrets.')) errors.add('Есть обращение к secrets.');

  final runsOn = RegExp(r'runs-on:\s*(\S+)').allMatches(text).toList();
  if (runsOn.isEmpty ||
      runsOn.any((m) => !RegExp(r'^macos-\d+$').hasMatch(m.group(1)!))) {
    errors.add('runs-on должен быть явной версией macos-NN');
  }

  for (final needle in const [
    '--no-codesign',
    '--branch 3.47.5',
    'PlistBuddy',
    'com.tonyvinsenty.zuno',
    'retention-days: 14',
  ]) {
    if (!text.contains(needle)) errors.add('Нет «$needle»');
  }

  for (final m in RegExp(r'uses:\s*(\S+)').allMatches(text)) {
    final action = m.group(1)!;
    if (!action.startsWith('actions/checkout@') &&
        !action.startsWith('actions/upload-artifact@')) {
      errors.add('Недопустимый action: $action');
    }
  }
  return errors;
}

void main() {
  final file = File('.github/workflows/ios-build.yml');

  test('ios-build.yml соответствует правилам', () {
    expect(checkIosWorkflow(file.readAsStringSync()), isEmpty);
  });

  test('в ios-build.yml нет табуляции', () {
    expect(file.readAsStringSync().contains('\t'), isFalse);
  });

  group('сам сторож распознаёт нарушения (синтетический текст)', () {
    const good = '''
name: iOS build
# push: в комментарии не считается, secrets.X тоже
on:
  workflow_dispatch:
permissions:
  contents: read
jobs:
  build:
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v7
      - run: git clone --depth 1 --branch 3.47.5 https://example.org/flutter.git
      - run: flutter build ios --release --no-codesign
      - run: /usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" x # com.tonyvinsenty.zuno
        # com.tonyvinsenty.zuno
      - uses: actions/upload-artifact@v7
        with:
          retention-days: 14
''';

    test('чистый текст проходит', () {
      expect(checkIosWorkflow(good), isEmpty);
    });

    test('добавленный push — ошибка', () {
      final bad = good.replaceFirst(
        'workflow_dispatch:',
        'workflow_dispatch:\n  push:',
      );
      expect(checkIosWorkflow(bad), isNotEmpty);
    });

    test('сторонний action — ошибка', () {
      final bad = good.replaceFirst(
        'actions/checkout@v7',
        'subosito/flutter-action@v2',
      );
      expect(checkIosWorkflow(bad), isNotEmpty);
    });

    test('macos-latest — ошибка', () {
      expect(
        checkIosWorkflow(good.replaceFirst('macos-26', 'macos-latest')),
        isNotEmpty,
      );
    });

    test('нет --no-codesign — ошибка', () {
      expect(
        checkIosWorkflow(good.replaceFirst('--no-codesign', '')),
        isNotEmpty,
      );
    });

    test('secrets.X — ошибка', () {
      final bad = good.replaceFirst(
        'jobs:',
        'env:\n  K: \${{ secrets.X }}\njobs:',
      );
      expect(checkIosWorkflow(bad), isNotEmpty);
    });

    test('contents: write — ошибка', () {
      expect(
        checkIosWorkflow(
          good.replaceFirst('contents: read', 'contents: write'),
        ),
        isNotEmpty,
      );
    });
  });
}
