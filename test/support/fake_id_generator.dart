import 'package:money_app/core/id/id_generator.dart';

/// Генератор id для тестов: `id-1`, `id-2`, ... по своему счётчику.
final class FakeIdGenerator implements IdGenerator {
  FakeIdGenerator({this.prefix = 'id'});

  final String prefix;

  int _counter = 0;

  @override
  String newId() {
    _counter++;
    return '$prefix-$_counter';
  }
}
