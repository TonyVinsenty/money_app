import 'package:flutter/material.dart';
import 'package:money_app/core/time/clock.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';
import 'package:money_app/features/transactions/presentation/quick_add/quick_add_screen.dart';

/// Имена маршрутов приложения. Живут в `lib/app/`, потому что только
/// приложение знает, какие экраны разных фич как связаны (ADR 0002).
abstract final class AppRoutes {
  /// Экран быстрого ввода. Аргумент маршрута — [QuickAddRouteArguments].
  static const quickAdd = '/quick-add';
}

/// Аргументы маршрута [AppRoutes.quickAdd].
///
/// Зачем тут часы: открытый по имени экран лежит в `Navigator` рядом с главным
/// экраном, а не под `AppScope`, поэтому сам достать сервисы он не может. Их
/// достаёт тот, кто открывает маршрут (он стоит под `AppScope`), и передаёт
/// сюда.
final class QuickAddRouteArguments {
  const QuickAddRouteArguments({required this.type, required this.clock});

  final TransactionType type;
  final Clock clock;
}

/// Собирает маршрут по имени: подключается как `MaterialApp.onGenerateRoute`.
/// Неизвестное имя — `null`, тогда Flutter пробует другие способы или
/// сообщает об ошибке сам.
Route<dynamic>? onGenerateAppRoute(RouteSettings settings) {
  switch (settings.name) {
    case AppRoutes.quickAdd:
      final arguments = settings.arguments;
      if (arguments is! QuickAddRouteArguments) {
        // Ошибка программиста, а не пользователя: показываем понятную причину
        // вместо падения где-то глубже из-за null.
        throw ArgumentError.value(
          arguments,
          'arguments',
          'Маршрут ${AppRoutes.quickAdd} ожидает аргумент '
              'QuickAddRouteArguments (тип операции TransactionType и часы)',
        );
      }
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) =>
            QuickAddScreen(type: arguments.type, clock: arguments.clock),
      );
  }
  return null;
}
