import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/id/id_generator.dart';

import '../../support/fake_id_generator.dart';
import '../../support/fixed_clock.dart';

final _format = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

/// Первые 48 бит id (12 hex-цифр без дефиса) как число миллисекунд.
int _timestampOf(String id) {
  final hex = id.replaceAll('-', '').substring(0, 12);
  return int.parse(hex, radix: 16);
}

void main() {
  group('UuidV7Generator', () {
    final start = DateTime.utc(2026, 9, 20, 12, 0, 0, 123);

    test('формат: 36 символов, 8-4-4-4-12, нижний регистр, версия 7', () {
      final generator = UuidV7Generator(clock: FixedClock(start));
      for (var i = 0; i < 100; i++) {
        final id = generator.newId();
        expect(id, hasLength(36));
        expect(id, matches(_format), reason: id);
        expect(id[14], '7', reason: 'версия: $id');
        expect('89ab', contains(id[19]), reason: 'вариант: $id');
        expect(id, id.toLowerCase());
      }
    });

    test('10 000 id подряд уникальны', () {
      final generator = UuidV7Generator(clock: FixedClock(start));
      final ids = {for (var i = 0; i < 10000; i++) generator.newId()};
      expect(ids, hasLength(10000));
    });

    test('первые 48 бит равны миллисекундам часов', () {
      final clock = FixedClock(start);
      final generator = UuidV7Generator(clock: clock);
      expect(_timestampOf(generator.newId()), start.millisecondsSinceEpoch);

      clock.advance(const Duration(days: 400, milliseconds: 7));
      expect(
        _timestampOf(generator.newId()),
        start
            .add(const Duration(days: 400, milliseconds: 7))
            .millisecondsSinceEpoch,
      );
    });

    test('местное время и UTC дают одну и ту же метку', () {
      final utc = DateTime.utc(2026, 1, 2, 3, 4, 5, 6);
      final local = utc.toLocal();
      expect(
        _timestampOf(UuidV7Generator(clock: FixedClock(local)).newId()),
        utc.millisecondsSinceEpoch,
      );
    });

    test('id при разном «сейчас» возрастают как строки', () {
      // Шаги по 1 мс, в том числе через границу секунды и минуты.
      final clock = FixedClock(DateTime.utc(2026, 9, 20, 12, 59, 59, 995));
      final generator = UuidV7Generator(clock: clock);
      final ids = <String>[];
      for (var i = 0; i < 3000; i++) {
        ids.add(generator.newId());
        clock.advance(const Duration(milliseconds: 1));
      }
      final sorted = [...ids]..sort();
      expect(sorted, ids);
      expect(ids.toSet(), hasLength(ids.length));
    });

    test(
      'внутри одной миллисекунды: только различие, порядок не проверяем',
      () {
        // Пакет uuid (4.6.0) для v7 не ведёт счётчик: после 48 бит времени идут
        // случайные биты. Порядок внутри одной миллисекунды он НЕ гарантирует,
        // поэтому тестируем лишь уникальность и то, что время у всех одно.
        final generator = UuidV7Generator(clock: FixedClock(start));
        final ids = [for (var i = 0; i < 1000; i++) generator.newId()];
        expect(ids.toSet(), hasLength(ids.length));
        expect(ids.map(_timestampOf).toSet(), {start.millisecondsSinceEpoch});
        // Отличаются именно случайные хвосты (после 48 бит времени).
        expect(
          ids.map((id) => id.replaceAll('-', '').substring(12)).toSet(),
          hasLength(ids.length),
        );
      },
    );

    test('без параметров работает на системных часах', () {
      final before = DateTime.now().millisecondsSinceEpoch;
      final id = const UuidV7Generator().newId();
      final after = DateTime.now().millisecondsSinceEpoch;
      expect(id, matches(_format));
      expect(_timestampOf(id), inInclusiveRange(before, after));
    });
  });

  group('FakeIdGenerator', () {
    test('выдаёт id-1, id-2, ...', () {
      final fake = FakeIdGenerator();
      expect(
        [fake.newId(), fake.newId(), fake.newId()],
        ['id-1', 'id-2', 'id-3'],
      );
    });

    test('префикс задаётся', () {
      final fake = FakeIdGenerator(prefix: 'expense');
      expect([fake.newId(), fake.newId()], ['expense-1', 'expense-2']);
    });

    test('независимые экземпляры не делят счётчик', () {
      final a = FakeIdGenerator();
      final b = FakeIdGenerator();
      a.newId();
      a.newId();
      expect(b.newId(), 'id-1');
      expect(a.newId(), 'id-3');
    });
  });
}
