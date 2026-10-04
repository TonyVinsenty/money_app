// Простой CSV-кодек: записывает таблицу в текст и читает её обратно.
//
// Работает только со строками (поля — это текст), без чисел и дат:
// форматирование сумм и дат делается выше, на границе экспорта.
//
// Формат (см. RFC 4180, с двумя изменениями для России):
// - разделитель полей — `;` (так Excel в русской локали ждёт файл);
// - файл начинается с BOM (метки UTF-8, символ `\uFEFF`), чтобы Excel
//   понял кодировку и не испортил кириллицу.

/// Метка порядка байт UTF-8. Excel по ней узнаёт кодировку файла.
const _bom = '\uFEFF';

/// Разделитель полей.
const _separator = ';';

/// Перенос строки по RFC 4180.
const _newline = '\r\n';

/// Превращает таблицу [rows] в текст CSV (с BOM в начале).
///
/// Поле берётся в кавычки, если внутри есть `;`, кавычка или перенос строки.
/// Внутренняя кавычка удваивается. Пустое поле пишется как пустая строка.
/// Строка без полей (пустой список) не поддерживается и даёт [ArgumentError]:
/// при чтении такая строка превратилась бы в строку с одним пустым полем.
String encodeCsv(List<List<String>> rows) {
  final buffer = StringBuffer(_bom);
  for (final row in rows) {
    if (row.isEmpty) {
      throw ArgumentError.value(rows, 'rows', 'строка CSV без полей');
    }
    buffer.write(row.map(_encodeField).join(_separator));
    buffer.write(_newline);
  }
  return buffer.toString();
}

/// Читает текст CSV обратно в таблицу.
///
/// BOM в начале снимается, если он есть. Строки можно разделять `\r\n` или `\n`.
/// Некорректный ввод даёт [FormatException] с номером строки в сообщении:
/// незакрытая кавычка, символ после закрывающей кавычки, кавычка внутри
/// поля без кавычек, одиночный `\r`.
List<List<String>> decodeCsv(String text) {
  final source = text.startsWith(_bom) ? text.substring(_bom.length) : text;
  final rows = <List<String>>[];
  if (source.isEmpty) return rows;

  var row = <String>[];
  var pos = 0;
  var line = 1;
  while (true) {
    final String value;
    if (pos < source.length && source[pos] == '"') {
      // Поле в кавычках: до закрывающей кавычки, `""` — это одна кавычка.
      final startLine = line;
      pos++;
      final buffer = StringBuffer();
      var closed = false;
      while (pos < source.length) {
        final char = source[pos];
        if (char == '"') {
          if (pos + 1 < source.length && source[pos + 1] == '"') {
            buffer.write('"');
            pos += 2;
            continue;
          }
          pos++;
          closed = true;
          break;
        }
        if (char == '\n') line++;
        buffer.write(char);
        pos++;
      }
      if (!closed) {
        throw FormatException(
          'Ошибка CSV в строке $startLine: не закрыта кавычка',
        );
      }
      if (pos < source.length && !_isFieldEnd(source[pos])) {
        throw FormatException(
          'Ошибка CSV в строке $line: после закрывающей кавычки ожидался '
          'разделитель ";" или перенос строки',
        );
      }
      value = buffer.toString();
    } else {
      // Поле без кавычек: до разделителя или конца строки.
      final start = pos;
      while (pos < source.length && !_isFieldEnd(source[pos])) {
        if (source[pos] == '"') {
          throw FormatException(
            'Ошибка CSV в строке $line: кавычка внутри поля без кавычек',
          );
        }
        pos++;
      }
      value = source.substring(start, pos);
    }
    row.add(value);

    if (pos >= source.length) {
      rows.add(row);
      return rows;
    }
    if (source[pos] == _separator) {
      pos++;
      continue;
    }
    // Здесь конец строки: либо `\r\n`, либо `\n`.
    if (source[pos] == '\r') {
      if (pos + 1 >= source.length || source[pos + 1] != '\n') {
        throw FormatException(
          'Ошибка CSV в строке $line: перенос строки должен быть CRLF или LF',
        );
      }
      pos += 2;
    } else {
      pos++;
    }
    line++;
    rows.add(row);
    row = <String>[];
    if (pos >= source.length) return rows;
  }
}

/// Что-то, после чего заканчивается поле без кавычек.
bool _isFieldEnd(String char) =>
    char == _separator || char == '\r' || char == '\n';

/// Записывает одно поле: в кавычки, только если без них нельзя.
String _encodeField(String field) {
  final needsQuotes =
      field.contains(_separator) ||
      field.contains('"') ||
      field.contains('\r') ||
      field.contains('\n');
  if (!needsQuotes) return field;
  return '"${field.replaceAll('"', '""')}"';
}
