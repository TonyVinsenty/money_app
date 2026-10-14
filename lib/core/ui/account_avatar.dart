import 'package:flutter/material.dart';
import 'package:money_app/core/ui/account_icons.dart';
import 'package:money_app/core/ui/icon_scale.dart';

/// Значок счёта в нейтральном кружке 40 dp: строки счетов выглядят как строки
/// операций (D44). Растёт с шрифтом до 1,3. От скринридера скрыт: подпись
/// даёт строка.
class AccountAvatar extends StatelessWidget {
  const AccountAvatar(this.iconKey, {this.name, super.key});

  final String iconKey;
  final String? name;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final k = iconScaleOf(context);
    return Container(
      width: 40 * k,
      height: 40 * k,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        shape: BoxShape.circle,
      ),
      child: AccountIconView(
        iconKey,
        name: name,
        size: 24 * k,
        color: scheme.onSurfaceVariant,
      ),
    );
  }
}
