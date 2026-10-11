import 'package:flutter/material.dart';
import 'package:money_app/core/format/date_format.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/card_header.dart';
import 'package:money_app/core/ui/theme/app_spacing.dart';

/// Тексты пустой «Главной» (У4, утверждены 2026-10-11).
const homeWelcomeTitle = 'Добро пожаловать в Zuno';
const homeWelcomeText =
    'Нажмите «\u2212 Расход» или «+ Доход» внизу — здесь появятся итоги '
    'месяца, а кольцо покажет, на что уходят деньги';
const homeWelcomeImportHint =
    'Есть записи из другого приложения? «Настройки» → «Загрузить из CSV»';

/// Строка вместо кольца, когда операции есть, а в месяце [month] — нет:
/// «В октябре операций пока нет», для прошлых — «В сентябре 2026 операций
/// не было». Склонение месяца своё, без `intl`.
String homeEmptyMonthText(DateOnly month, {required bool isCurrentMonth}) =>
    isCurrentMonth
    ? 'В ${formatMonthPrepositional(month)} операций пока нет'
    : 'В ${formatMonthPrepositional(month)} ${month.year} операций не было';

/// Карточка-приветствие вместо итогов и кольца, пока в базе нет ни одной
/// операции: кольцо 0,00 ₽ ничего не объясняет новичку.
class HomeWelcomeCard extends StatelessWidget {
  const HomeWelcomeCard({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card.outlined(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.borderL,
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CardHeader(homeWelcomeTitle),
            Text(homeWelcomeText, style: theme.textTheme.bodyLarge),
            const SizedBox(height: AppSpacing.m),
            Text(
              homeWelcomeImportHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
