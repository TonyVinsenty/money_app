import 'package:flutter/material.dart';

/// Пояснение пустого экрана: операции в других валютах есть, но не видны.
/// [symbol] - знак основной валюты из каталога.
String otherCurrenciesHintText(String symbol) =>
    'Здесь только операции в основной валюте ($symbol). Остальные появятся '
    'снова, если вернуть их валюту в «Настройках».';

/// Ключ подсказки (для тестов).
const Key otherCurrenciesHintKey = ValueKey('other-currencies-hint');

/// Показывает [otherCurrenciesHintText], когда [hasOther] выдал `true`; пока
/// ответа нет, при `false`, ошибке или без потока - ничего.
class OtherCurrenciesHint extends StatelessWidget {
  const OtherCurrenciesHint({
    required this.hasOther,
    required this.symbol,
    super.key,
  });

  final Stream<bool>? hasOther;
  final String symbol;

  @override
  Widget build(BuildContext context) {
    final stream = hasOther;
    if (stream == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return StreamBuilder<bool>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.data != true) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            otherCurrenciesHintText(symbol),
            key: otherCurrenciesHintKey,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        );
      },
    );
  }
}
