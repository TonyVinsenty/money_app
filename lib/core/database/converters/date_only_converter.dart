import 'package:drift/drift.dart';
import 'package:money_app/core/time/date_only.dart';

/// Превращает [DateOnly] в целое ГГГГММДД для колонки БД и обратно (ADR 0001).
///
/// Число, которое не является настоящим днём (`0`, `20260230`, `20261301`),
/// бросает [FormatException] с самим значением: испорченные данные не должны
/// молча превращаться в `null` или в «какой-нибудь» день.
class DateOnlyConverter extends TypeConverter<DateOnly, int> {
  const DateOnlyConverter();

  @override
  DateOnly fromSql(int fromDb) {
    try {
      return DateOnly.fromInt(fromDb);
    } on ArgumentError {
      throw FormatException('Bad DateOnly value in database: $fromDb');
    }
  }

  @override
  int toSql(DateOnly value) => value.toInt();
}
