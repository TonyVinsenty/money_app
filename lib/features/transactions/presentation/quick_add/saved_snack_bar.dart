import 'package:flutter/material.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/format/money_spoken.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

/// Подписи и сборка сообщений после сохранения операции.
abstract final class SavedSnackBar {
  static const undoLabel = 'Отменить';
  static const undoFailedText = 'Не удалось отменить. Попробуйте ещё раз';

  /// Сколько сообщение висит на экране.
  static const duration = Duration(seconds: 6);

  /// «Сохранено: расход 350,00 ₽ · Продукты». Сумма называется всегда, и
  /// нулевая тоже («Сохранено: расход 0,00 ₽ · ...»).
  /// С подкатегорией — «... · Продукты · Овощи».
  static String text({
    required TransactionType type,
    required Money amount,
    required String categoryName,
    String? subcategoryName,
  }) {
    return 'Сохранено: ${_word(type)} ${formatMoney(amount)} · $categoryName'
        '${_sub(subcategoryName)}';
  }

  /// То же для скринридера: сумма словами («Сохранено: расход 350 рублей · ...»).
  static String spokenText({
    required TransactionType type,
    required Money amount,
    required String categoryName,
    String? subcategoryName,
  }) {
    return 'Сохранено: ${_word(type)} ${spokenMoney(amount)} · $categoryName'
        '${_sub(subcategoryName)}';
  }

  static String _sub(String? name) => name == null ? '' : ' · $name';

  static String _word(TransactionType type) =>
      type == TransactionType.income ? 'доход' : 'расход';

  /// Сообщение с кнопкой «Отменить». Автоматически исчезает через [duration]:
  /// `persist: false` нужно явно, иначе у сообщения с кнопкой время не
  /// отсчитывается.
  static SnackBar build({
    required String text,
    required String spokenText,
    required VoidCallback onUndo,
  }) {
    return SnackBar(
      content: Semantics(
        label: spokenText,
        excludeSemantics: true,
        child: Text(text),
      ),
      duration: duration,
      persist: false,
      // По умолчанию «Отменить» уходит на отдельную строку, если оно шире
      // четверти экрана; тогда сообщение вырастает до ~150 dp и не влезает в
      // запас под ним на «Главной». Держим кнопку в одной строке с текстом.
      actionOverflowThreshold: 1,
      action: SnackBarAction(label: undoLabel, onPressed: onUndo),
    );
  }
}
