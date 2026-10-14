import 'package:flutter/material.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/app_card.dart';
import 'package:money_app/core/ui/category_labels.dart';
import 'package:money_app/core/ui/masked_amount.dart';
import 'package:money_app/features/analytics/domain/analytics_period.dart';
import 'package:money_app/features/analytics/domain/hints.dart';
import 'package:money_app/features/analytics/presentation/analytics_texts.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';

/// Карточка подсказок над кольцом в «Категориях»: лампочка и 1–3 строки.
/// Подсказки только по расходам и не зависят от переключателя «Расходы |
/// Доходы» (ADR 0012). Подсказок нет: ничего не рисуется, отступа тоже нет.
///
/// Подсказка «больше, чем за весь прошлый» (с «уже») есть только для периода с
/// сегодняшним днём: это решает `analyticsHints`.
class AnalyticsHintsCard extends StatelessWidget {
  const AnalyticsHintsCard({
    required this.transactions,
    required this.period,
    required this.today,
    required this.categories,
    required this.currency,
    super.key,
  });

  /// Операции окна данных (период и период сравнения).
  final List<Transaction> transactions;
  final AnalyticsPeriod period;
  final DateOnly today;

  /// Все категории, включая архивные.
  final List<Category> categories;
  final String currency;

  static const cardKey = ValueKey('analytics-hints-card');
  static Key lineKey(int index) => ValueKey('analytics-hint-$index');

  @override
  Widget build(BuildContext context) {
    final hints = analyticsHints(
      transactions,
      period,
      today,
      currency: currency,
    );
    if (hints.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final byId = {for (final c in categories) c.id: c};
    String nameOf(String id) => byId[id]?.name ?? noCategoryLabel;
    String text(AnalyticsHint hint, bool spoken) => analyticsHintText(
      hint,
      nameOf: nameOf,
      period: period,
      today: today,
      spoken: spoken,
      hidden: AmountsVisibility.hiddenOf(context),
    );

    // Заголовок для скринридера: одна подпись на всю карточку, строки внутри
    // остаются отдельными узлами (container: true).
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Semantics(
        container: true,
        label: analyticsHintsTitle,
        child: AppCard(
          key: cardKey,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(
                child: Icon(
                  Icons.lightbulb_outline,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < hints.length; i++) ...[
                      if (i > 0) const SizedBox(height: 8),
                      Semantics(
                        container: true,
                        label: text(hints[i], true),
                        excludeSemantics: true,
                        child: Text(
                          text(hints[i], false),
                          key: lineKey(i),
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
