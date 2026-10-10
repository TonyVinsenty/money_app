import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/app/app_version.dart';

void main() {
  test('appVersion совпадает со строкой version: в pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(
      r'^version:\s*(\S+)\s*$',
      multiLine: true,
    ).firstMatch(pubspec);
    expect(match, isNotNull, reason: 'в pubspec.yaml нет строки version:');
    expect(
      appVersion,
      match!.group(1),
      reason: 'Поднимите номер и в pubspec.yaml, и в lib/app/app_version.dart',
    );
  });
}
