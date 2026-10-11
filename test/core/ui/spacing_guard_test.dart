import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Сторож шкалы отступов и скруглений (ADR 0013, п. 1).
///
/// В `lib/**/presentation/` и `lib/core/ui/`:
/// - числа в `EdgeInsets.*(...)` — только 0, 4, 8, 12, 16, 24;
/// - числа в `BorderRadius.circular(...)` и `Radius.circular(...)` — 12 или 16;
/// - пустые распорки `SizedBox(width: N)` / `SizedBox(height: N)` — из шкалы.
/// Графики (`CustomPainter`) и размеры зон нажатия сторож не трогает.
const _spacingScale = <num>{0, 4, 8, 12, 16, 24};
const _radiusScale = <num>{12, 16};

final _insetsStart = RegExp(r'EdgeInsets(?:Directional)?\.[A-Za-z]+\(');
final _radiusStart = RegExp(r'(?:Border)?Radius\.circular\(');
final _spacerRule = RegExp(
  r'SizedBox\(\s*(?:width|height):\s*(\d+(?:\.\d+)?)\s*,?\s*\)',
);
final _number = RegExp(r'(?<![\w.])\d+(?:\.\d+)?');

/// Возвращает найденные нарушения в виде «строка: причина».
List<String> findSpacingViolations(String source) {
  final result = <String>[];

  void checkCalls(RegExp start, Set<num> allowed, String what) {
    for (final m in start.allMatches(source)) {
      var depth = 1;
      var i = m.end;
      while (i < source.length && depth > 0) {
        final c = source[i];
        if (c == '(') depth++;
        if (c == ')') depth--;
        i++;
      }
      final args = source.substring(m.end, i - 1);
      for (final n in _number.allMatches(args)) {
        final value = num.parse(n.group(0)!);
        if (!allowed.contains(value)) {
          final line = '\n'.allMatches(source.substring(0, m.start)).length + 1;
          result.add('строка $line: $what ${n.group(0)} вне шкалы $allowed');
        }
      }
    }
  }

  checkCalls(_insetsStart, _spacingScale, 'отступ');
  checkCalls(_radiusStart, _radiusScale, 'радиус');
  for (final m in _spacerRule.allMatches(source)) {
    final value = num.parse(m.group(1)!);
    if (!_spacingScale.contains(value)) {
      final line = '\n'.allMatches(source.substring(0, m.start)).length + 1;
      result.add('строка $line: распорка $value вне шкалы $_spacingScale');
    }
  }
  return result;
}

bool _isGuarded(String path) {
  final p = path.replaceAll(r'\', '/');
  if (!p.endsWith('.dart') || p.endsWith('.g.dart')) return false;
  // Графики рисуют сами (CustomPainter): их геометрия вне шкалы.
  if (p.endsWith('/bar_chart.dart') || p.endsWith('/donut_chart.dart')) {
    return false;
  }
  return p.contains('/presentation/') || p.contains('lib/core/ui/');
}

void main() {
  group('findSpacingViolations (проверка самого сторожа)', () {
    test('ловит EdgeInsets.all(10)', () {
      expect(
        findSpacingViolations('padding: const EdgeInsets.all(10),'),
        isNotEmpty,
      );
    });

    test('ловит числа внутри only/symmetric и условия', () {
      expect(
        findSpacingViolations('EdgeInsets.only(top: i == 0 ? 0 : 6)'),
        hasLength(1),
      );
      expect(
        findSpacingViolations(
          'EdgeInsets.symmetric(horizontal: 16, vertical: 2)',
        ),
        hasLength(1),
      );
    });

    test('ловит радиус 8 и распорку 6, пропускает шкалу', () {
      expect(findSpacingViolations('BorderRadius.circular(8)'), hasLength(1));
      expect(findSpacingViolations('SizedBox(height: 6)'), hasLength(1));
      expect(
        findSpacingViolations(
          'EdgeInsets.fromLTRB(16, 8, 12, 24); BorderRadius.circular(16); '
          'SizedBox(width: 4); EdgeInsets.only(left: AppSpacing.l)',
        ),
        isEmpty,
      );
    });
  });

  test('в lib нет отступов и скруглений вне шкалы', () {
    final violations = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !_isGuarded(entity.path)) continue;
      for (final v in findSpacingViolations(entity.readAsStringSync())) {
        violations.add('${entity.path}: $v');
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });
}
