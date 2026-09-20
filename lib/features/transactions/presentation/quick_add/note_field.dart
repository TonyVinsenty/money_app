import 'package:flutter/material.dart';
import 'package:money_app/core/ui/runes_length_formatter.dart';
import 'package:money_app/features/transactions/domain/transaction_rules.dart';

/// Строка необязательного комментария на экране выбора категории.
///
/// Текст живёт в [controller], который создаёт и освобождает владелец поля.
/// Готовое к сохранению значение получают через `normalizeTransactionNote`
/// (тот же код, что нормализует комментарий в `domain`): пробелы по краям
/// обрезаются, пустая строка означает «комментария нет» (`null`).
///
/// Поведение:
/// - подпись «Комментарий (необязательно)» видна всегда, а не только пока поле
///   пусто (`floatingLabelBehavior.always`);
/// - счётчик «N/200» считает кодовые точки, как `domain`, поэтому встроенный
///   `maxLength` не используется;
/// - поле не забирает фокус само (`autofocus: false`): клавиатура открывается
///   только по тапу; кнопка «Готово» на клавиатуре убирает фокус.
class NoteField extends StatelessWidget {
  const NoteField({required this.controller, super.key});

  final TextEditingController controller;

  static const label = 'Комментарий (необязательно)';
  static const hint =
      'Нажмите на категорию — операция сохранится сразу, вместе с комментарием';

  static String counterText(int length) => '$length/$transactionNoteMaxLength';

  static String counterSemantics(int length) =>
      'Введено $length из $transactionNoteMaxLength символов';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              final length = runesLength(value.text);
              return TextField(
                controller: controller,
                autofocus: false,
                maxLines: 1,
                keyboardType: TextInputType.text,
                textInputAction: TextInputAction.done,
                textCapitalization: TextCapitalization.sentences,
                inputFormatters: const [
                  RunesLengthFormatter(transactionNoteMaxLength),
                ],
                decoration: InputDecoration(
                  labelText: label,
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  border: const OutlineInputBorder(),
                  counter: Text(
                    counterText(length),
                    semanticsLabel: counterSemantics(length),
                  ),
                ),
              );
            },
          ),
          Text(
            hint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
