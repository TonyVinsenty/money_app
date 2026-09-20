import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Папки `core`, которые по смыслу являются `domain`-кодом (шаг 1.6a).
const _guardedFolders = <String>[
  'lib/core/money',
  'lib/core/time',
  'lib/core/id',
];

/// Запрещённые фрагменты: шаблон и человеческое объяснение.
///
/// `\bdouble\b` ловит слово `double` целиком (тип, `double.parse`, слово в
/// комментарии), но не трогает части идентификаторов вроде `doubleValue`
/// или `redoubled`: они не являются типом `double`, а ложные срабатывания
/// делают сторож раздражающим.
final _rules = <({RegExp pattern, String reason})>[
  (
    pattern: RegExp('package:flutter/'),
    reason: 'импорт Flutter запрещён в core (ADR 0002)',
  ),
  (pattern: RegExp('dart:ui'), reason: 'dart:ui запрещён в core (ADR 0002)'),
  (
    pattern: RegExp('package:drift/'),
    reason: 'импорт drift запрещён в core (ADR 0002)',
  ),
  (
    pattern: RegExp('package:intl/'),
    reason: 'импорт intl запрещён в core: форматирование только в UI',
  ),
  (
    pattern: RegExp(r'\bdouble\b', caseSensitive: false),
    reason: 'слово double запрещено: деньги только целые (ADR 0004)',
  ),
];

/// Ищет нарушения в тексте файла. Возвращает по одной строке на нарушение
/// в формате `путь:номер_строки: причина`; пустой список — файл чистый.
List<String> findViolations(String source, {String path = '<source>'}) {
  final violations = <String>[];
  final lines = source.split('\n');
  for (var i = 0; i < lines.length; i++) {
    for (final rule in _rules) {
      if (rule.pattern.hasMatch(lines[i])) {
        violations.add('$path:${i + 1}: ${rule.reason}');
      }
    }
  }
  return violations;
}

/// Собирает нарушения по всем `.dart`-файлам папки (включая вложенные).
List<String> scanFolder(Directory folder) {
  final files =
      folder
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  final violations = <String>[];
  for (final file in files) {
    violations.addAll(
      findViolations(
        file.readAsStringSync(),
        path: file.path.replaceAll(r'\', '/'),
      ),
    );
  }
  return violations;
}

void main() {
  group('findViolations (проверка самого сторожа)', () {
    test('чистый код не даёт нарушений', () {
      const source = '''
import 'package:money_app/core/money/currency.dart';

/// Сумма в копейках.
final class Amount {
  const Amount(this.minorUnits);
  final int minorUnits;
}
''';
      expect(findViolations(source), isEmpty);
    });

    test('ловит импорт Flutter', () {
      final result = findViolations("import 'package:flutter/material.dart';");
      expect(result, hasLength(1));
      expect(result.single, contains('Flutter'));
    });

    test('ловит dart:ui', () {
      expect(findViolations("import 'dart:ui';"), hasLength(1));
    });

    test('ловит импорт drift', () {
      expect(
        findViolations("import 'package:drift/drift.dart';"),
        hasLength(1),
      );
    });

    test('ловит импорт intl', () {
      expect(findViolations("import 'package:intl/intl.dart';"), hasLength(1));
    });

    test('ловит тип double', () {
      expect(findViolations('final double price = 1;'), hasLength(1));
      expect(findViolations('final x = double.parse(s);'), hasLength(1));
    });

    test('ловит слово double внутри комментария', () {
      expect(findViolations('// не используем double для денег'), hasLength(1));
      expect(findViolations('/// Double тут нельзя.'), hasLength(1));
    });

    test('части идентификаторов (doubleValue, redoubled) не считаются', () {
      expect(findViolations('final doubleValue = 2;'), isEmpty);
      expect(findViolations('final redoubled = 2;'), isEmpty);
    });

    test('сообщение содержит путь и номер строки', () {
      const source = 'final a = 1;\n\nfinal double b = 2;\n';
      final result = findViolations(source, path: 'lib/core/money/x.dart');
      expect(result, hasLength(1));
      expect(result.single, startsWith('lib/core/money/x.dart:3:'));
    });

    test('несколько нарушений в одном файле находятся все', () {
      const source =
          "import 'dart:ui';\nimport 'package:flutter/widgets.dart';";
      final result = findViolations(source);
      expect(result, hasLength(2));
      expect(result[0], contains(':1:'));
      expect(result[1], contains(':2:'));
    });
  });

  group('сканирование реальных папок core', () {
    test('lib/core/money существует и содержит .dart файлы', () {
      final folder = Directory('lib/core/money');
      expect(
        folder.existsSync(),
        isTrue,
        reason:
            'Папка lib/core/money пропала или переименована — '
            'сторож остался бы пустым. Обновите _guardedFolders.',
      );
      final dartFiles = folder
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'));
      expect(dartFiles, isNotEmpty);
    });

    for (final path in _guardedFolders) {
      final folder = Directory(path);
      // Папки, которых ещё нет (time, id), пропускаем с пояснением: как
      // только шаги 1.8/1.10 создадут папку, тест начнёт работать сам.
      final skipReason = folder.existsSync()
          ? null
          : 'папки $path ещё нет, появится на следующих шагах';
      test('$path не содержит запрещённого', () {
        expect(scanFolder(folder), isEmpty);
      }, skip: skipReason);
    }
  });
}
