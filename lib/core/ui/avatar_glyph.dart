import 'package:flutter/widgets.dart' show StringCharacters;

/// Ключ значка «Другое»: его получают новые категории из импорта CSV.
const String _otherIconKey = 'more_horiz';

/// Название категории, которой оставляем значок «...»: она и значит «всё
/// остальное».
const String _restName = 'прочее';

/// Что рисовать в аватаре вместо значка: первую букву названия или `null`
/// (рисуется обычный значок).
///
/// Буква только у ключа «Другое» (`more_horiz`) и только если название не
/// пустое и не «Прочее» (без учёта регистра). Первый символ берётся целиком
/// (эмодзи и цифра остаются как есть), буква - заглавная.
///
/// [otherKey] - какой ключ значит «Другое»: у категорий `more_horiz`, у
/// счетов `other`.
String? avatarGlyph(
  String? iconKey,
  String? name, {
  String otherKey = _otherIconKey,
}) {
  if (iconKey != otherKey) return null;
  final trimmed = name?.trim() ?? '';
  if (trimmed.isEmpty) return null;
  if (trimmed.toLowerCase() == _restName) return null;
  return trimmed.characters.first.toUpperCase();
}
