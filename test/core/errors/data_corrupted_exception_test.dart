import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/errors/data_corrupted_exception.dart';

void main() {
  test('хранит сообщение, причины может не быть', () {
    const e = DataCorruptedException('bad row');
    expect(e.message, 'bad row');
    expect(e.cause, isNull);
    expect(e.toString(), 'DataCorruptedException: bad row');
  });

  test('хранит причину и показывает её в toString', () {
    final cause = FormatException('oops');
    final e = DataCorruptedException('bad row', cause: cause);
    expect(e.cause, same(cause));
    expect(e.toString(), contains('bad row'));
    expect(e.toString(), contains('oops'));
  });

  test('это Exception', () {
    expect(
      () => throw const DataCorruptedException('x'),
      throwsA(isA<DataCorruptedException>()),
    );
  });
}
