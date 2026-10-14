import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/theme/app_spacing.dart';

/// Кнопки и чипы листа с колесом даты.
const dateWheelCancel = 'Отмена';
const dateWheelDone = 'Готово';
const dateWheelToday = 'Сегодня';
const dateWheelYesterday = 'Вчера';

/// Высота колеса, как у системного календаря iOS.
const _wheelHeight = 216.0;

/// Выбор дня: на iOS — лист с колесом ([showDateWheelSheet]), на Android —
/// Material-календарь, как раньше. Границы [first]..[last] включительно;
/// [today] приходит из `Clock` (ADR 0004). `null` — выбор отменили.
Future<DateOnly?> pickDate(
  BuildContext context, {
  required DateOnly initial,
  required DateOnly first,
  required DateOnly last,
  required DateOnly today,
  String title = 'Дата',
}) async {
  if (Theme.of(context).platform == TargetPlatform.iOS) {
    return showDateWheelSheet(
      context,
      initial: initial,
      first: first,
      last: last,
      today: today,
      title: title,
    );
  }
  final picked = await showDatePicker(
    context: context,
    initialDate: initial.toDateTime(),
    firstDate: first.toDateTime(),
    lastDate: last.toDateTime(),
  );
  return picked == null ? null : DateOnly.fromDateTime(picked);
}

/// Лист снизу с колесом «день · месяц · год» и чипами «Сегодня»/«Вчера».
/// Возвращает день после «Готово» или `null` при «Отмене» и смахивании.
/// Чип, чей день вне границ [first]..[last], недоступен.
Future<DateOnly?> showDateWheelSheet(
  BuildContext context, {
  required DateOnly initial,
  required DateOnly first,
  required DateOnly last,
  required DateOnly today,
  required String title,
}) {
  return showModalBottomSheet<DateOnly>(
    context: context,
    useSafeArea: true,
    builder: (context) => _DateWheel(
      initial: initial,
      first: first,
      last: last,
      today: today,
      title: title,
    ),
  );
}

class _DateWheel extends StatefulWidget {
  const _DateWheel({
    required this.initial,
    required this.first,
    required this.last,
    required this.today,
    required this.title,
  });

  final DateOnly initial;
  final DateOnly first;
  final DateOnly last;
  final DateOnly today;
  final String title;

  @override
  State<_DateWheel> createState() => _DateWheelState();
}

class _DateWheelState extends State<_DateWheel> {
  late var _date = _clamp(widget.initial);

  DateOnly _clamp(DateOnly day) {
    if (day < widget.first) return widget.first;
    if (day > widget.last) return widget.last;
    return day;
  }

  bool _inRange(DateOnly day) => day >= widget.first && day <= widget.last;

  Widget _chip(String label, DateOnly day) {
    return ActionChip(
      label: Text(label),
      // Колесо не умеет прыгать само: пересоздаём его с новым днём (ключ).
      onPressed: _inRange(day) ? () => setState(() => _date = day) : null,
    );
  }

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
                  child: const Text(dateWheelCancel),
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
                  onPressed: () => Navigator.of(context).pop(_date),
                  child: const Text(dateWheelDone),
                ),
              ],
            ),
          ),
          Wrap(
            spacing: AppSpacing.s,
            children: [
              _chip(dateWheelToday, widget.today),
              _chip(dateWheelYesterday, widget.today.addDays(-1)),
            ],
          ),
          SizedBox(
            height: _wheelHeight,
            // Высота строк колеса постоянная: крупный шрифт растёт только
            // до 130 %, иначе подписи обрезаются (design-style.md, 8.6).
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.3,
              child: CupertinoDatePicker(
                key: ValueKey(_date),
                mode: CupertinoDatePickerMode.date,
                initialDateTime: _date.toDateTime(),
                minimumDate: widget.first.toDateTime(),
                maximumDate: widget.last.toDateTime(),
                onDateTimeChanged: (value) =>
                    _date = DateOnly.fromDateTime(value),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
