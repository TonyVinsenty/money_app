import 'package:flutter/material.dart';

/// Заглушка на месте будущей круговой диаграммы расходов по категориям
/// (этап 4). Карточка-рамка занимает свободную середину «Главной» и честно
/// говорит, что диаграмма появится позже.
///
/// Заглушка не нажимается: без `InkWell`, без роли кнопки и без шеврона.
/// Когда появится диаграмма, этот виджет заменят целиком.
class ChartPlaceholder extends StatelessWidget {
  const ChartPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card.outlined(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Диаграмма расходов по категориям появится позже',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}
