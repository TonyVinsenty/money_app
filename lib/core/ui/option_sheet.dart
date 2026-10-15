import 'package:flutter/material.dart';
import 'package:money_app/core/ui/theme/app_spacing.dart';

/// Один вариант в листе выбора [showOptionSheet].
class OptionSheetItem<T> {
  const OptionSheetItem({
    required this.value,
    required this.title,
    this.subtitle,
    this.leading,
  });

  /// Что вернёт лист, если вариант выбран.
  final T value;
  final String title;

  /// Пояснение мелким шрифтом под названием.
  final String? subtitle;

  /// Значок или аватар слева.
  final Widget? leading;
}

/// Лист выбора одного из вариантов (D6, D37): заголовок, строки с галочкой
/// справа у выбранного. Один вид на обеих платформах вместо выпадающих
/// списков Material; [footer] — пояснение под списком. Возвращает значение
/// варианта или `null`, если лист закрыли.
Future<T?> showOptionSheet<T>(
  BuildContext context, {
  required String title,
  required List<OptionSheetItem<T>> items,
  T? selected,
  String? footer,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (context) => _OptionSheet<T>(
      title: title,
      items: items,
      selected: selected,
      footer: footer,
    ),
  );
}

class _OptionSheet<T> extends StatelessWidget {
  const _OptionSheet({
    required this.title,
    required this.items,
    required this.selected,
    required this.footer,
  });

  final String title;

  /// Пояснение под списком (мелко, приглушённо); `null` — без него.
  final String? footer;
  final List<OptionSheetItem<T>> items;
  final T? selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.l,
            0,
            AppSpacing.l,
            AppSpacing.s,
          ),
          child: Semantics(
            header: true,
            child: Text(title, style: theme.textTheme.titleMedium),
          ),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [for (final item in items) _row(context, item)],
          ),
        ),
        if (footer case final text?)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.l,
              AppSpacing.s,
              AppSpacing.l,
              AppSpacing.l,
            ),
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }

  Widget _row(BuildContext context, OptionSheetItem<T> item) {
    final theme = Theme.of(context);
    final isSelected = selected != null && item.value == selected;
    void pick() => Navigator.of(context).pop(item.value);
    return Semantics(
      button: true,
      selected: isSelected ? true : null,
      label: item.subtitle == null
          ? item.title
          : '${item.title}, ${item.subtitle}',
      excludeSemantics: true,
      onTap: pick,
      child: InkWell(
        onTap: pick,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.l,
              vertical: AppSpacing.s,
            ),
            child: Row(
              children: [
                if (item.leading case final leading?) ...[
                  leading,
                  const SizedBox(width: AppSpacing.m),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.title, style: theme.textTheme.bodyLarge),
                      if (item.subtitle case final sub?)
                        Text(
                          sub,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                if (isSelected)
                  Icon(Icons.check, color: theme.colorScheme.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
