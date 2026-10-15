import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/features/settings/data/thanks_loader.dart';
import 'package:money_app/features/settings/domain/thanks.dart';

/// Ресурсы из памяти: отдаёт заданную строку или «файла нет».
class _FakeBundle extends CachingAssetBundle {
  _FakeBundle(this.source);

  final String? source;

  @override
  Future<ByteData> load(String key) async {
    final text = source;
    if (key != thanksAssetPath || text == null) {
      throw FlutterError('Нет ресурса $key');
    }
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(text)));
  }
}

void main() {
  group('Thanks.parse', () {
    test('пустые уровни — пустой список', () {
      final thanks = Thanks.parse('{"t3": [], "t2": [], "t1": []}');
      expect(thanks.isEmpty, isTrue);
      expect(thanks.tier3, isEmpty);
      expect(thanks.tier2, isEmpty);
      expect(thanks.tier1, isEmpty);
    });

    test('три уровня, порядок как в файле', () {
      final thanks = Thanks.parse(
        '{"t1": ["Яна", "Антон"], "t3": ["Мария", "Борис"], "t2": ["Ким"]}',
      );
      expect(thanks.tier3, ['Мария', 'Борис']);
      expect(thanks.tier2, ['Ким']);
      expect(thanks.tier1, ['Яна', 'Антон']);
      expect(thanks.isEmpty, isFalse);
    });

    test('пробелы обрезаются, пустые строки и не-строки пропускаются', () {
      final thanks = Thanks.parse(
        '{"t3": ["  Мария ", "", "   ", 42, null, true, {"a": 1}, ["Б"], "Ли"]}',
      );
      expect(thanks.tier3, ['Мария', 'Ли']);
      expect(thanks.tier2, isEmpty);
      expect(thanks.tier1, isEmpty);
    });

    test('нет ключа или уровень не список — пустой уровень', () {
      final thanks = Thanks.parse('{"t2": "Ким", "t1": ["Яна"]}');
      expect(thanks.tier3, isEmpty);
      expect(thanks.tier2, isEmpty);
      expect(thanks.tier1, ['Яна']);
    });

    test('лишние ключи (правило в файле) не мешают', () {
      final thanks = Thanks.parse('{"_rule": "текст", "t3": ["Мария"]}');
      expect(thanks.tier3, ['Мария']);
    });

    for (final broken in ['', '{', 'не json', '[]', '"t3"', '42', 'null']) {
      test('битый JSON или не объект «$broken» — пустой список', () {
        expect(Thanks.parse(broken).isEmpty, isTrue);
      });
    }

    test('списки нельзя изменить снаружи', () {
      final thanks = Thanks.parse('{"t1": ["Яна"]}');
      expect(() => thanks.tier1.add('Ким'), throwsUnsupportedError);
    });
  });

  group('loadThanks', () {
    test('читает список из ресурсов', () async {
      final thanks = await loadThanks(bundle: _FakeBundle('{"t2": ["Ким"]}'));
      expect(thanks.tier2, ['Ким']);
    });

    test('ресурса нет — пустой список, без исключения', () async {
      final thanks = await loadThanks(bundle: _FakeBundle(null));
      expect(thanks.isEmpty, isTrue);
    });
  });

  group('настоящий assets/thanks.json', () {
    test('лежит в ресурсах и разбирается без ошибок', () {
      final file = File(thanksAssetPath);
      expect(file.existsSync(), isTrue);
      final source = file.readAsStringSync();
      // Файл — объект JSON с тремя уровнями-списками.
      final decoded = jsonDecode(source) as Map<String, Object?>;
      for (final key in ['t3', 't2', 't1']) {
        expect(decoded[key], isA<List<Object?>>(), reason: key);
      }
      // Каждое имя — непустая строка без пробелов по краям: разбор ничего
      // молча не выбросил.
      final thanks = Thanks.parse(source);
      expect(
        thanks.tier3.length + thanks.tier2.length + thanks.tier1.length,
        [
          for (final key in ['t3', 't2', 't1']) ...decoded[key]! as List,
        ].length,
      );
    });

    test('подключён в pubspec.yaml', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('    - $thanksAssetPath'));
    });

    test('правило о согласии записано в самом файле', () {
      final source = File(thanksAssetPath).readAsStringSync();
      expect(source, contains('согласия человека'));
    });
  });
}
