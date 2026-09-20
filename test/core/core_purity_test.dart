import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Папки `core`, которые по смыслу являются `domain`-кодом (шаг 1.6a).
const _guardedFolders = <String>[
  'lib/core/money',
  'lib/core/time',
  'lib/core/id',
];

/// Единственная папка, где разрешён пакет `uuid` (генератор идентификаторов).
const _uuidFolder = 'lib/core/id/';

/// Префиксы `package:`-импортов, разрешённых во всех охраняемых папках.
const _allowedPackagePrefixes = <String>[
  'package:money_app/core/money/',
  'package:money_app/core/time/',
  'package:money_app/core/id/',
];

/// Запрещённые фрагменты в импортах: шаблон и человеческое объяснение.
///
/// Действуют на любую строку файла (в том числе на комментарий), как и было
/// раньше. Это «чёрный список»: он даёт понятное сообщение для самых важных
/// случаев, а всё остальное отсекает белый список ниже.
final _importRules = <({RegExp pattern, String reason})>[
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
];

/// Слово `double` запрещено везде, включая комментарии.
///
/// `\bdouble\b` ловит слово целиком (тип, `double.parse`, слово в
/// комментарии), но не трогает части идентификаторов вроде `doubleValue`
/// или `redoubled`: они не являются типом `double`, а ложные срабатывания
/// делают сторож раздражающим.
final _doubleRule = (
  pattern: RegExp(r'\bdouble\b', caseSensitive: false),
  reason: 'слово double запрещено: деньги только целые (ADR 0004)',
);

/// Директива `import`/`export`: слово, кавычка, путь до закрывающей кавычки.
final _directive = RegExp(r'''^\s*(?:import|export)\s+['"]([^'"]*)['"]''');

/// Разрешён ли путь [uri] из директивы `import`/`export` внутри core.
///
/// [allowUuid] включает `package:uuid/` (только для `lib/core/id`).
bool isImportAllowed(String uri, {bool allowUuid = false}) {
  if (uri.startsWith('dart:')) return !uri.startsWith('dart:ui');
  if (_allowedPackagePrefixes.any(uri.startsWith)) return true;
  return allowUuid && uri.startsWith('package:uuid/');
}

/// Ищет нарушения в тексте файла. Возвращает по одной строке на нарушение
/// в формате `путь:номер_строки: причина`; пустой список — файл чистый.
///
/// Путь [path] нужен для сообщений и чтобы понять, лежит ли файл в
/// `lib/core/id` (там разрешён `package:uuid/`).
List<String> findViolations(String source, {String path = '<source>'}) {
  final allowUuid = path.replaceAll(r'\', '/').contains(_uuidFolder);
  final violations = <String>[];
  final lines = source.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final where = '$path:${i + 1}';

    var importRuleHit = false;
    for (final rule in _importRules) {
      if (rule.pattern.hasMatch(line)) {
        violations.add('$where: ${rule.reason}');
        importRuleHit = true;
      }
    }

    // Строки-комментарии для белого списка игнорируем, а слово double
    // ищем везде.
    if (!importRuleHit && !line.trimLeft().startsWith('//')) {
      final match = _directive.firstMatch(line);
      if (match != null) {
        final uri = match.group(1)!;
        if (!isImportAllowed(uri, allowUuid: allowUuid)) {
          violations.add(
            '$where: импорт $uri не разрешён в core (белый список)',
          );
        }
      }
    }

    if (_doubleRule.pattern.hasMatch(line)) {
      violations.add('$where: ${_doubleRule.reason}');
    }
  }
  return violations;
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

/// Собирает нарушения по всем `.dart`-файлам папки (включая вложенные).
List<String> scanFolder(Directory folder) {
  final violations = <String>[];
  for (final file in dartFilesIn(folder)) {
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

  group('белый список импортов', () {
    test('разрешённые импорты проходят', () {
      const allowed = [
        "import 'dart:core';",
        "import 'dart:math';",
        "import 'dart:convert';",
        "import 'package:money_app/core/money/money.dart';",
        "import 'package:money_app/core/time/date_only.dart';",
        "import 'package:money_app/core/id/id_generator.dart';",
        "export 'package:money_app/core/money/currency.dart';",
        '  import "dart:math";',
        "import 'dart:math' show max;",
      ];
      for (final line in allowed) {
        expect(
          findViolations(line, path: 'lib/core/time/x.dart'),
          isEmpty,
          reason: line,
        );
      }
    });

    test('запрещённые импорты ловятся', () {
      const forbidden = [
        "import 'package:money_app/core/format/money_format.dart';",
        "import 'package:money_app/core/ui/theme/app_theme.dart';",
        "import 'package:money_app/features/expenses/domain/expense.dart';",
        "import 'package:flutter/material.dart';",
        "import 'package:intl/intl.dart';",
        "import 'dart:ui';",
        "import 'x.dart';",
        "import '../money/money.dart';",
        "import 'package:collection/collection.dart';",
        "export 'x.dart';",
        "export 'package:money_app/core/format/date_format.dart';",
      ];
      for (final line in forbidden) {
        expect(
          findViolations(line, path: 'lib/core/money/x.dart'),
          isNotEmpty,
          reason: line,
        );
      }
    });

    test('сообщение называет импорт и белый список', () {
      final result = findViolations(
        "import 'x.dart';",
        path: 'lib/core/money/a.dart',
      );
      expect(result, [
        'lib/core/money/a.dart:1: импорт x.dart не разрешён в core '
            '(белый список)',
      ]);
    });

    test('чужой пакет не разрешён, и в сообщении есть его путь', () {
      final result = findViolations(
        "import 'package:collection/collection.dart';",
        path: 'lib/core/time/a.dart',
      );
      expect(result.single, contains('package:collection/collection.dart'));
    });

    test('package:uuid/ разрешён только в lib/core/id', () {
      const line = "import 'package:uuid/uuid.dart';";
      expect(findViolations(line, path: 'lib/core/id/a.dart'), isEmpty);
      expect(findViolations(line, path: 'lib/core/id/sub/a.dart'), isEmpty);
      expect(findViolations(line, path: 'lib/core/money/a.dart'), isNotEmpty);
      expect(findViolations(line, path: 'lib/core/time/a.dart'), isNotEmpty);
      expect(findViolations(line), isNotEmpty);
    });

    test('строка-комментарий с импортом для белого списка игнорируется', () {
      expect(findViolations("// import 'x.dart';"), isEmpty);
      expect(findViolations("  /// import 'x.dart';"), isEmpty);
    });

    test('слово double в комментарии ловится по-прежнему', () {
      expect(findViolations('// import double;'), hasLength(1));
    });

    test('isImportAllowed: dart:ui не разрешён, остальные dart: разрешены', () {
      expect(isImportAllowed('dart:ui'), isFalse);
      expect(isImportAllowed('dart:math'), isTrue);
      expect(isImportAllowed('dart:core'), isTrue);
    });

    test('isImportAllowed: uuid только при allowUuid', () {
      expect(isImportAllowed('package:uuid/uuid.dart'), isFalse);
      expect(
        isImportAllowed('package:uuid/uuid.dart', allowUuid: true),
        isTrue,
      );
    });
  });

  group('сканирование реальных папок core', () {
    for (final path in _guardedFolders) {
      test('$path существует и содержит .dart файлы', () {
        final folder = Directory(path);
        expect(
          folder.existsSync(),
          isTrue,
          reason:
              'Папка $path пропала или переименована — '
              'сторож остался бы пустым. Обновите _guardedFolders.',
        );
        expect(
          dartFilesIn(folder),
          isNotEmpty,
          reason: 'В папке $path нет ни одного .dart файла.',
        );
      });

      test('$path не содержит запрещённого', () {
        expect(scanFolder(Directory(path)), isEmpty);
      });
    }
  });
}
