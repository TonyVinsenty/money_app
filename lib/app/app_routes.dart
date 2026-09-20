import 'package:flutter/material.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';
import 'package:money_app/features/transactions/presentation/quick_add/quick_add_screen.dart';

/// Имена маршрутов приложения. Живут в `lib/app/`, потому что только
/// приложение знает, какие экраны разных фич как связаны (ADR 0002).
abstract final class AppRoutes {
  /// Экран быстрого ввода. Аргумент маршрута — [TransactionType].
  static const quickAdd = '/quick-add';
}

/// Собирает маршрут по имени: подключается как `MaterialApp.onGenerateRoute`.
/// Неизвестное имя — `null`, тогда Flutter пробует другие способы или
/// сообщает об ошибке сам.
Route<dynamic>? onGenerateAppRoute(RouteSettings settings) {
  switch (settings.name) {
    case AppRoutes.quickAdd:
      final type = settings.arguments;
      if (type is! TransactionType) {
        // Ошибка программиста, а не пользователя: показываем понятную причину
        // вместо падения где-то глубже из-за null.
        throw ArgumentError.value(
          type,
          'arguments',
          'Маршрут ${AppRoutes.quickAdd} ожидает аргумент TransactionType '
              '(доход или расход)',
        );
      }
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => QuickAddScreen(type: type),
      );
  }
  return null;
}
