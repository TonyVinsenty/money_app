import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:money_app/features/recurring/domain/recurring_repository.dart';
import 'package:money_app/features/recurring/presentation/recurring_texts.dart';

/// Кружок с числом записей «К оплате» на значке вкладки «Баланс». Записей нет -
/// значок без кружка.
class DueTabBadge extends StatelessWidget {
  const DueTabBadge({required this.dues, required this.icon, super.key});

  /// Общий источник записей «К оплате»; его держит приложение (`lib/app`).
  final ValueListenable<List<RecurringDue>> dues;
  final Widget icon;

  static const badgeKey = ValueKey('due-tab-badge');

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<RecurringDue>>(
      valueListenable: dues,
      builder: (context, list, _) {
        if (list.isEmpty) return icon;
        return Semantics(
          // Значение, а не подпись: оно читается после подписи вкладки
          // («Баланс, к оплате: 3»), подпись же шла бы перед ней.
          value: dueBadgeSemantics(list.length),
          child: ExcludeSemantics(
            child: Badge(
              key: badgeKey,
              label: Text(dueBadgeText(list.length)),
              child: icon,
            ),
          ),
        );
      },
    );
  }
}
