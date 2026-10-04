import 'package:flutter/material.dart';

/// Переключатель периода: «‹ подпись ›».
///
/// Виджет не знает, что за период (месяц, неделя) и что внутри: он показывает
/// готовую [label] и зовёт [onPrevious]/[onNext]. Если колбэк `null`, стрелка
/// недоступна и приглушена. Если недоступны обе, стрелки скрыты, но место за
/// ними сохраняется, чтобы подпись не сдвигалась.
class PeriodSwitcher extends StatelessWidget {
  const PeriodSwitcher({
    required this.label,
    required this.onPrevious,
    required this.onNext,
    required this.previousTooltip,
    required this.nextTooltip,
    super.key,
  });

  /// Ключи стрелок: на них опираются тесты.
  static const previousKey = ValueKey('period-switcher-previous');
  static const nextKey = ValueKey('period-switcher-next');

  /// Размер зоны нажатия стрелки, dp (минимум для пальца на Android).
  static const double _arrowSize = 48;

  final String label;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  /// Подсказки стрелок (они же читаются скринридером).
  final String previousTooltip;
  final String nextTooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hideArrows = onPrevious == null && onNext == null;

    Widget arrow(Key key, IconData icon, String tooltip, VoidCallback? onTap) {
      if (hideArrows) return const SizedBox(width: _arrowSize);
      return IconButton(
        key: key,
        icon: Icon(icon),
        tooltip: tooltip,
        onPressed: onTap,
        color: scheme.onSurfaceVariant,
        disabledColor: scheme.onSurfaceVariant.withValues(alpha: 0.38),
        constraints: const BoxConstraints.tightFor(
          width: _arrowSize,
          height: _arrowSize,
        ),
      );
    }

    return Row(
      children: [
        arrow(previousKey, Icons.chevron_left, previousTooltip, onPrevious),
        Expanded(
          // liveRegion: скринридер объявляет смену подписи.
          child: Semantics(
            liveRegion: true,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                softWrap: false,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
        arrow(nextKey, Icons.chevron_right, nextTooltip, onNext),
      ],
    );
  }
}
