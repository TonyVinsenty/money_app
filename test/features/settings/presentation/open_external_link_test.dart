import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/features/settings/presentation/open_external_link.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> calls;

  void replyWith(Object? Function() reply) {
    messenger.setMockMethodCallHandler(linksChannel, (call) async {
      calls.add(call);
      return reply();
    });
  }

  setUp(() => calls = []);
  tearDown(() => messenger.setMockMethodCallHandler(linksChannel, null));

  test('шлёт в канал метод openUrl с адресом', () async {
    replyWith(() => true);
    expect(await openExternalLink('https://boosty.to/tony_vinsenty'), isTrue);
    expect(calls.single.method, 'openUrl');
    expect(calls.single.arguments, {'url': 'https://boosty.to/tony_vinsenty'});
  });

  test('натив ответил false или null — не открылось', () async {
    replyWith(() => false);
    expect(await openExternalLink('https://example.com'), isFalse);
    replyWith(() => null);
    expect(await openExternalLink('https://example.com'), isFalse);
  });

  test('ошибка натива — не открылось, без исключения', () async {
    replyWith(() => throw PlatformException(code: 'failed'));
    expect(await openExternalLink('https://example.com'), isFalse);
  });

  test('платформа без реализации — не открылось', () async {
    messenger.setMockMethodCallHandler(linksChannel, null);
    expect(await openExternalLink('https://example.com'), isFalse);
  });
}
