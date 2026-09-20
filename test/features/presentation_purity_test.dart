import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'domain_purity_test.dart' show dartFilesIn;

/// Директива `import`/`export`: слово, кавычка, путь до закрывающей кавычки.
/// Строки-комментарии сюда не попадают: они начинаются с `//`.
final _directive = RegExp(r'''^\s*(?:import|export)\s+['"]([^'"]*)['"]''');

/// Файл слоя `presentation`: `lib/features/<фича>/presentation/...`.
final _presentationPath = RegExp(r'^lib/features/([^/]+)/presentation/');

/// Путь внутри `lib/features/<фича>/<слой>/...`.
final _featureLayer = RegExp(r'^lib/features/([^/]+)/([^/]+)/');

/// Префиксы пакетов, которые `presentation` не должен знать (ADR 0002):
/// с базой экраны работают только через репозиторные интерфейсы из `domain`.
const _forbiddenPackages = <({String prefix, String reason})>[
  (
    prefix: 'package:drift/',
    reason:
        'импорт drift запрещён в presentation: с базой работает только data',
  ),
  (
    prefix: 'package:sqlite3/',
    reason:
        'импорт sqlite3 запрещён в presentation: с базой работает только data',
  ),
];

/// Ищет нарушения границ слоя `presentation` в тексте файла [path]
/// (`lib/features/<фича>/presentation/...`). Возвращает по одной строке
/// `путь:номер_строки: причина` на нарушение; пустой список — чисто.
///
/// Запрещено: `drift`, `sqlite3`, `core/database/`, `data` любой фичи,
/// `presentation` ЧУЖОЙ фичи и `lib/app` (фичи не знают о приложении).
/// Разрешено: свои `domain` и `presentation`, `domain` чужой фичи, `core/`
/// (кроме `core/database/`), Flutter и SDK. Относительные пути
/// разворачиваются от [path], поэтому `../../x/data/y.dart` тоже ловится.
List<String> findPresentationViolations(String source, {required String path}) {
  final own = _presentationPath.firstMatch(path);
  if (own == null) {
    throw ArgumentError.value(
      path,
      'path',
      'expected lib/features/<feature>/presentation/...',
    );
  }
  final feature = own.group(1)!;
  final violations = <String>[];
  final lines = source.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final match = _directive.firstMatch(lines[i]);
    if (match == null) continue;
    final uri = match.group(1)!;
    final where = '$path:${i + 1}';

    for (final rule in _forbiddenPackages) {
      if (uri.startsWith(rule.prefix)) {
        violations.add('$where: ${rule.reason}');
      }
    }

    final libPath = _libPathOf(uri, path);
    if (libPath == null) continue;
    if (libPath == 'lib/app' || libPath.startsWith('lib/app/')) {
      violations.add(
        '$where: presentation не может импортировать lib/app: фичи не знают '
        'о приложении ($uri)',
      );
    }
    if (libPath.startsWith('lib/core/database/')) {
      violations.add(
        '$where: presentation не может импортировать core/database ($uri, '
        'ADR 0002)',
      );
    }
    final layer = _featureLayer.firstMatch(libPath);
    if (layer != null) {
      final owner = layer.group(1)!;
      final name = layer.group(2)!;
      if (name == 'data') {
        violations.add(
          '$where: presentation не может импортировать data ($uri, ADR 0002)',
        );
      } else if (name == 'presentation' && owner != feature) {
        violations.add(
          '$where: presentation не может импортировать presentation чужой '
          'фичи "$owner" ($uri, ADR 0002)',
        );
      }
    }
  }
  return violations;
}

/// Путь импорта [uri] относительно корня проекта (`lib/...`) или `null`, если
/// это `dart:` или чужой пакет (их проверяют по префиксу).
String? _libPathOf(String uri, String fromPath) {
  const ownPackage = 'package:money_app/';
  if (uri.startsWith(ownPackage)) {
    return 'lib/${uri.substring(ownPackage.length)}';
  }
  if (uri.contains(':')) return null;
  // Относительный путь: разворачиваем от папки файла.
  final resolved = Uri.parse('/$fromPath').resolve(uri).path;
  return resolved.startsWith('/') ? resolved.substring(1) : resolved;
}

/// Все папки `presentation` внутри `lib/features/*/`.
List<Directory> presentationFolders(Directory features) {
  if (!features.existsSync()) return const [];
  return features
      .listSync()
      .whereType<Directory>()
      .map((feature) => Directory('${feature.path}/presentation'))
      .where((folder) => folder.existsSync())
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}

void main() {
  const home = 'lib/features/categories/presentation/screen.dart';

  group('findPresentationViolations (проверка самого сторожа)', () {
    test(
      'чистый код проходит: свой domain, чужой domain, core/ui, Flutter',
      () {
        const source = '''
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:money_app/core/ui/theme/app_colors.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/categories/presentation/widgets/tile.dart';
import 'widgets/tile.dart';
import '../domain/category.dart';

// import 'package:drift/drift.dart'; (комментарий не считается)
/// Экран.
final class Screen {}
''';
        expect(findPresentationViolations(source, path: home), isEmpty);
      },
    );

    test('ловит drift и sqlite3', () {
      const forbidden = [
        "import 'package:drift/drift.dart';",
        "import 'package:drift/native.dart';",
        "import 'package:sqlite3/sqlite3.dart';",
        "export 'package:drift/drift.dart';",
        '  import "package:drift/drift.dart";',
      ];
      for (final line in forbidden) {
        expect(
          findPresentationViolations(line, path: home),
          hasLength(1),
          reason: line,
        );
      }
    });

    test('ловит core/database', () {
      const forbidden = [
        "import 'package:money_app/core/database/app_database.dart';",
        "import 'package:money_app/core/database/tables/categories.dart';",
        "import '../../../core/database/app_database.dart';",
      ];
      for (final line in forbidden) {
        final result = findPresentationViolations(line, path: home);
        expect(result, hasLength(1), reason: line);
        expect(result.single, contains('core/database'));
      }
    });

    test('ловит data своей и любой чужой фичи', () {
      const forbidden = [
        "import 'package:money_app/features/categories/data/repo.dart';",
        "import 'package:money_app/features/transactions/data/repo.dart';",
        "import '../data/repo.dart';",
        "import '../../transactions/data/repo.dart';",
        "export 'package:money_app/features/settings/data/x.dart';",
      ];
      for (final line in forbidden) {
        final result = findPresentationViolations(line, path: home);
        expect(result, hasLength(1), reason: line);
        expect(result.single, contains('data'));
      }
    });

    test('ловит presentation чужой фичи, но не своей', () {
      const forbidden = [
        "import 'package:money_app/features/transactions/presentation/x.dart';",
        "import '../../transactions/presentation/x.dart';",
        "export 'package:money_app/features/settings/presentation/x.dart';",
      ];
      for (final line in forbidden) {
        final result = findPresentationViolations(line, path: home);
        expect(result, hasLength(1), reason: line);
        expect(result.single, contains('чужой'));
      }
      const allowed = [
        "import 'package:money_app/features/categories/presentation/x.dart';",
        "import '../presentation/x.dart';",
        "import 'x.dart';",
      ];
      for (final line in allowed) {
        expect(
          findPresentationViolations(line, path: home),
          isEmpty,
          reason: line,
        );
      }
    });

    test('ловит lib/app', () {
      const forbidden = [
        "import 'package:money_app/app/app_scope.dart';",
        "import 'package:money_app/app/money_app.dart';",
        "import '../../../app/app_scope.dart';",
        "export 'package:money_app/app/app_services.dart';",
      ];
      for (final line in forbidden) {
        final result = findPresentationViolations(line, path: home);
        expect(result, hasLength(1), reason: line);
        expect(result.single, contains('lib/app'));
      }
    });

    test('чужой domain и core/ui разрешены', () {
      const allowed = [
        "import 'package:money_app/features/transactions/domain/t.dart';",
        "import 'package:money_app/core/ui/amount_failure_text.dart';",
        "import 'package:money_app/core/errors/data_corrupted_exception.dart';",
        "import 'package:money_app/core/format/money_format.dart';",
        "import 'package:flutter/widgets.dart';",
        "import 'package:flutter_test/flutter_test.dart';",
      ];
      for (final line in allowed) {
        expect(
          findPresentationViolations(line, path: home),
          isEmpty,
          reason: line,
        );
      }
    });

    test('сообщение: путь, номер строки и причина', () {
      const source =
          "final a = 1;\n\nimport 'package:drift/drift.dart';\n"
          "import 'package:money_app/features/transactions/presentation/x.dart';";
      final result = findPresentationViolations(source, path: home);

      expect(result, hasLength(2));
      expect(result[0], startsWith('$home:3: '));
      expect(result[0], contains('drift'));
      expect(result[1], startsWith('$home:4: '));
    });

    test('несколько нарушений на разных строках находятся все', () {
      const source =
          "import 'package:drift/drift.dart';\n"
          "import 'package:money_app/core/database/app_database.dart';\n"
          "import '../data/a.dart';\n"
          "import 'package:money_app/app/app_scope.dart';";
      final result = findPresentationViolations(source, path: home);

      expect(result, hasLength(4));
      for (var i = 0; i < 4; i++) {
        expect(result[i], contains(':${i + 1}:'));
      }
    });

    test('чужая фича определяется по пути файла', () {
      const line =
          "import 'package:money_app/features/settings/presentation/x.dart';";

      expect(
        findPresentationViolations(
          line,
          path: 'lib/features/settings/presentation/a.dart',
        ),
        isEmpty,
      );
      expect(findPresentationViolations(line, path: home), hasLength(1));
    });

    test('путь вне presentation — ошибка вызова сторожа', () {
      expect(
        () => findPresentationViolations(
          '',
          path: 'lib/features/categories/domain/a.dart',
        ),
        throwsArgumentError,
      );
    });
  });

  group('сканирование реальных папок presentation', () {
    final folders = presentationFolders(Directory('lib/features'));

    test(
      'в каждой найденной папке есть файлы',
      () {
        for (final folder in folders) {
          expect(
            dartFilesIn(folder),
            isNotEmpty,
            reason: 'В ${folder.path} нет ни одного .dart файла.',
          );
        }
      },
      skip: folders.isEmpty
          ? 'папок lib/features/*/presentation пока нет: проверять нечего'
          : false,
    );

    test(
      'в presentation нет запрещённых импортов',
      () {
        final violations = <String>[];
        for (final folder in folders) {
          for (final file in dartFilesIn(folder)) {
            violations.addAll(
              findPresentationViolations(
                file.readAsStringSync(),
                path: file.path.replaceAll(r'\', '/'),
              ),
            );
          }
        }
        expect(violations, isEmpty, reason: violations.join('\n'));
      },
      skip: folders.isEmpty
          ? 'папок lib/features/*/presentation пока нет: проверять нечего'
          : false,
    );
  });
}
