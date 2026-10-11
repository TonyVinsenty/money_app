import 'package:flutter/material.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/core/ui/period_switcher.dart';
import 'package:money_app/features/analytics/presentation/analytics_texts.dart';

/// Шапка «Аналитики»: «[Месяц ▾] ‹ Октябрь 2026 ›».
///
/// Кнопка слева открывает меню вида периода. Виджет ничего не решает сам:
/// только зовёт колбэки. Выбор дат для «Свой период…» делает экран.
/// При крупном шрифте строка переносится: вид над стрелками.
class PeriodHeader extends StatelessWidget {
  const PeriodHeader({
    required this.kind,
    required this.label,
    required this.onKindSelected,
    required this.onCustomSelected,
    required this.onPrevious,
    required this.onNext,
    required this.previousTooltip,
    required this.nextTooltip,
    super.key,
  });

  static const kindButtonKey = ValueKey('period-header-kind');
  static const customItemKey = ValueKey('period-header-custom');
  static ValueKey<String> itemKey(PeriodKind kind) =>
      ValueKey('period-header-item-${kind.name}');

  /// Масштаб шрифта, с которого строка переносится на две.
  static const double _wrapScale = 1.3;

  static const List<PeriodKind> _menuKinds = [
    PeriodKind.day,
    PeriodKind.week,
    PeriodKind.month,
    PeriodKind.year,
  ];

  final PeriodKind kind;
  final String label;
  final ValueChanged<PeriodKind> onKindSelected;
  final VoidCallback onCustomSelected;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final String previousTooltip;
  final String nextTooltip;

  Widget _kindButton() {
    return MenuAnchor(
      menuChildren: [
        for (final k in _menuKinds)
          MenuItemButton(
            key: itemKey(k),
            leadingIcon: Icon(k == kind ? Icons.check : null),
            onPressed: () => onKindSelected(k),
            child: Text(periodKindTitle(k)),
          ),
        MenuItemButton(
          key: customItemKey,
          leadingIcon: Icon(kind == PeriodKind.custom ? Icons.check : null),
          onPressed: onCustomSelected,
          child: const Text(periodCustomMenuItem),
        ),
      ],
      builder: (context, controller, _) => Semantics(
        button: true,
        label: periodKindSpoken(kind),
        excludeSemantics: true,
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
        child: TextButton.icon(
          key: kindButtonKey,
          onPressed: () =>
              controller.isOpen ? controller.close() : controller.open(),
          icon: const Icon(Icons.arrow_drop_down),
          iconAlignment: IconAlignment.end,
          label: Text(periodKindTitle(kind)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(100) / 100;
    final switcher = PeriodSwitcher(
      label: label,
      onPrevious: onPrevious,
      onNext: onNext,
      previousTooltip: previousTooltip,
      nextTooltip: nextTooltip,
    );
    if (scale >= _wrapScale) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [_kindButton(), switcher],
      );
    }
    return Row(
      children: [
        _kindButton(),
        Expanded(child: switcher),
      ],
    );
  }
}
