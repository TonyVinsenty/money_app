import 'dart:convert';

/// Имена для экрана «Спасибо» (этап 8, шаг 8.31) по трём уровням:
/// [tier3] — старший, [tier1] — младший.
///
/// Список лежит в ресурсах приложения (`assets/thanks.json`) и обновляется
/// с новой сборкой. Имя добавляется только с согласия человека и только под
/// тем ником, который он сам назвал.
final class Thanks {
  const Thanks({
    this.tier3 = const [],
    this.tier2 = const [],
    this.tier1 = const [],
  });

  /// Пустой список: ни одного имени.
  static const empty = Thanks();

  final List<String> tier3;
  final List<String> tier2;
  final List<String> tier1;

  /// Нет ни одного имени ни на одном уровне.
  bool get isEmpty => tier3.isEmpty && tier2.isEmpty && tier1.isEmpty;

  /// Разбирает JSON вида `{"t3": [...], "t2": [...], "t1": [...]}`.
  ///
  /// Порядок имён — как в файле; пробелы по краям обрезаются; пустые строки
  /// и не-строки пропускаются. Нет ключа — пустой уровень; битый JSON или
  /// не объект — пустой список целиком. Исключений не бросает: экран
  /// «Спасибо» не должен падать из-за опечатки в файле.
  static Thanks parse(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      return empty;
    }
    if (decoded is! Map<String, Object?>) return empty;
    return Thanks(
      tier3: _names(decoded['t3']),
      tier2: _names(decoded['t2']),
      tier1: _names(decoded['t1']),
    );
  }

  static List<String> _names(Object? value) {
    if (value is! List<Object?>) return const [];
    return List.unmodifiable([
      for (final item in value)
        if (item is String && item.trim().isNotEmpty) item.trim(),
    ]);
  }
}
