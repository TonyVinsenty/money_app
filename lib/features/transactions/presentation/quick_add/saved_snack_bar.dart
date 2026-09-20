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

  /// «Расход 350,00 ₽ · Продукты сохранён». Сумма называется всегда, и нулевая
  /// тоже («Расход 0,00 ₽ · ...»).
  static String text({
    required TransactionType type,
    required Money amount,
    required String categoryName,
  }) {
    return '${_word(type)} ${formatMoney(amount)} · $categoryName сохранён';
  }

  /// То же для скринридера: сумма словами («Расход 350 рублей · ...»).
  static String spokenText({
    required TransactionType type,
    required Money amount,
    required String categoryName,
  }) {
    return '${_word(type)} ${spokenMoney(amount)} · $categoryName сохранён';
  }

  static String _word(TransactionType type) =>
      type == TransactionType.income ? 'Доход' : 'Расход';

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
      action: SnackBarAction(label: undoLabel, onPressed: onUndo),
    );
  }
}
