import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:money_app/core/money/currency.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/font_scale.dart';
import 'package:money_app/core/ui/theme/app_spacing.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/home/presentation/home_compact.dart';
import 'package:money_app/features/home/presentation/home_welcome_card.dart';
import 'package:money_app/features/home/presentation/month_chart_card.dart';
import 'package:money_app/features/home/presentation/month_summary_card.dart';
import 'package:money_app/features/settings/domain/home_balance_line.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';

/// Главный экран: итоги расходов и доходов за месяц и диаграмма по категориям.
///
/// Кнопки «Доход» и «Расход» сюда не входят: они лежат в HomeActionBar над
/// нижней панелью, которую ставит каркас приложения (иначе сообщение SnackBar
/// закрывало бы их).
///
/// Экран не знает, куда ведут нажатия и откуда берутся суммы: об этом знает
/// только приложение (`lib/app`), которое передаёт [onOpenCategory] и потоки.
/// Так фича `home` не зависит от маршрутов, репозиториев и других экранов
/// (ADR 0002).
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    required this.monthExpenses,
    required this.monthIncome,
    required this.monthTransactions,
    required this.categories,
    required this.month,
    required this.onOpenCategory,
    this.isCurrentMonth = true,
    this.onPreviousMonth,
    this.onNextMonth,
    this.currency = rubCurrencyCode,
    this.balanceLine,
    this.balanceLineKind = HomeBalanceLine.allTime,
    this.banner,
    this.hideAmounts = false,
    this.onHideAmountsChanged,
    this.hasAnyTransactions,
    super.key,
  });

  /// Затухание над кнопками на коротком экране, когда есть что прокручивать.
  static const bottomFadeKey = ValueKey('home-bottom-fade');

  /// Есть ли в базе хоть одна операция; `false` — вместо итогов и кольца
  /// приветствие, `null` — пока неизвестно (экран как обычно).
  final bool? hasAnyTransactions;

  /// Суммы скрыты ли сейчас и как это переключить («глаз» в карточке итогов).
  /// Без обработчика значка нет.
  final bool hideAmounts;
  final ValueChanged<bool>? onHideAmountsChanged;

  /// Какая это вторая строка в кольце («За всё время» или «На счетах»).
  final HomeBalanceLine balanceLineKind;

  /// Плашка над итогами (например, «К оплате»), которую собирает приложение.
  /// Сама должна быть нулевой высоты, когда показывать нечего; `null` - слота
  /// нет совсем.
  final Widget? banner;

  /// Сумма для строки «Баланс» в центре кольца; `null` в потоке или нет
  /// потока - строки нет. Поток один и тот же между перерисовками.
  final Stream<Money?>? balanceLine;

  /// Код основной валюты: в ней кольцо считает операции [monthTransactions].
  final String currency;

  /// Показан текущий месяц (для текста пустой диаграммы).
  final bool isCurrentMonth;

  /// Стрелки переключателя месяца; `null` — стрелка недоступна. Откуда берётся
  /// месяц, экран не знает: это решает приложение (`lib/app`, ADR 0002).
  final VoidCallback? onPreviousMonth;
  final VoidCallback? onNextMonth;

  /// Выбраны категории на диаграмме или в легенде (id одной категории или
  /// группы): приложение показывает их расходы за [month] в «Истории».
  final ValueChanged<Set<String>> onOpenCategory;

  /// Итог расходов за [month]. Поток должен быть один и тот же между
  /// перерисовками (его создаёт вызывающий), иначе подписка начнётся заново.
  final Stream<Money> monthExpenses;

  /// Итог доходов за [month]; те же правила, что у [monthExpenses].
  final Stream<Money> monthIncome;

  /// Операции за [month] для диаграммы (те же правила про поток).
  final Stream<List<Transaction>> monthTransactions;

  /// Все категории, включая архивные: из них берутся названия в легенде.
  final Stream<List<Category>> categories;

  /// Любой день показываемого месяца: из него берётся название месяца.
  final DateOnly month;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// Измеренная высота плашки (0, когда её нет или она пустая).
  double _bannerHeight = 0;

  void _onBannerHeight(double height) {
    if (!mounted || height == _bannerHeight) return;
    setState(() => _bannerHeight = height);
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final banner = w.banner;
    return Padding(
      // Снизу — место под кнопками и нижней панелью: каркас кладёт их поверх
      // экрана (Scaffold.extendBody) и сообщает их высоту через MediaQuery.
      padding: EdgeInsets.fromLTRB(
        AppSpacing.l,
        AppSpacing.l,
        AppSpacing.l,
        MediaQuery.paddingOf(context).bottom,
      ),
      // Середина прокручивается: при крупном шрифте на маленьком экране она
      // уступает место панели кнопок, а не вызывает переполнение.
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Кольцо как можно крупнее, но не выше видимой области (итоги выше
          // при этом прокручиваются).
          final ring = chartRingSize(
            viewportWidth: constraints.maxWidth,
            viewportHeight: constraints.maxHeight,
            textScale: fontScaleOf(context),
            bannerHeight: banner == null ? 0 : _bannerHeight,
            compact: isCompactHome(context),
            // Компактный режим: кольцо по высоте, а не по ширине (иначе при
            // крупном шрифте видна половина кольца).
            fitHeightOnly: isCompactHome(context),
          );
          final scroll = CustomScrollView(
            slivers: [
              // Плашка сообщает свою высоту (при крупном шрифте она в 2-3
              // строки): кольцо уступает ей место.
              if (banner != null)
                SliverToBoxAdapter(
                  child: _HeightReporter(
                    onHeight: _onBannerHeight,
                    child: banner,
                  ),
                ),
              if (w.hasAnyTransactions == false)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: AppSpacing.l),
                    child: HomeWelcomeCard(),
                  ),
                )
              else ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: MonthSummaryCard(
                      expenses: w.monthExpenses,
                      income: w.monthIncome,
                      month: w.month,
                      onPreviousMonth: w.onPreviousMonth,
                      onNextMonth: w.onNextMonth,
                      hideAmounts: w.hideAmounts,
                      onHideAmountsChanged: w.onHideAmountsChanged,
                    ),
                  ),
                ),
                // Карточка кольца занимает остаток высоты до панели кнопок; если
                // содержимое выше остатка, она растёт и середина прокручивается.
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: MonthChartCard(
                    transactions: w.monthTransactions,
                    categories: w.categories,
                    month: w.month,
                    isCurrentMonth: w.isCurrentMonth,
                    currency: w.currency,
                    balanceLine: w.balanceLine,
                    balanceLineKind: w.balanceLineKind,
                    ringSize: ring,
                    onOpenCategory: w.onOpenCategory,
                  ),
                ),
              ],
            ],
          );
          // Короткий экран: если низ карточки ещё прокручивается, над кнопками
          // видно затухание — подсказка, что там есть продолжение (D3).
          return isCompactHome(context) ? _FadeAtBottom(child: scroll) : scroll;
        },
      ),
    );
  }
}

/// Показывает затухание (градиент к фону) у нижней кромки [child], пока
/// прокрутка не дошла до конца.
class _FadeAtBottom extends StatefulWidget {
  const _FadeAtBottom({required this.child});

  final Widget child;

  @override
  State<_FadeAtBottom> createState() => _FadeAtBottomState();
}

class _FadeAtBottomState extends State<_FadeAtBottom> {
  /// Высота затухания, dp.
  static const fadeHeight = 24.0;

  bool _more = false;

  bool _onMetrics(ScrollMetrics m) {
    final more = m.extentAfter > 0.5;
    if (more != _more) setState(() => _more = more);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).scaffoldBackgroundColor;
    return Stack(
      children: [
        NotificationListener<ScrollMetricsNotification>(
          onNotification: (n) => _onMetrics(n.metrics),
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) => _onMetrics(n.metrics),
            child: widget.child,
          ),
        ),
        if (_more)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: fadeHeight,
            child: IgnorePointer(
              child: DecoratedBox(
                key: HomeScreen.bottomFadeKey,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [bg.withValues(alpha: 0), bg],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Обёртка, которая после раскладки сообщает высоту [child] (после кадра,
/// чтобы не менять состояние во время раскладки).
class _HeightReporter extends SingleChildRenderObjectWidget {
  const _HeightReporter({required this.onHeight, required super.child});

  final ValueChanged<double> onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderHeightReporter(onHeight);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderHeightReporter renderObject,
  ) {
    renderObject.onHeight = onHeight;
  }
}

class _RenderHeightReporter extends RenderProxyBox {
  _RenderHeightReporter(this.onHeight);

  ValueChanged<double> onHeight;
  double? _last;

  @override
  void performLayout() {
    super.performLayout();
    final height = size.height;
    if (height == _last) return;
    _last = height;
    SchedulerBinding.instance.addPostFrameCallback((_) => onHeight(height));
  }
}
