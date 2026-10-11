import 'package:flutter/widgets.dart';

/// Отступ прокручиваемого списка вкладки: [base] плюс место под нижней
/// панелью-капсулой (и кнопками над ней), которое каркас приложения
/// сообщает через `MediaQuery.padding.bottom` (`Scaffold.extendBody`).
///
/// Нужен списку с явным `padding`: без него `ListView` добавляет этот отступ
/// сам, а с ним — нет, и последняя строка остаётся под капсулой.
EdgeInsets withBottomInset(BuildContext context, EdgeInsets base) =>
    base.copyWith(bottom: base.bottom + MediaQuery.paddingOf(context).bottom);
