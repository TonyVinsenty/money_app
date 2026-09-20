import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Запрещённые в `domain` префиксы импортов и объяснение (ADR 0002).
const _forbiddenPrefixes = <({String prefix, String reason})>[
  (
    prefix: 'package:flutter/',
    reason: 'импорт Flutter запрещён в domain (ADR 0002)',
  ),
  (prefix: 'dart:ui', reason: 'dart:ui запрещён в domain (ADR 0002)'),
  (
    prefix: 'package:drift/',
    reason: 'импорт drift запрещён в domain (ADR 0002)',
  ),
  (
    prefix: 'package:intl/',
    reason: 'импорт intl запрещён в domain: форматирование только в UI',
  ),
  (
    prefix: 'package:path_provider/',
    reason: 'импорт path_provider запрещён в domain: это работа с файлами',
  ),
  (
    prefix: 'package:sqlite3/',
    reason: 'импорт sqlite3 запрещён в domain: это хранилище',
  ),
];

/// Директива `import`/`export`: слово, кавычка, путь до закрывающей кавычки.
/// Строки-комментарии сюда не попадают: они начинаются с `//`.
final _directive = RegExp(r'''^\s*(?:import|export)\s+['"]([^'"]*)['"]''');

/// Ищет нарушения чистоты `domain` в тексте файла. Возвращает по одной
/// строке `путь:номер_строки: причина` на нарушение; пустой список — чисто.
List<String> findDomainViolations(String source, {String path = '<source>'}) {
  final violations = <String>[];
  final lines = source.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final match = _directive.firstMatch(lines[i]);
    if (match == null) continue;
    final uri = match.group(1)!;
    final where = '$path:${i + 1}';

    for (final rule in _forbiddenPrefixes) {
      if (uri.startsWith(rule.prefix)) {
        violations.add('$where: ${rule.reason}');
      }
    }
    if (_pointsInto(uri, 'data')) {
      violations.add(
        '$where: domain не может импортировать data ($uri, ADR 0002)',
      );
    }
    if (_pointsInto(uri, 'presentation')) {
      violations.add(
        '$where: domain не может импортировать presentation ($uri, ADR 0002)',
      );
    }
  }
  return violations;
}

/// Проходит ли путь [uri] через папку с именем [folder] (`/data/`, ...).
bool _pointsInto(String uri, String folder) {
  return uri.contains('/$folder/') || uri.startsWith('$folder/');
}

/// Все папки `domain` внутри `lib/features/*/`.
List<Directory> domainFolders(Directory features) {
  if (!features.existsSync()) return const [];
  return features
      .listSync()
      .whereType<Directory>()
      .map((feature) => Directory('${feature.path}/domain'))
      .where((domain) => domain.existsSync())
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}

/// Все `.dart`-файлы папки (включая вложенные), по алфавиту.
List<File> dartFilesIn(Directory folder) {
  return folder
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}

void main() {
  group('findDomainViolations (проверка самого сторожа)', () {
    test('чистый код проходит', () {
      const source = '''
import 'dart:async';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/features/categories/domain/category.dart';

// import 'package:flutter/material.dart'; (комментарий не считается)
/// Сущность.
final class Thing {}
''';
      expect(findDomainViolations(source), isEmpty);
    });

    test('ловит каждый запрещённый пакет', () {
      const forbidden = [
        "import 'package:flutter/material.dart';",
        "import 'dart:ui';",
        "import 'dart:ui' as ui;",
        "import 'package:drift/drift.dart';",
        "import 'package:intl/intl.dart';",
        "import 'package:path_provider/path_provider.dart';",
        "import 'package:sqlite3/sqlite3.dart';",
        "export 'package:flutter/widgets.dart';",
        '  import "package:drift/native.dart";',
      ];
      for (final line in forbidden) {
        expect(findDomainViolations(line), hasLength(1), reason: line);
      }
    });

    test('ловит импорт из data и presentation любой фичи', () {
      const forbidden = [
        "import 'package:money_app/features/categories/data/repo.dart';",
        "import 'package:money_app/features/transactions/presentation/x.dart';",
        "import '../data/repo.dart';",
        "import 'data/repo.dart';",
        "export '../../presentation/screen.dart';",
      ];
      for (final line in forbidden) {
        expect(findDomainViolations(line), hasLength(1), reason: line);
      }
    });

    test('чужой domain и core разрешены', () {
      const allowed = [
        "import 'package:money_app/features/transactions/domain/t.dart';",
        "import 'package:money_app/core/database/converters/x.dart';",
        "import 'package:money_app/core/errors/data_corrupted_exception.dart';",
      ];
      for (final line in allowed) {
        expect(findDomainViolations(line), isEmpty, reason: line);
      }
    });

    test('сообщение: путь, номер строки и причина', () {
      const source =
          "final a = 1;\n\nimport 'package:flutter/material.dart';\n";
      final result = findDomainViolations(
        source,
        path: 'lib/features/x/domain/a.dart',
      );
      expect(result, hasLength(1));
      expect(result.single, startsWith('lib/features/x/domain/a.dart:3: '));
      expect(result.single, contains('Flutter'));
    });

    test('несколько нарушений находятся все', () {
      const source =
          "import 'dart:ui';\nimport 'package:drift/drift.dart';\n"
          "import '../data/a.dart';";
      final result = findDomainViolations(source);
      expect(result, hasLength(3));
      expect(result[0], contains(':1:'));
      expect(result[1], contains(':2:'));
      expect(result[2], contains(':3:'));
    });
  });

  group('сканирование реальных папок domain', () {
    final folders = domainFolders(Directory('lib/features'));

    test('найдена хотя бы одна папка domain, и в каждой есть файлы', () {
      expect(
        folders,
        isNotEmpty,
        reason:
            'Не найдено ни одной lib/features/*/domain: сторож был бы '
            'пустым. Возможно, структура папок изменилась.',
      );
      for (final folder in folders) {
        expect(
          dartFilesIn(folder),
          isNotEmpty,
          reason: 'В ${folder.path} нет ни одного .dart файла.',
        );
      }
    });

    test('в domain нет запрещённых импортов', () {
      final violations = <String>[];
      for (final folder in folders) {
        for (final file in dartFilesIn(folder)) {
          violations.addAll(
            findDomainViolations(
              file.readAsStringSync(),
              path: file.path.replaceAll(r'\', '/'),
            ),
          );
        }
      }
      expect(violations, isEmpty, reason: violations.join('\n'));
    });
  });
}
