import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Перехватывает канал `SystemChannels.platform` и копит вызовы вибрации:
/// `HapticFeedbackType.lightImpact` и т. п. (аргумент `HapticFeedback.vibrate`).
/// Остальные вызовы канала отвечают `null`. Перехват снимается после теста.
List<String> recordHaptics(WidgetTester tester) {
  final calls = <String>[];
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'HapticFeedback.vibrate') {
      calls.add(call.arguments as String);
    }
    return null;
  });
  addTearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );
  return calls;
}
