import 'package:flutter/material.dart';
import 'package:money_app/core/ui/account_icons.dart';
import 'package:money_app/features/accounts/domain/account.dart';

/// Тексты плашки счёта и листа выбора (утверждены).
const String accountChipNone = 'Без счёта';
const String accountSheetTitle = 'Счёт';

/// Скринридеру: «Счёт: Карта, изменить».
String accountChipSemantics(String? name) =>
    'Счёт: ${name ?? accountChipNone.toLowerCase()}, изменить';

/// Плашка счёта операции рядом с плашкой даты: имя счёта или «Без счёта».
/// Тап открывает лист выбора среди [accounts] (уже отобранных вызывающим) и
/// «Без счёта» последним. Выбор уходит в [onChanged] (`null` - без счёта).
class AccountChip extends StatelessWidget {
  const AccountChip({
    required this.accounts,
    required this.selectedId,
    required this.onChanged,
    super.key,
  });

  final List<Account> accounts;
  final String? selectedId;
  final ValueChanged<String?> onChanged;

  static const chipKey = ValueKey('account-chip');

  static ValueKey<String> optionKey(String? id) =>
      ValueKey('account-option-${id ?? 'none'}');

  Account? get _selected {
    for (final a in accounts) {
      if (a.id == selectedId) return a;
    }
    return null;
  }

  Future<void> _pick(BuildContext context) async {
    final picked = await showModalBottomSheet<({String? id})>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text(
                  accountSheetTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              for (final a in accounts)
                _option(context, a.id, a.name, accountIconFor(a.iconKey).icon),
              _option(context, null, accountChipNone, Icons.block),
            ],
          ),
        ),
      ),
    );
    if (picked != null) onChanged(picked.id);
  }

  Widget _option(BuildContext context, String? id, String name, IconData icon) {
    final selected = id == _selected?.id;
    return ListTile(
      key: optionKey(id),
      leading: Icon(icon),
      title: Text(name),
      trailing: selected ? const Icon(Icons.check) : null,
      selected: selected,
      onTap: () => Navigator.of(context).pop((id: id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = _selected?.name;
    return Semantics(
      label: accountChipSemantics(name),
      button: true,
      onTap: () => _pick(context),
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        child: ActionChip(
          key: chipKey,
          avatar: Icon(
            name == null
                ? Icons.account_balance_wallet_outlined
                : accountIconFor(_selected!.iconKey).icon,
            size: 18,
          ),
          label: Text(name ?? accountChipNone),
          onPressed: () => _pick(context),
          materialTapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),
    );
  }
}
