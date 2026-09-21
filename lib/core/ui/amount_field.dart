import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:money_app/core/format/money_spoken.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/money/parse_amount.dart';
import 'package:money_app/core/ui/amount_failure_text.dart';
import 'package:money_app/core/ui/amount_input_formatter.dart';
import 'package:money_app/core/ui/theme/app_colors.dart';

/// Настоящий минус (U+2212), а не дефис. Собран из кода, чтобы в исходнике не
/// было символа, который легко спутать с обычным «-».
final String _minusSign = String.fromCharCode(0x2212);

const String _currencySymbol = '₽';

/// Состояние поля суммы: текст, результат разбора и «была ли попытка продолжить».
///
/// Зачем отдельный объект, а не просто `TextEditingController`: ошибку
/// «Введите сумму» нельзя показывать, пока человек не пробовал продолжить, а
/// эту «попытку» делает не только сам виджет (клавиша «Далее» на клавиатуре), но
/// и кнопка на экране снаружи. Экран держит один [AmountFieldController], вызывает
/// [submit] из кнопки, а виджет [AmountField] перерисовывается сам.
///
/// Экран, который владеет контроллером, обязан вызвать [dispose].
class AmountFieldController extends ChangeNotifier {
  AmountFieldController() {
    text.addListener(notifyListeners);
  }

  // Пока везде рубль ([rubCurrencyCode]). Мультивалютность — позже: тогда
  // здесь снова появится код валюты, а вместо «₽» — его символ.

  /// Текстовое поле внутри. Наружу отдано, чтобы можно было задать начальное
  /// значение (правка операции) или очистить поле.
  final TextEditingController text = TextEditingController();

  /// Фокус текстового поля. Нужен, чтобы тап по знаку или по «₽» тоже открывал
  /// клавиатуру (см. [AmountField]).
  final FocusNode focusNode = FocusNode();

  bool _attempted = false;

  /// Результат разбора текущего текста (без «мягкой» логики показа ошибок).
  AmountParseResult get result => parseAmount(text.text);

  /// Что показать под полем прямо сейчас: `null` — ничего.
  ///
  /// «Введите сумму» (пусто) — только после первой попытки продолжить; любая
  /// другая причина (например, слишком большая сумма) — сразу. Ноль ошибкой не
  /// считается.
  AmountParseFailure? get visibleFailure {
    final current = result;
    if (current is! AmountParseFailed) return null;
    if (current.failure == AmountParseFailure.empty && !_attempted) return null;
    return current.failure;
  }

  /// Попытка продолжить (кнопка «Далее» или клавиша на клавиатуре). Запоминает
  /// её, чтобы показать ошибку, если она есть. Возвращает сумму, если её можно
  /// продолжать, иначе `null`.
  Money? submit() {
    _attempted = true;
    notifyListeners();
    final current = result;
    return current is AmountParsed ? current.amount : null;
  }

  @override
  void dispose() {
    text.removeListener(notifyListeners);
    text.dispose();
    focusNode.dispose();
    super.dispose();
  }
}

/// Крупное поле ввода суммы: главный элемент экрана быстрого ввода.
///
/// - знак «−»/«+» и цвет (из темы) показывают направление; смысл не только в
///   цвете;
/// - число, знак и «₽» лежат в `FittedBox(scaleDown)`: длинная сумма при крупном
///   системном шрифте уменьшается, а не вылезает за экран;
/// - ошибка выводится текстом под полем, дословно из [amountFailureMessage];
/// - скринридер читает сумму прописью («Расход 1234 рубля 50 копеек»), а пока
///   поле пусто или введено неразборчиво — «Сумма расхода» без озвучки мусора.
///
/// Лежит в `core/ui`, потому что нужен и быстрому вводу, и правке операции.
/// Направление передаётся признаком [isIncome], а не `TransactionType`: `core/ui`
/// не должен зависеть от фичи (ADR 0002).
class AmountField extends StatelessWidget {
  const AmountField({
    required this.controller,
    required this.isIncome,
    this.onSubmitted,
    this.autofocus = false,
    super.key,
  });

  final AmountFieldController controller;

  /// `true` — доход («+», цвет дохода), `false` — расход («−», цвет расхода).
  final bool isIncome;

  /// Вызывается, когда человек нажал «Далее» на клавиатуре и сумма разобрана.
  final ValueChanged<Money>? onSubmitted;

  /// Открывать ли клавиатуру сразу при показе экрана.
  final bool autofocus;

  String _semanticLabel(AmountParseResult result) {
    final word = isIncome ? 'Доход' : 'Расход';
    if (result is AmountParsed) {
      return '$word ${spokenMoney(result.amount)}';
    }
    return isIncome ? 'Сумма дохода' : 'Сумма расхода';
  }

  double _textWidth(BuildContext context, String text, TextStyle style) {
    // Ту же основу, что и у самого TextField, чтобы ширина совпала.
    final effective =
        (Theme.of(context).textTheme.bodyLarge ?? const TextStyle()).merge(
          style,
        );
    final painter = TextPainter(
      text: TextSpan(text: text, style: effective),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  /// Тап по любой части строки суммы (знак, число, «₽», пустое место): ставит
  /// фокус в поле и снова показывает клавиатуру. Второе нужно, когда клавиатуру
  /// закрыли жестом «Назад»: фокус остался, и просто `requestFocus()` ничего бы
  /// не показал.
  void _focusField() {
    controller.focusNode.requestFocus();
    unawaited(SystemChannels.textInput.invokeMethod<void>('TextInput.show'));
  }

  void _handleEditingComplete() {
    final amount = controller.submit();
    if (amount != null) onSubmitted?.call(amount);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = isIncome
        ? context.appColors.income
        : context.appColors.expense;
    final style = theme.textTheme.displayMedium!.copyWith(
      color: accent,
      fontWeight: FontWeight.w600,
    );

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final text = controller.text.text;
        final failure = controller.visibleFailure;
        // Ширину поля подгоняем под текст: FittedBox нужна конечная ширина,
        // чтобы знать, во сколько раз сжимать. Запас на курсор.
        final fieldWidth =
            _textWidth(context, text.isEmpty ? '0' : text, style) + 8;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Область нажатия вокруг всей строки суммы, не ниже 48 dp. Свой
            // тап-обработчик не попадает в дерево семантики: скринридер видит
            // только само поле.
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              excludeFromSemantics: true,
              onTap: _focusField,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Знак и валюта — для глаз; скринридер читает подпись поля.
                        ExcludeSemantics(
                          child: Text(
                            isIncome ? '+' : _minusSign,
                            style: style,
                          ),
                        ),
                        SizedBox(
                          width: fieldWidth,
                          child: Stack(
                            alignment: Alignment.centerLeft,
                            children: [
                              // Бледный «0» пока пусто. Нарисован сам, а не через
                              // hintText: подсказка поля попала бы в подпись для
                              // скринридера. Прозрачность 0,4, чтобы «0» не
                              // выглядел как введённое значение.
                              if (text.isEmpty)
                                ExcludeSemantics(
                                  child: IgnorePointer(
                                    child: Text(
                                      '0',
                                      style: style.copyWith(
                                        color: theme
                                            .colorScheme
                                            .onSurfaceVariant
                                            .withValues(alpha: 0.4),
                                      ),
                                    ),
                                  ),
                                ),
                              Semantics(
                                label: _semanticLabel(controller.result),
                                child: TextField(
                                  controller: controller.text,
                                  focusNode: controller.focusNode,
                                  autofocus: autofocus,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  textInputAction: TextInputAction.next,
                                  inputFormatters: const [
                                    AmountInputFormatter(),
                                  ],
                                  // Свой обработчик вместо стандартного: клавиатура
                                  // остаётся открытой, если сумма не прошла проверку.
                                  onEditingComplete: _handleEditingComplete,
                                  maxLines: 1,
                                  style: style,
                                  cursorColor: accent,
                                  decoration: const InputDecoration.collapsed(
                                    hintText: null,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        ExcludeSemantics(
                          child: Text(_currencySymbol, style: style),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (failure != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    amountFailureMessage(failure),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
