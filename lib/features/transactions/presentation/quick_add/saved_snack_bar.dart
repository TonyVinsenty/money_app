import 'package:flutter/material.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/format/money_spoken.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/ui/font_scale.dart';
import 'package:money_app/core/ui/tap_to_dismiss_snack_content.dart';
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

  /// Сообщение с кнопкой «Отменить». [textScaler] — масштаб шрифта экрана
  /// (MediaQuery.textScalerOf). Автоматически исчезает через [duration]:
  /// `persist: false` нужно явно, иначе у сообщения с кнопкой время не
  /// отсчитывается.
  static SnackBar build({
    required String text,
    required String spokenText,
    required VoidCallback onUndo,
    TextScaler textScaler = TextScaler.noScaling,
  }) {
    return SnackBar(
      content: TapToDismissSnackContent(
        child: Semantics(
          label: spokenText,
          excludeSemantics: true,
          child: Text(text),
        ),
      ),
      duration: duration,
      persist: false,
      // По умолчанию «Отменить» уходит на отдельную строку, если оно шире
      // четверти экрана; тогда сообщение при обычном шрифте лишний раз
      // вырастает, поэтому держим кнопку в одной строке с текстом. Но при
      // крупном шрифте (200 % на 360 dp) кнопка занимает почти всю ширину, и
      // тексту остаётся ~40 dp: он ломается по одной букве. Тогда кнопку
      // переносим на свою строку (порог 0). Flutter меряет ширину кнопки без
      // учёта масштаба шрифта, поэтому решаем сами.
      actionOverflowThreshold: fontScaleFrom(textScaler) > 1.3 ? 0 : 1,
      action: SnackBarAction(label: undoLabel, onPressed: onUndo),
    );
  }
}
