import 'package:flutter/material.dart';
import 'package:money_app/core/format/day_label.dart';
import 'package:money_app/core/time/date_only.dart';

/// Самый ранний день, который можно выбрать в календаре.
final DateOnly dateChipFirstDay = DateOnly(2000, 1, 1);

/// Плашка даты операции: «Сегодня», «Вчера» или дата словами.
///
/// Тап открывает русский календарь. Выбрать день позже [today] нельзя
/// (операция это факт, а не план), самый ранний день — [dateChipFirstDay].
/// Плашка сама ничего не хранит: выбранный день приходит в [value], а новый
/// выбор уходит в [onChanged]. «Сегодня» ([today]) передаёт вызывающий из
/// `Clock`, поэтому в тестах его можно зафиксировать.
class DateChip extends StatelessWidget {
  const DateChip({
    required this.value,
    required this.today,
    required this.onChanged,
    super.key,
  });

  final DateOnly value;
  final DateOnly today;
  final ValueChanged<DateOnly> onChanged;

  Future<void> _pick(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: value.toDateTime(),
      firstDate: dateChipFirstDay.toDateTime(),
      lastDate: today.toDateTime(),
    );
    if (picked != null) {
      onChanged(DateOnly.fromDateTime(picked));
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = dayLabel(value, today: today);
    // Скринридеру: «Дата операции: сегодня» (слова «Сегодня»/«Вчера» читаем с
    // маленькой буквы, у полной даты регистр не меняется).
    final spoken = 'Дата операции: ${label.toLowerCase()}';
    // excludeSemantics убирает внутренности (слово и иконку), чтобы скринридер
    // прочитал одну фразу; нажатие поэтому задано на самом узле.
    return Semantics(
      label: spoken,
      button: true,
      onTap: () => _pick(context),
      excludeSemantics: true,
      child: ConstrainedBox(
        // Зона нажатия не меньше 48 dp по высоте и ширине.
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        child: ActionChip(
          avatar: const Icon(Icons.calendar_today_outlined, size: 18),
          label: Text(label),
          onPressed: () => _pick(context),
          materialTapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),
    );
  }
}
