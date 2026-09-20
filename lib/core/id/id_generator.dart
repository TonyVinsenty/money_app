import 'package:money_app/core/time/clock.dart';
import 'package:uuid/data.dart';
import 'package:uuid/uuid.dart';

/// Источник идентификаторов записей (ADR 0001: `id` — текст, UUID v7).
///
/// Код, которому нужен новый id, получает [IdGenerator] параметром, а в
/// тестах подставляется предсказуемая реализация.
abstract interface class IdGenerator {
  /// Возвращает новый уникальный идентификатор.
  String newId();
}

/// Генератор UUID версии 7: первые 48 бит — время в миллисекундах, остальное
/// случайное. Строка в нижнем регистре, формат 8-4-4-4-12.
///
/// Порядок по времени гарантирован только между id, созданными в РАЗНЫЕ
/// миллисекунды. Внутри одной миллисекунды пакет `uuid` порядок не
/// гарантирует: там 74 случайных бита без счётчика.
final class UuidV7Generator implements IdGenerator {
  const UuidV7Generator({this._clock = const SystemClock()});

  final Clock _clock;

  static const _uuid = Uuid();

  @override
  String newId() {
    final millis = _clock.now().millisecondsSinceEpoch;
    return _uuid.v7(config: V7Options(millis, null));
  }
}
