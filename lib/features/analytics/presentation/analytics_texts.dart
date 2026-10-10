import 'package:money_app/features/analytics/presentation/analytics_controller.dart';

/// Тексты вкладки «Аналитика», добавленные этапом А (ADR 0012). Тексты
/// утверждены пользователем 2026-10-11 (ROADMAP, «Тексты» Т1–Т6).

/// Т1. Название раздела в строке разделов.
String analyticsSectionTitle(AnalyticsSection section) => switch (section) {
  AnalyticsSection.categories => 'Категории',
  AnalyticsSection.dynamics => 'Динамика',
  AnalyticsSection.comparison => 'Сравнение',
  AnalyticsSection.operations => 'Операции',
};
