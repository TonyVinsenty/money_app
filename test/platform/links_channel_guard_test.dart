// Сторож канала ссылок (шаг 8.0): имя канала, метода и ключа в Dart, Swift и
// Kotlin совпадают, открываются только https-адреса. Нативный код на Windows
// не собирается, поэтому проверяем текстом.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/features/settings/presentation/open_external_link.dart';

List<String> checkLinksCommon(String source) {
  final errors = <String>[];
  for (final needle in [
    '"${linksChannel.name}"',
    '"$openUrlMethod"',
    '"$openUrlArg"',
    '"https"',
  ]) {
    if (!source.contains(needle)) errors.add('Не найдено $needle');
  }
  return errors;
}

List<String> checkLinksSwift(String source) {
  final errors = checkLinksCommon(source);
  final start = source.indexOf('func didInitializeImplicitFlutterEngine');
  final end = start < 0 ? -1 : source.indexOf('func ', start + 5);
  final body = start < 0 ? '' : source.substring(start, end);
  if (!body.contains('name: linksChannelName')) {
    errors.add('Канал не создаётся в didInitializeImplicitFlutterEngine');
  }
  if (!source.contains('UIApplication.shared.open(url')) {
    errors.add('Не найдено UIApplication.shared.open');
  }
  return errors;
}

List<String> checkLinksKotlin(String source) {
  final errors = checkLinksCommon(source);
  for (final needle in [
    'linksChannelName)',
    'Intent.ACTION_VIEW',
    'ActivityNotFoundException',
  ]) {
    if (!source.contains(needle)) errors.add('Не найдено $needle');
  }
  return errors;
}

void main() {
  final swift = File('ios/Runner/AppDelegate.swift').readAsStringSync();
  final kotlin = File(
    'android/app/src/main/kotlin/com/tonyvinsenty/zuno/MainActivity.kt',
  ).readAsStringSync();

  test('AppDelegate.swift: канал, метод, ключ и только https', () {
    expect(checkLinksSwift(swift), isEmpty);
  });

  test('MainActivity.kt: канал, метод, ключ и только https', () {
    expect(checkLinksKotlin(kotlin), isEmpty);
  });

  test('сторож замечает другое имя канала, метода и ключа', () {
    for (final broken in [
      swift.replaceAll('zuno/links', 'zuno/other'),
      swift.replaceAll('"openUrl"', '"open"'),
      swift.replaceAll('args["url"]', 'args["link"]'),
      swift.replaceAll('"https"', '"http"'),
    ]) {
      expect(checkLinksSwift(broken), isNotEmpty);
    }
    for (final broken in [
      kotlin.replaceAll('zuno/links', 'zuno/other'),
      kotlin.replaceAll('"openUrl"', '"open"'),
      kotlin.replaceAll('<String>("url")', '<String>("link")'),
      kotlin.replaceAll('"https"', '"http"'),
    ]) {
      expect(checkLinksKotlin(broken), isNotEmpty);
    }
  });
}
