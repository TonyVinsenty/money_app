import 'package:flutter/material.dart';
import 'package:money_app/core/ui/theme/app_spacing.dart';

/// Поле «выбрать значение» (D6): подпись в рамке сверху, внутри аватар или
/// значок и значение, справа шеврон. Рамка и цвета - из темы полей ввода.
/// Нажатие открывает выбор (его делает вызывающий код).
///
/// Скринридер читает одну фразу «Подпись: значение» как кнопку; если нужна
/// другая - [semanticsLabel]. Длинное значение переносится на строки, не
/// обрезается (крупный шрифт).
class PickerField extends StatelessWidget {
  const PickerField({
    required this.label,
    required this.value,
    required this.onTap,
    this.leading,
    this.errorText,
    this.hasError = false,
    this.semanticsLabel,
    super.key,
  });

  /// Подпись в рамке («Категория»).
  final String label;

  /// Выбранное значение («Кафе»).
  final String value;
  final VoidCallback onTap;

  /// Аватар или значок слева; `null` - без него.
  final Widget? leading;

  /// Текст ошибки под полем; рамка и значение становятся красными.
  final String? errorText;

  /// Красная рамка и значение без текста под полем (текст ошибки уже есть
  /// на экране в другом месте).
  final bool hasError;

  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = errorText;
    final failed = hasError || error != null;
    final spoken =
        semanticsLabel ??
        (error == null ? '$label: $value' : '$label: $value, $error');
    return Semantics(
      button: true,
      label: spoken,
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.borderM,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            floatingLabelBehavior: FloatingLabelBehavior.always,
            errorText: error,
            error: error == null && hasError ? const SizedBox.shrink() : null,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.m,
              vertical: AppSpacing.m,
            ),
          ),
          child: Row(
            children: [
              if (leading case final leading?) ...[
                leading,
                const SizedBox(width: AppSpacing.m),
              ],
              Expanded(
                child: Text(
                  value,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: failed ? theme.colorScheme.error : null,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.s),
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
