import 'package:money_app/features/settings/domain/app_icon_choice.dart';

/// Смена иконки приложения (ADR 0014). Что стоит сейчас, знает только
/// система: ответ не хранится, его каждый раз спрашивают.
abstract interface class AppIconService {
  /// Умеет ли система менять иконку.
  Future<bool> supported();

  /// Какая иконка стоит сейчас; `null` — узнать не удалось.
  Future<AppIconChoice?> current();

  /// Меняет иконку; `true` — система согласилась.
  Future<bool> set(AppIconChoice choice);
}
