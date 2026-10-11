import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:money_app/core/ui/theme/app_spacing.dart';

/// Описание одной вкладки нижней панели: подпись, две иконки и содержимое.
@immutable
class AppTab {
  const AppTab({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.builder,
    this.actionsBuilder,
    this.decorateIcon,
  });

  /// Необязательная обёртка значка вкладки (например, кружок с числом).
  /// Применяется к обеим иконкам; строится заново с каркасом, поэтому сама
  /// обёртка должна слушать свой источник данных.
  final Widget Function(BuildContext context, Widget icon)? decorateIcon;

  final String label;

  /// Иконка невыбранной вкладки.
  final IconData icon;

  /// Иконка выбранной вкладки (обычно закрашенный вариант).
  final IconData selectedIcon;

  /// Строит содержимое вкладки. Своего `Scaffold` внутри быть не должно:
  /// он один, в [AppShell].
  ///
  /// Строитель вызывается ОДИН раз, при первом открытии вкладки, и получает
  /// контекст каркаса; построенный виджет затем кэшируется. Поэтому данные из
  /// `AppScope`, `Theme`, `MediaQuery`, локали нужно читать в собственном
  /// `build` виджета вкладки, а не в замыкании строителя: иначе прочитанное
  /// «замрёт» и не обновится при смене темы, языка или сервисов.
  ///
  /// ```dart
  /// // Правильно: виджет сам читает AppScope в своём build.
  /// builder: (_) => const HomeTab(),
  /// // class HomeTab ... build(context) { AppScope.of(context)... }
  ///
  /// // Неправильно: значение прочитано один раз и «замёрзло».
  /// builder: (context) => HomeTab(services: AppScope.of(context)),
  /// ```
  final WidgetBuilder builder;

  /// Необязательная панель действий над нижней навигацией, пока вкладка
  /// выбрана (на «Главной» — кнопки «Доход» и «Расход»). Строится при каждой
  /// перерисовке каркаса, поэтому лучше возвращать маленький виджет, который
  /// сам читает всё нужное в своём `build`.
  final WidgetBuilder? actionsBuilder;
}

/// Каркас приложения: содержимое выбранной вкладки и нижняя панель навигации.
class AppShell extends StatefulWidget {
  // Конструктор не const: длину списка нельзя проверить на этапе компиляции.
  // Проверка явная (не assert), чтобы работала и в релизной сборке.
  AppShell({required this.tabs, this.selectedTab, super.key}) {
    if (tabs.length < 3 || tabs.length > 5) {
      throw ArgumentError.value(
        tabs.length,
        'tabs',
        'NavigationBar в Material поддерживает от 3 до 5 вкладок',
      );
    }
  }

  final List<AppTab> tabs;

  /// Необязательный внешний уведомитель номера вкладки: каркас берёт номер
  /// из него и пишет в него же, так что вкладку можно переключить снаружи
  /// (ADR 0008). Без него номер хранит сам каркас. Освобождает уведомитель
  /// тот, кто его создал.
  final ValueNotifier<int>? selectedTab;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _ownIndex = 0;

  int get _selectedIndex => widget.selectedTab?.value ?? _ownIndex;

  set _selectedIndex(int value) {
    final external = widget.selectedTab;
    if (external != null) {
      external.value = value;
    } else {
      _ownIndex = value;
    }
  }

  @override
  void initState() {
    super.initState();
    widget.selectedTab?.addListener(_onExternalTabChanged);
  }

  void _onExternalTabChanged() => setState(() {});

  /// Уже построенное содержимое открытых вкладок по индексу. Ключи этой карты
  /// и есть «множество открытых вкладок»: индекса нет — вкладку ещё не
  /// показывали, и её строитель не вызывался. Один и тот же виджет отдаётся
  /// в [IndexedStack] при каждой перерисовке, поэтому строитель вызывается
  /// ровно один раз на вкладку, а состояние вкладки не теряется.
  final Map<int, Widget> _openedTabs = {};

  @override
  void didUpdateWidget(AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedTab != widget.selectedTab) {
      oldWidget.selectedTab?.removeListener(_onExternalTabChanged);
      widget.selectedTab?.addListener(_onExternalTabChanged);
    }
    // Тот же набор вкладок (даже в новом списке) кэш не сбрасывает. Другой
    // набор: старые индексы указывают уже на другие вкладки, кэш забываем.
    if (!_sameTabs(oldWidget.tabs, widget.tabs)) {
      _openedTabs.clear();
      if (_selectedIndex >= widget.tabs.length) {
        _selectedIndex = widget.tabs.length - 1;
      }
    }
  }

  @override
  void dispose() {
    widget.selectedTab?.removeListener(_onExternalTabChanged);
    super.dispose();
  }

  static bool _sameTabs(List<AppTab> a, List<AppTab> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    // Выбранная вкладка строится при первом показе и дальше берётся из кэша.
    _openedTabs.putIfAbsent(
      _selectedIndex,
      () => widget.tabs[_selectedIndex].builder(context),
    );
    // «Назад» на Android: пока выбрана не «Главная», перехватываем его и
    // возвращаем на первую вкладку; на «Главной» пропускаем как обычно
    // (приложение уходит на задний план). Если поверх каркаса открыт другой
    // экран, «Назад» сначала закроет его: PopScope работает, только пока
    // каркас — верхний маршрут.
    return PopScope(
      canPop: _selectedIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        setState(() => _selectedIndex = 0);
      },
      child: _buildScaffold(),
    );
  }

  Widget _buildScaffold() {
    return Scaffold(
      // Содержимое прокручивается под капсулой (её фон размывает его). Нижний
      // отступ под капсулу Scaffold передаёт вкладкам через
      // MediaQuery.padding.bottom: ListView учитывает его сам.
      extendBody: true,
      // Верхней панели (AppBar) нет, поэтому без SafeArea содержимое уехало бы
      // под системную строку состояния. Низ не защищаем: этим занимается сама
      // NavigationBar.
      body: SafeArea(
        bottom: false,
        // IndexedStack держит в дереве все свои дочерние виджеты и показывает
        // один. Ещё не открытые вкладки — пустые заглушки, открытые — их
        // кэшированное содержимое (оно остаётся в дереве скрытым).
        child: IndexedStack(
          index: _selectedIndex,
          children: [
            for (var i = 0; i < widget.tabs.length; i++)
              _openedTabs[i] ?? const SizedBox.shrink(),
          ],
        ),
      ),
      // Панель действий вкладки (если есть) лежит в том же слоте, что и
      // навигация: SnackBar Flutter ставит над слотом целиком, то есть над
      // панелью действий, и сообщение её не закрывает.
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.tabs[_selectedIndex].actionsBuilder != null)
            widget.tabs[_selectedIndex].actionsBuilder!(context),
          NavCapsule(child: _buildNavigationBar()),
        ],
      ),
    );
  }

  static Widget _decorated(BuildContext context, AppTab tab, Widget icon) =>
      tab.decorateIcon?.call(context, icon) ?? icon;

  /// Нижняя панель с подписями в одну строку. Масштаб шрифта подписей не
  /// больше [_maxLabelScale] (как у таб-бара iOS), а если самая длинная подпись
  /// всё равно шире своей вкладки, размер шрифта уменьшается, и слово не рвётся
  /// и не обрезается.
  Widget _buildNavigationBar() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final theme = Theme.of(context);
        final media = MediaQuery.of(context);
        final scaler = TextScaler.linear(
          media.textScaler.scale(1).clamp(1.0, _maxLabelScale),
        );
        final base = theme.textTheme.labelMedium ?? const TextStyle();
        final baseSize = base.fontSize ?? 12;
        // Ширина вкладки за вычетом полей по краям.
        final room = constraints.maxWidth / widget.tabs.length - 8;
        var widest = 0.0;
        for (final tab in widget.tabs) {
          final painter = TextPainter(
            text: TextSpan(text: tab.label, style: base),
            textDirection: Directionality.of(context),
            textScaler: scaler,
            maxLines: 1,
          )..layout();
          if (painter.width > widest) widest = painter.width;
          painter.dispose();
        }
        final factor = widest > room && widest > 0 ? room / widest : 1.0;
        final scheme = theme.colorScheme;
        TextStyle style(Color color) =>
            base.copyWith(fontSize: baseSize * factor, color: color);
        return MediaQuery(
          data: media.copyWith(textScaler: scaler),
          child: NavigationBarTheme(
            data: NavigationBarTheme.of(context).copyWith(
              labelTextStyle: WidgetStateProperty.resolveWith(
                (states) => style(
                  states.contains(WidgetState.selected)
                      ? scheme.onSurface
                      : scheme.onSurfaceVariant,
                ),
              ),
            ),
            child: NavigationBar(
              // Фон, тень и отступ от системной полоски даёт капсула.
              height: navCapsuleHeight,
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              selectedIndex: _selectedIndex,
              onDestinationSelected: (index) {
                setState(() => _selectedIndex = index);
              },
              destinations: [
                for (final tab in widget.tabs)
                  NavigationDestination(
                    icon: _decorated(context, tab, Icon(tab.icon)),
                    selectedIcon: _decorated(
                      context,
                      tab,
                      Icon(tab.selectedIcon),
                    ),
                    label: tab.label,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Наибольший масштаб шрифта подписей вкладок.
const double _maxLabelScale = 1.15;

/// Высота капсулы нижней панели, dp (значок с подложкой и подпись).
const double navCapsuleHeight = 64;

/// Зазор между капсулой и нижним краем (или системной полоской), dp.
const double navCapsuleGap = AppSpacing.s;

/// Размытие того, что прокручивается под капсулой.
const double _capsuleBlur = 16;

/// Непрозрачность заливки капсулы: в светлой теме капсула отделяется от
/// фона, подписи читаются и над пёстрым содержимым (ревью 7.30d).
const double _capsuleFillAlpha = 0.9;

/// Нижняя панель «стеклянная капсула» (решение пользователя 2026-10-11):
/// скругление на всю высоту, полупрозрачная заливка `surfaceContainer`,
/// размытие содержимого под ней и тонкая светлая обводка. Настоящее Liquid
/// Glass iOS 26 Flutter-у недоступно — это сознательная имитация.
class NavCapsule extends StatelessWidget {
  const NavCapsule({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final media = MediaQuery.of(context);
    const radius = BorderRadius.all(Radius.circular(navCapsuleHeight / 2));
    final background = theme.scaffoldBackgroundColor;
    // Под капсулой (зазор и системная полоска) содержимое плавно уходит в
    // цвет фона: обрывки строк не торчат между капсулой и краем экрана.
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [background.withValues(alpha: 0), background],
          stops: const [0.3, 0.75],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.l,
          0,
          AppSpacing.l,
          media.viewPadding.bottom + navCapsuleGap,
        ),
        child: DecoratedBox(
          // Мягкая тень отделяет капсулу от светлого фона.
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? 0.32 : 0.12),
                blurRadius: AppSpacing.xl,
                offset: const Offset(0, AppSpacing.xs),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: _capsuleBlur,
                sigmaY: _capsuleBlur,
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainer.withValues(
                    alpha: _capsuleFillAlpha,
                  ),
                  borderRadius: radius,
                  border: Border.all(
                    color: dark
                        ? Colors.white.withValues(alpha: 0.14)
                        : scheme.outlineVariant.withValues(alpha: 0.6),
                  ),
                ),
                // Отступ от системной полоски уже снаружи капсулы. По бокам —
                // отступ, чтобы крайние подписи не срезало скругление.
                child: MediaQuery.removePadding(
                  context: context,
                  removeBottom: true,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s,
                    ),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
