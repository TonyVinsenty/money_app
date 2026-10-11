import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:money_app/core/ui/theme/app_spacing.dart';

/// Подставляется вместо суммы внутри фраз, когда суммы скрыты.
const maskedMoneyText = '\u2022\u2022\u2022';

/// Что говорит скринридер вместо скрытой суммы.
const hiddenAmountLabel = 'сумма скрыта';

/// Раздаёт вниз по дереву флаг «суммы скрыты» (настройка «Скрыть суммы»).
/// Без него выше по дереву суммы показываются.
class AmountsVisibility extends InheritedWidget {
  const AmountsVisibility({
    required this.hidden,
    required super.child,
    super.key,
  });

  final bool hidden;

  /// Скрыты ли суммы для [context]; виджет перестроится при смене флага.
  static bool hiddenOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AmountsVisibility>()?.hidden ??
      false;

  @override
  bool updateShouldNotify(AmountsVisibility oldWidget) =>
      oldWidget.hidden != hidden;
}

/// [money] или [maskedMoneyText], если суммы скрыты: для сумм внутри фраз.
String maskedMoney(BuildContext context, String money) =>
    AmountsVisibility.hiddenOf(context) ? maskedMoneyText : money;

/// [spoken] или [hiddenAmountLabel], если суммы скрыты: для озвучки.
String maskedSpoken(BuildContext context, String spoken) =>
    AmountsVisibility.hiddenOf(context) ? hiddenAmountLabel : spoken;

/// Текст суммы. Когда суммы скрыты, вместо цифр — «облачко»: размытое пятно
/// цвета текста одной ширины для любой суммы (длина числа не выдаётся),
/// а скринридер говорит «сумма скрыта».
class MaskedAmount extends StatelessWidget {
  const MaskedAmount(
    this.text, {
    this.style,
    this.textAlign,
    this.semanticsLabel,
    this.maxLines,
    this.softWrap,
    this.overflow,
    super.key,
  });

  /// Передаются в [Text], когда сумма видна.
  final int? maxLines;
  final bool? softWrap;
  final TextOverflow? overflow;

  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;

  /// Озвучка суммы, когда она видна (как у [Text.semanticsLabel]).
  final String? semanticsLabel;

  /// Невидимая заготовка, по которой меряется облачко.
  static const _placeholder = '00 000';

  @override
  Widget build(BuildContext context) {
    if (!AmountsVisibility.hiddenOf(context)) {
      return Text(
        text,
        style: style,
        textAlign: textAlign,
        semanticsLabel: semanticsLabel,
        maxLines: maxLines,
        softWrap: softWrap,
        overflow: overflow,
      );
    }
    final resolved = DefaultTextStyle.of(context).style.merge(style);
    final color = resolved.color ?? Theme.of(context).colorScheme.onSurface;
    return Semantics(
      label: hiddenAmountLabel,
      excludeSemantics: true,
      child: Stack(
        children: [
          Text(
            _placeholder,
            style: resolved.copyWith(color: Colors.transparent),
            maxLines: 1,
          ),
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                child: DecoratedBox(
                  key: const ValueKey('masked-amount-cloud'),
                  decoration: ShapeDecoration(
                    color: color.withValues(alpha: 0.45),
                    shape: const StadiumBorder(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
