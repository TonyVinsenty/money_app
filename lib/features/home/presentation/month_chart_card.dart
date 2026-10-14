import 'package:flutter/material.dart';
import 'package:money_app/core/format/date_format.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/format/money_spoken.dart';
import 'package:money_app/core/format/percent_format.dart';
import 'package:money_app/core/money/currency.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/core/ui/app_card.dart';
import 'package:money_app/core/ui/async_view.dart';
import 'package:money_app/core/ui/card_header.dart';
import 'package:money_app/core/ui/category_labels.dart';
import 'package:money_app/core/ui/color_dot.dart';
import 'package:money_app/core/ui/donut_chart.dart';
import 'package:money_app/core/ui/font_scale.dart';
import 'package:money_app/core/ui/masked_amount.dart';
import 'package:money_app/core/ui/theme/app_colors.dart';
import 'package:money_app/core/ui/theme/app_spacing.dart';
import 'package:money_app/features/analytics/domain/category_totals.dart';
import 'package:money_app/features/analytics/domain/period_summary.dart';
import 'package:money_app/features/analytics/domain/shares.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/home/presentation/home_compact.dart';
import 'package:money_app/features/home/presentation/home_welcome_card.dart';
import 'package:money_app/features/home/presentation/month_summary_card.dart';
import 'package:money_app/features/settings/domain/home_balance_line.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

/// Сколько строк легенды показываем: если секторов больше, три крупнейших и
/// строка «Ещё N категорий».
const int _legendRows = 4;

/// Внутренний отступ карточки, dp, и границы размера кольца.
const double _cardPadding = 16;
const double _minRing = 160;
const double _maxRing = 360;

/// Высота строки легенды, dp, и зазор между кольцом и легендой.
const double _legendRowHeight = 28;
const double _legendGap = 8;

/// Размер кольца: как можно крупнее по ширине карточки ([viewportWidth] минус
/// её отступы), но так, чтобы вместе с карточкой итогов, заголовком и легендой
/// оно помещалось в [viewportHeight] (при крупном шрифте — только по ширине:
/// экран прокручивается). Границы 160 и 360 dp. Высоты итогов,
/// заголовка и легенды прикидываем по масштабу шрифта [textScale]. Высота
/// плашки над итогами ([bannerHeight], вместе с её отступом) известна из
/// измерения и просто вычитается; без плашки она 0.
double chartRingSize({
  required double viewportWidth,
  required double viewportHeight,
  required double textScale,
  double bannerHeight = 0,
  bool compact = false,
  bool fitHeightOnly = false,
}) {
  // Отступы карточки сверху и снизу, заголовок, зазоры и строки легенды
  // (до двух по 28 dp; при крупном шрифте элементы встают по одному;
  // в компактном режиме легенда — одна строка).
  final legendRows = compact ? 1 : (textScale >= 1.5 ? 4 : 2);
  final summary = estimateSummaryHeight(
    viewportWidth - 2 * _cardPadding,
    textScale,
  );
  // Итоги и зазор 16 между карточками.
  final reserved =
      bannerHeight +
      summary +
      16 +
      2 * _cardPadding +
      24 * textScale +
      12 +
      _legendGap +
      legendRows * _legendRowHeight +
      // Крупный шрифт: вторая строка (Т1) — под кольцом.
      (textScale >= twoLineRowScale ? AppSpacing.s + 20 * textScale : 0);
  final byWidth = viewportWidth - 2 * _cardPadding;
  // Крупный шрифт: экран всё равно прокручивается, поэтому кольцо — по
  // ширине, а не по высоте: иначе дырка мала и число в центре мелкое.
  // [fitHeightOnly] — «какое кольцо влезло бы по высоте» (для компактного
  // режима): правило крупного шрифта пропускаем.
  if (textScale >= twoLineRowScale && !fitHeightOnly) {
    return byWidth.clamp(_minRing, _maxRing);
  }
  final byHeight = viewportHeight - reserved;
  return (byWidth < byHeight ? byWidth : byHeight).clamp(_minRing, _maxRing);
}

/// Карточка «Расходы по категориям» на «Главной»: кольцо размера [ringSize] с
/// балансом месяца («Всего») в центре и легенда под ним (до 4 элементов).
/// Касание сектора показывает в центре его категорию; отпускание пальца на
/// секторе и нажатие на элемент легенды зовут [onOpenCategory] с набором id
/// категорий.
/// Неизвестная категория («Без категории») никуда не ведёт.
///
/// Потоки [transactions] (операции месяца) и [categories] (все категории,
/// включая архивные) создаёт вызывающий и держит одними и теми же.
class MonthChartCard extends StatefulWidget {
  const MonthChartCard({
    required this.transactions,
    required this.categories,
    required this.month,
    required this.ringSize,
    this.onOpenCategory,
    this.isCurrentMonth = true,
    this.currency = rubCurrencyCode,
    this.balanceLine,
    this.balanceLineKind = HomeBalanceLine.allTime,
    super.key,
  });

  /// Сумма для второй строки в центре кольца. Нет потока, `null` в нём,
  /// ожидание или ошибка - строки нет. Поток создаёт вызывающий.
  final Stream<Money?>? balanceLine;

  /// Что считает [balanceLine]: «За всё время» или «На счетах».
  final HomeBalanceLine balanceLineKind;

  /// Ключ второй строки под кольцом (крупный шрифт; для тестов раскладки).
  static const lineBelowKey = ValueKey('month-chart-line-below');

  /// Код валюты кольца (основная валюта); операции других валют в поток не
  /// приходят.
  final String currency;

  /// Показан текущий месяц: от этого зависит текст пустого состояния.
  final bool isCurrentMonth;

  /// Диаметр кольца, dp (см. [chartRingSize]).
  final double ringSize;

  final Stream<List<Transaction>> transactions;
  final Stream<List<Category>> categories;

  /// Любой день показываемого месяца.
  final DateOnly month;

  /// Выбраны категории (сектор или строка легенды): id одной категории, группы
  /// «Остальное» или всех категорий строки «Ещё N». Без колбэка строки не
  /// кнопки, а сектора только подсвечиваются.
  final ValueChanged<Set<String>>? onOpenCategory;

  @override
  State<MonthChartCard> createState() => _MonthChartCardState();
}

/// Операции вместе с месяцем, для которого их запрашивали. При смене месяца
/// на экране остаются прежние операции, пока не придут новые: границы и
/// подписи берём из этой пары, а не из [MonthChartCard.month], иначе прежние
/// операции отфильтровались бы новым месяцем и мелькнуло бы «расходов нет».
typedef _MonthData = ({
  DateOnly month,
  bool isCurrentMonth,
  String currency,
  List<Transaction> transactions,
});

class _MonthChartCardState extends State<MonthChartCard> {
  int? _highlight;
  late Stream<_MonthData> _data = _tag();

  Stream<_MonthData> _tag() {
    final month = widget.month;
    final isCurrentMonth = widget.isCurrentMonth;
    // Валюта едет вместе с операциями: после смены основной валюты старые
    // рублёвые операции не должны считаться в новой валюте.
    final currency = widget.currency;
    return widget.transactions.map(
      (transactions) => (
        month: month,
        isCurrentMonth: isCurrentMonth,
        currency: currency,
        transactions: transactions,
      ),
    );
  }

  @override
  void didUpdateWidget(MonthChartCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Новый поток — новый месяц (или репозиторий): сектор под пальцем устарел.
    if (!identical(oldWidget.transactions, widget.transactions) ||
        oldWidget.currency != widget.currency) {
      _data = _tag();
      _highlight = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Заголовок и карточка нужны всем состояниям, кроме пустого месяца (D15):
    // тот рисует свою карточку по высоте содержимого.
    Widget shell(Widget child) => AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const CardHeader('Расходы по категориям', centered: true),
          // Кольцо по центру оставшейся высоты, легенда прижата к низу.
          Expanded(child: child),
        ],
      ),
    );
    return AsyncView<_MonthData>(
      stream: _data,
      loadingBuilder: (_) => shell(const SizedBox.shrink()),
      errorBuilder: (context, error) => shell(_error(context, error)),
      dataBuilder: (context, data) => AsyncView<List<Category>>(
        stream: widget.categories,
        loadingBuilder: (_) => shell(const SizedBox.shrink()),
        errorBuilder: (context, error) => shell(_error(context, error)),
        dataBuilder: (context, categories) =>
            _content(context, data, categories, shell),
      ),
    );
  }

  Widget _error(BuildContext context, Object error) {
    final theme = Theme.of(context);
    return Center(
      child: Row(
        children: [
          Icon(Icons.error_outline, color: theme.colorScheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Не удалось посчитать расходы по категориям',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _content(
    BuildContext context,
    _MonthData data,
    List<Category> categories,
    Widget Function(Widget child) shell,
  ) {
    final transactions = data.transactions;
    final month = data.month;
    final theme = Theme.of(context);
    final colors = context.appColors;
    final range = monthRange(month);
    // Месяц без единой операции: серое кольцо 0,00 ₽ ничего не говорит,
    // хватает короткой строки (У4). Вторая строка («За всё время», «На
    // счетах») остаётся: 1-го числа она по-прежнему нужна.
    if (!transactions.any(
      (t) => range.contains(t.occurredOn) && t.amount.currency == data.currency,
    )) {
      final muted = theme.colorScheme.onSurfaceVariant;
      // Без заголовка и растягивания: карточка ровно по тексту, вверху места.
      Widget emptyWith(Money? line) => Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: double.infinity,
          child: AppCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  homeEmptyMonthText(
                    month,
                    isCurrentMonth: data.isCurrentMonth,
                  ),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(color: muted),
                ),
                if (line != null) ...[
                  const SizedBox(height: AppSpacing.s),
                  MergeSemantics(
                    child: Text(
                      '${_lineLabel()}: ${maskedMoney(context, _lineText(line))}',
                      textAlign: TextAlign.center,
                      semanticsLabel:
                          '${_lineLabel()}: '
                          '${maskedSpoken(context, _spokenLine(line))}',
                      style: theme.textTheme.titleSmall?.copyWith(color: muted),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
      final lineStream = widget.balanceLine;
      return lineStream == null
          ? emptyWith(null)
          : StreamBuilder<Money?>(
              stream: lineStream,
              builder: (context, snapshot) =>
                  emptyWith(snapshot.hasError ? null : snapshot.data),
            );
    }
    final balance = summarizePeriod(
      transactions,
      range,
      currency: data.currency,
    ).balance;
    final slices = chartSlices(
      totalsByCategory(
        transactions,
        range,
        type: TransactionType.expense,
        currency: data.currency,
      ),
    );
    final byId = {for (final c in categories) c.id: c};
    final names = {for (final c in categories) c.id: c.name};
    final open = widget.onOpenCategory;
    // Категории сектора; null — неизвестная категория («Без категории»).
    Set<String>? idsOf(ChartSlice s) {
      if (s.isOther) return s.categoryIds.toSet();
      final id = s.categoryIds.single;
      return byId.containsKey(id) ? {id} : null;
    }

    final items = _legendItems(
      slices,
      names,
      colors,
      onTap: open == null
          ? null
          : (s) {
              final ids = idsOf(s);
              return ids == null ? null : () => open(ids);
            },
      onTapRest: open == null
          ? null
          : () => open(legendRestCategoryIds(slices)),
    );
    // Номер мог устареть, если данные обновились во время касания.
    final lit = _highlight;
    final highlighted = lit != null && lit < slices.length ? lit : null;

    final side = widget.ringSize;
    final twoLine = useTwoLineRows(context);
    final lineStyle = theme.textTheme.titleSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    // Квадрат с жёсткими сторонами: карточка на «Главной» тянется по
    // intrinsic-высоте содержимого, а при одной лишь ширине кольцо мерилось бы
    // по всей ширине карточки, и экран прокручивался бы зря.
    Widget ringWith(Money? line) {
      final label =
          'Диаграмма расходов за ${formatMonthName(month)}. '
          '${_topLabel(month)}: '
          '${maskedSpoken(context, _spokenSigned(balance))}'
          '${line == null ? '' : '. ${_lineLabel()}: '
                    '${maskedSpoken(context, _spokenLine(line))}'}';
      return SizedBox.square(
        dimension: side,
        child: DonutChart(
          segments: [
            for (var i = 0; i < slices.length; i++)
              DonutSegment(
                weight: slices[i].amount.minorUnits,
                color: _sliceColor(slices[i], i, colors),
              ),
          ],
          highlightedIndex: highlighted,
          onHighlight: (index) => setState(() => _highlight = index),
          onSelect: open == null
              ? null
              : (index) {
                  if (index >= slices.length) return;
                  final ids = idsOf(slices[index]);
                  if (ids != null) open(ids);
                },
          semanticsLabel: label,
          center: SizedBox(
            width: side * 0.66,
            child: highlighted == null
                ? _totalCenter(
                    context,
                    theme,
                    colors,
                    month,
                    balance,
                    // Крупный шрифт: в центре одно число (с подписью
                    // «За октябрь», иначе его легко принять за доход),
                    // вторая строка — под кольцом.
                    twoLine ? null : line,
                  )
                : _sliceCenter(
                    theme,
                    slices[highlighted],
                    slices[highlighted].isOther
                        ? 'Остальное'
                        : names[slices[highlighted].categoryIds.single] ??
                              noCategoryLabel,
                  ),
          ),
        ),
      );
    }

    // Строка «Баланс» приходит отдельным потоком: пока данных нет, при ошибке
    // и при null кольцо рисуется без неё.
    // Крупный шрифт: строка — под кольцом в полный размер. Скринридер её уже
    // слышит в описании кольца, второй раз не читает.
    Widget ringBlock(Money? line) {
      if (!twoLine || line == null) return ringWith(line);
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ringWith(line),
          const SizedBox(height: AppSpacing.s),
          // Подпись и сумма — отдельно: не влезают в строку — сумма уходит
          // под подпись целиком; шире всей строки — уменьшается, но не рвётся.
          ExcludeSemantics(
            child: Wrap(
              key: MonthChartCard.lineBelowKey,
              alignment: WrapAlignment.center,
              spacing: AppSpacing.xs,
              children: [
                Text('${_lineLabel()}:', style: lineStyle),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    maskedMoney(context, _lineText(line)),
                    style: lineStyle,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final balanceStream = widget.balanceLine;
    final ring = balanceStream == null
        ? ringBlock(null)
        : StreamBuilder<Money?>(
            stream: balanceStream,
            builder: (context, snapshot) =>
                ringBlock(snapshot.hasError ? null : snapshot.data),
          );

    final Widget legend = items.isEmpty
        ? Text(
            data.isCurrentMonth
                ? 'В этом месяце расходов пока нет'
                : 'За ${formatMonthName(month)} ${month.year} '
                      'расходов нет',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        : isCompactHome(context)
        ? _CompactLegend(items: items)
        : Wrap(
            alignment: WrapAlignment.center,
            spacing: 16,
            children: [for (final item in items) _LegendItemView(item: item)],
          );

    return shell(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: Center(child: ring)),
          const SizedBox(height: _legendGap),
          legend,
        ],
      ),
    );
  }

  /// Подпись над числом: «За октябрь» (месяц в винительном падеже совпадает с
  /// именительным).
  String _topLabel(DateOnly month) => 'За ${formatMonthName(month)}';

  /// Подпись второй строки: «За всё время» или «На счетах».
  String _lineLabel() => widget.balanceLineKind == HomeBalanceLine.accounts
      ? 'На счетах'
      : 'За всё время';

  /// «На счетах» - остаток без знака, «За всё время» - со знаком.
  String _lineText(Money line) =>
      widget.balanceLineKind == HomeBalanceLine.accounts
      ? formatMoney(line)
      : _signedText(line);

  String _spokenLine(Money line) =>
      widget.balanceLineKind == HomeBalanceLine.accounts
      ? spokenMoney(line)
      : _spokenSigned(line);

  /// Центр без подсветки: «За октябрь» и баланс месяца (доходы минус расходы).
  /// Цвет и знак только у суммы: плюс цветом дохода, минус цветом расхода, ноль
  /// нейтрально.
  ///
  /// Под ними - мельче - строка «За всё время: …» или «На счетах: …» ([line]),
  /// если она есть.
  Widget _totalCenter(
    BuildContext context,
    ThemeData theme,
    AppColors colors,
    DateOnly month,
    Money balance,
    Money? line,
  ) {
    final color = balance.isZero
        ? null
        : balance.isNegative
        ? colors.expense
        : colors.income;
    final text = _signedText(balance);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _fit(
          Text(
            _topLabel(month),
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        _fit(
          MaskedAmount(
            text,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(color: color),
          ),
        ),
        if (line != null)
          _fit(
            Text(
              '${_lineLabel()}: ${maskedMoney(context, _lineText(line))}',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }

  /// Сумма с «+» для плюса (минус даёт formatMoney, ноль без знака).
  String _signedText(Money m) =>
      m.isZero || m.isNegative ? formatMoney(m) : '+${formatMoney(m)}';

  /// spokenMoney сам добавляет «минус»; для плюса приставку ставим тут.
  String _spokenSigned(Money m) =>
      m > Money.zero(m.currency) ? 'плюс ${spokenMoney(m)}' : spokenMoney(m);

  /// Строка в дырке кольца: длинная сумма уменьшается, а не вылезает.
  Widget _fit(Widget child) => FittedBox(fit: BoxFit.scaleDown, child: child);

  /// Центр при подсветке сектора: название, сумма и процент, всё нейтрально.
  Widget _sliceCenter(ThemeData theme, ChartSlice slice, String name) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium,
        ),
        _fit(
          MaskedAmount(
            formatMoney(slice.amount),
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
        ),
        _fit(
          Text(
            _percentText(slice.share),
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// Строка легенды: цвет метки, подпись, сумма и доля.
class _LegendItem {
  const _LegendItem(
    this.label,
    this.amount,
    this.share,
    this.color, [
    this.onTap,
    this.compactLabel,
  ]);

  final String label;

  /// Короткая подпись для компактной легенды («Ещё 8»); null — как [label].
  final String? compactLabel;
  final Money amount;
  final PercentShare share;
  final Color color;

  /// Нажатие на строку; null — строка не кнопка.
  final VoidCallback? onTap;
}

/// Цвет сектора: по месту в палитре, «Остальное» — серый.
Color _sliceColor(ChartSlice slice, int index, AppColors colors) =>
    slice.isOther
    ? colors.chartOther
    : colors.chartPalette[index % colors.chartPalette.length];

List<_LegendItem> _legendItems(
  List<ChartSlice> slices,
  Map<String, String> names,
  AppColors colors, {
  VoidCallback? Function(ChartSlice slice)? onTap,
  VoidCallback? onTapRest,
}) {
  _LegendItem of(int i) {
    final s = slices[i];
    return _LegendItem(
      s.isOther ? 'Остальное' : names[s.categoryIds.single] ?? noCategoryLabel,
      s.amount,
      s.share,
      _sliceColor(s, i, colors),
      onTap?.call(s),
    );
  }

  if (slices.length <= _legendRows) {
    return [for (var i = 0; i < slices.length; i++) of(i)];
  }
  final rest = slices.sublist(_legendRows - 1);
  var count = 0;
  var percent = 0;
  var amount = Money.zero(rest.first.amount.currency);
  for (final s in rest) {
    count += s.categoryIds.length;
    percent += s.share.percent ?? 0;
    amount += s.amount;
  }
  return [
    for (var i = 0; i < _legendRows - 1; i++) of(i),
    _LegendItem(
      'Ещё $count ${pluralRu(count, 'категория', 'категории', 'категорий')}',
      amount,
      PercentShare(
        percent: percent,
        isBelowOne: amount.minorUnits > 0 && percent == 0,
      ),
      colors.chartOther,
      onTapRest,
      'Ещё $count',
    ),
  ];
}

/// Категории, не показанные отдельными элементами легенды (все секторы после
/// первых трёх, включая категории «Остального»): их открывает строка
/// «Ещё N категорий». Если секторов не больше [_legendRows], строки нет и
/// набор пуст.
Set<String> legendRestCategoryIds(List<ChartSlice> slices) {
  if (slices.length <= _legendRows) return {};
  return {for (final s in slices.skip(_legendRows - 1)) ...s.categoryIds};
}

/// Легенда компактного режима (D3): «Дом 43 % · Займы 31 % · Ещё 8». Строка
/// переносится целыми элементами, а не уходит за край; точки между элементами
/// скринридер не читает, сами элементы озвучены как в обычной легенде.
class _CompactLegend extends StatelessWidget {
  const _CompactLegend({required this.items});

  final List<_LegendItem> items;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0)
            ExcludeSemantics(
              child: Text('·', style: TextStyle(color: muted)),
            ),
          _LegendItemView(item: items[i], compact: true),
        ],
      ],
    );
  }
}

class _LegendItemView extends StatelessWidget {
  const _LegendItemView({required this.item, this.compact = false});

  final _LegendItem item;

  /// Компактный вид: без цветной метки, одной подписью «Дом 43 %».
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onTap = item.onTap;
    final short = item.compactLabel;
    // Wrap даёт элементу не больше своей ширины: длинное название обрезается
    // многоточием, процент остаётся целым.
    final content = compact
        ? Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              short ?? '${item.label} ${_percentText(item.share)}',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          )
        : Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ColorDot(color: item.color),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _percentText(item.share),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          );
    // Строки очень компактные (28 dp): ниже рекомендованных 48 dp, зато легенда
    // не рыхлая; кольцо и сектора нажимаются тоже.
    final box = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: _legendRowHeight),
      child: Center(widthFactor: 1, child: content),
    );
    return Semantics(
      // container: каждый элемент — отдельный узел, а не слитый с соседями.
      container: true,
      label:
          '${item.label}, ${maskedSpoken(context, spokenMoney(item.amount))}, '
          '${_percentSpoken(item.share)}',
      button: onTap != null,
      onTap: onTap,
      excludeSemantics: true,
      child: onTap == null
          ? box
          : InkWell(onTap: onTap, borderRadius: AppRadius.borderM, child: box),
    );
  }
}

String _percentText(PercentShare share) =>
    formatPercent(share.percent ?? 0, isBelowOne: share.isBelowOne);

String _percentSpoken(PercentShare share) =>
    spokenPercent(share.percent ?? 0, isBelowOne: share.isBelowOne);
