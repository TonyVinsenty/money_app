import 'package:flutter/material.dart';

/// Подсказка скринридера для касания плашки.
const String snackBarDismissHint = 'Скрыть';

/// Содержимое плашки (`SnackBar.content`), которое закрывает её по касанию.
///
/// Кнопка действия («Отменить») лежит вне содержимого и работает как раньше;
/// свайп и таймер тоже. Для скринридера у плашки есть действие с подсказкой
/// [snackBarDismissHint].
class TapToDismissSnackContent extends StatelessWidget {
  const TapToDismissSnackContent({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final messenger = ScaffoldMessenger.of(context);
    return Semantics(
      onTap: messenger.hideCurrentSnackBar,
      onTapHint: snackBarDismissHint,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: messenger.hideCurrentSnackBar,
        child: SizedBox(width: double.infinity, child: child),
      ),
    );
  }
}
