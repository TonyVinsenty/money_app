import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:money_app/core/ui/theme/app_spacing.dart';
import 'package:money_app/features/recurring/domain/reminder_plan.dart';

/// Кнопки листа с колесом времени.
const reminderWheelCancel = 'Отмена';
const reminderWheelDone = 'Готово';

/// Высота колеса, как у системного будильника iOS.
const _wheelHeight = 216.0;

/// Лист снизу с колесом «часы : минуты» в 24-часовом формате (7.30f) — так
/// время выбирают на iPhone. Возвращает выбранное время после «Готово» или
/// `null`, если лист закрыли «Отменой» или смахиванием.
Future<ReminderTime?> showReminderTimeWheel(
  BuildContext context, {
  required ReminderTime initial,
  required String title,
}) {
  return showModalBottomSheet<ReminderTime>(
    context: context,
    useSafeArea: true,
    builder: (context) => _ReminderTimeWheel(initial: initial, title: title),
  );
}

class _ReminderTimeWheel extends StatefulWidget {
  const _ReminderTimeWheel({required this.initial, required this.title});

  final ReminderTime initial;
  final String title;

  @override
  State<_ReminderTimeWheel> createState() => _ReminderTimeWheelState();
}

class _ReminderTimeWheelState extends State<_ReminderTimeWheel> {
  late var _time = widget.initial;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
            child: Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(reminderWheelCancel),
                ),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      widget.title,
                      style: textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(_time),
                  child: const Text(reminderWheelDone),
                ),
              ],
            ),
          ),
          SizedBox(
            height: _wheelHeight,
            // Высота строк колеса постоянная: крупный шрифт растёт только
            // до 130 %, иначе цифры обрезаются (design-style.md, 8.6).
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.3,
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.time,
                use24hFormat: true,
                initialDateTime: DateTime(
                  2000,
                  1,
                  1,
                  widget.initial.hour,
                  widget.initial.minute,
                ),
                onDateTimeChanged: (value) =>
                    _time = ReminderTime(value.hour, value.minute),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
