import 'package:flutter/material.dart';
import 'package:money_app/core/money/currency_catalog.dart';

const String currencyPickerTitle = 'Валюта';
const String currencyPickerSearchHint = 'Код, название или символ';
const String currencyPickerClearSearch = 'Очистить поиск';
const String currencyPickerPopular = 'Популярные';
const String currencyPickerYours = 'Ваши валюты';
const String currencyPickerAll = 'Все валюты';
const String currencyPickerCrypto = 'Криптовалюты';
const String currencyPickerNothingFound = 'Ничего не найдено';
const String currencyPickerCustom = 'Своя валюта…';
const String currencyPickerCustomHint = 'Если нужной нет в списке';

/// Коды группы «Популярные» (ADR 0010, п. 16.8).
const List<String> _popularCodes = <String>[
  'RUB',
  'USD',
  'EUR',
  'CNY',
  'BTC',
  'ETH',
  'USDT',
  'TON',
];

/// Открывает лист выбора валюты (ADR 0010, п. 16.8).
///
/// Возвращает выбранную запись или `null`, если лист закрыли.
/// [selected] — код текущей валюты (отмечается признаком `selected`).
/// [fiatOnly] — только обычные валюты: без крипты, «Ваших валют» и «Своей
/// валюты». [yourCurrencies] — свои валюты из счетов. [onCustom] — колбэк
/// «Своя валюта…»: строка показывается, только если он передан; если колбэк
/// вернул валюту, лист закрывается с ней.
Future<CurrencyInfo?> showCurrencyPicker(
  BuildContext context, {
  String? selected,
  bool fiatOnly = false,
  List<CurrencyInfo> yourCurrencies = const [],
  Future<CurrencyInfo?> Function()? onCustom,
  String title = currencyPickerTitle,
}) {
  return showModalBottomSheet<CurrencyInfo>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (context) => _CurrencyPickerSheet(
      title: title,
      selected: selected,
      fiatOnly: fiatOnly,
      yourCurrencies: fiatOnly ? const [] : yourCurrencies,
      onCustom: fiatOnly ? null : onCustom,
    ),
  );
}

sealed class _Item {
  const _Item();
}

class _Header extends _Item {
  const _Header(this.title);
  final String title;
}

class _Currency extends _Item {
  const _Currency(this.info);
  final CurrencyInfo info;
}

class _Nothing extends _Item {
  const _Nothing();
}

class _Custom extends _Item {
  const _Custom();
}

class _CurrencyPickerSheet extends StatefulWidget {
  const _CurrencyPickerSheet({
    required this.title,
    required this.selected,
    required this.fiatOnly,
    required this.yourCurrencies,
    required this.onCustom,
  });

  final String title;
  final String? selected;
  final bool fiatOnly;
  final List<CurrencyInfo> yourCurrencies;
  final Future<CurrencyInfo?> Function()? onCustom;

  @override
  State<_CurrencyPickerSheet> createState() => _CurrencyPickerSheetState();
}

class _CurrencyPickerSheetState extends State<_CurrencyPickerSheet> {
  final TextEditingController _controller = TextEditingController();
  late final List<CurrencyInfo> _pool;
  String _query = '';

  @override
  void initState() {
    super.initState();
    // Пул для поиска: свои валюты (которых нет в каталоге) и каталог.
    final seen = <String>{};
    _pool = [
      for (final c in [...widget.yourCurrencies, ...currencyCatalog])
        if ((!widget.fiatOnly || c.kind == CurrencyKind.fiat) &&
            seen.add(c.code))
          c,
    ];
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<_Item> _buildItems() {
    final items = <_Item>[];
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) {
      final popular = [
        for (final code in _popularCodes)
          for (final c in _pool)
            if (c.code == code) c,
      ];
      items.add(const _Header(currencyPickerPopular));
      items.addAll(popular.map(_Currency.new));
      if (widget.yourCurrencies.isNotEmpty) {
        items.add(const _Header(currencyPickerYours));
        items.addAll(widget.yourCurrencies.map(_Currency.new));
      }
      final fiat = [
        for (final c in _pool)
          if (c.kind == CurrencyKind.fiat) c,
      ]..sort((a, b) => a.name.compareTo(b.name));
      items.add(const _Header(currencyPickerAll));
      items.addAll(fiat.map(_Currency.new));
      if (!widget.fiatOnly) {
        items.add(const _Header(currencyPickerCrypto));
        items.addAll([
          for (final c in _pool)
            if (c.kind == CurrencyKind.crypto) _Currency(c),
        ]);
      }
    } else {
      final found = [
        for (final c in _pool)
          if (c.code.toLowerCase().contains(query) ||
              c.name.toLowerCase().contains(query) ||
              c.symbol.toLowerCase().contains(query))
            c,
      ];
      if (found.isEmpty) {
        items.add(const _Nothing());
      } else {
        items.addAll(found.map(_Currency.new));
      }
    }
    if (widget.onCustom != null) items.add(const _Custom());
    return items;
  }

  Future<void> _pickCustom() async {
    final result = await widget.onCustom!();
    if (result != null && mounted) Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    final height = (media.size.height - keyboard) * 0.85;
    final items = _buildItems();

    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: SizedBox(
        height: height < 240 ? 240 : height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: Semantics(
                header: true,
                child: Text(widget.title, style: theme.textTheme.titleMedium),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: _controller,
                builder: (context, value, _) => TextField(
                  controller: _controller,
                  onChanged: (text) => setState(() => _query = text),
                  maxLines: 1,
                  keyboardType: TextInputType.text,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: currencyPickerSearchHint,
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: value.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close),
                            tooltip: currencyPickerClearSearch,
                            onPressed: () {
                              _controller.clear();
                              setState(() => _query = '');
                            },
                          ),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: items.length,
                itemBuilder: (context, index) =>
                    _buildItem(context, items[index]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItem(BuildContext context, _Item item) {
    final theme = Theme.of(context);
    switch (item) {
      case _Header(:final title):
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Semantics(
            header: true,
            child: Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        );
      case _Nothing():
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Semantics(
            liveRegion: true,
            child: Text(
              currencyPickerNothingFound,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        );
      case _Custom():
        return ListTile(
          minVerticalPadding: 8,
          leading: const Icon(Icons.add),
          title: const Text(currencyPickerCustom),
          subtitle: const Text(currencyPickerCustomHint),
          onTap: _pickCustom,
        );
      case _Currency(:final info):
        final isSelected = info.code == widget.selected;
        final sub = info.symbol == info.code
            ? info.code
            : '${info.code} · ${info.symbol}';
        return Semantics(
          button: true,
          selected: isSelected ? true : null,
          label: '${info.name}, ${info.code}',
          excludeSemantics: true,
          onTap: () => Navigator.of(context).pop(info),
          child: InkWell(
            onTap: () => Navigator.of(context).pop(info),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(info.name, style: theme.textTheme.bodyLarge),
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
}
