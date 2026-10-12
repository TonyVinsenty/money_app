import 'package:flutter/material.dart';

/// Сколько длится смена суммы (ADR 0013, п. 7).
const Duration amountSwitchDuration = Duration(milliseconds: 250);

/// Плавная смена суммы: когда меняется [switchKey] (текст суммы, «пусто»,
/// «ошибка»), прежнее содержимое растворяется, а новое проявляется на его
/// месте. Первый показ — без анимации. При «Уменьшить движение»
/// (`MediaQuery.disableAnimations`) новое содержимое встаёт сразу.
///
/// [alignment] — к какому краю прижаты прежнее и новое содержимое, пока они
/// видны вместе: так суммы разной длины не «прыгают».
class AmountSwitcher extends StatelessWidget {
  const AmountSwitcher({
    required this.switchKey,
    required this.child,
    this.alignment = AlignmentDirectional.centerStart,
    super.key,
  });

  final Object switchKey;
  final Widget child;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return AnimatedSwitcher(
      duration: reduceMotion ? Duration.zero : amountSwitchDuration,
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      layoutBuilder: (current, previous) =>
          Stack(alignment: alignment, children: [...previous, ?current]),
      child: KeyedSubtree(key: ValueKey(switchKey), child: child),
    );
  }
}
