import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:money_app/core/ui/account_icons.dart';
import 'package:money_app/core/ui/async_view.dart';
import 'package:money_app/core/ui/category_rule_text.dart';
import 'package:money_app/core/ui/tap_to_dismiss_snack_content.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/accounts/domain/accounts_repository.dart';
import 'package:money_app/features/accounts/presentation/account_texts.dart';

/// Экран «Порядок счетов»: не архивные счета, переставляются за ручку справа.
/// Новый порядок сохраняется сразу; при сбое возвращается прежний и
/// показывается сообщение. Кнопок «выше/ниже» для скринридера отдельно не
/// нужно: `ReorderableListView` сам вешает их на каждую строку.
class AccountsOrderScreen extends StatefulWidget {
  const AccountsOrderScreen({required this.accounts, super.key});

  final AccountsRepository accounts;

  static ValueKey<String> rowKey(String id) => ValueKey('accounts-order-$id');

  @override
  State<AccountsOrderScreen> createState() => _AccountsOrderScreenState();
}

class _AccountsOrderScreenState extends State<AccountsOrderScreen> {
  late final Stream<List<Account>> _stream = widget.accounts.watchAll();

  // Порядок, показанный сразу после перетаскивания, пока запись не дошла до
  // потока; `null` - показываем то, что отдал поток.
  List<String>? _localOrder;
  bool _saving = false;

  List<Account> _live(List<Account> all) {
    final live = [
      for (final a in all)
        if (!a.isArchived) a,
    ];
    final local = _localOrder;
    if (local == null) return live;
    final byId = {for (final a in live) a.id: a};
    if (local.length != live.length ||
        local.any((id) => !byId.containsKey(id))) {
      return live;
    }
    return [for (final id in local) byId[id]!];
  }

  Future<void> _reorder(List<Account> live, int oldIndex, int target) async {
    if (_saving || oldIndex == target) return;
    final moved = live[oldIndex];
    final next = [...live]
      ..removeAt(oldIndex)
      ..insert(target, moved);
    final ids = [for (final a in next) a.id];
    setState(() {
      _localOrder = ids;
      _saving = true;
    });
    final messenger = ScaffoldMessenger.of(context);
    var ok = true;
    try {
      await widget.accounts.reorder(ids);
    } on Object {
      ok = false;
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (!ok) _localOrder = null;
    });
    if (!ok) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: TapToDismissSnackContent(
              child: const Text(categorySaveFailedText),
            ),
          ),
        );
      return;
    }
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        accountMovedAnnouncement(moved.name, target + 1, ids.length),
        Directionality.of(context),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text(accountsOrderTitle)),
      body: SafeArea(
        child: AsyncView<List<Account>>(
          stream: _stream,
          loadingBuilder: (_) => const AsyncLoading(),
          errorBuilder: (context, _) => const Padding(
            padding: EdgeInsets.all(16),
            child: Text(accountsLoadError),
          ),
          dataBuilder: (context, all) {
            final live = _live(all);
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      accountsOrderHint,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: ReorderableListView(
                    // Свои ручки: тянуть можно только за значок справа.
                    buildDefaultDragHandles: false,
                    onReorderItem: (oldIndex, newIndex) =>
                        unawaited(_reorder(live, oldIndex, newIndex)),
                    children: [
                      for (var i = 0; i < live.length; i++)
                        ConstrainedBox(
                          key: AccountsOrderScreen.rowKey(live[i].id),
                          constraints: const BoxConstraints(minHeight: 56),
                          child: Padding(
                            padding: const EdgeInsets.only(left: 16),
                            child: Row(
                              children: [
                                Icon(
                                  accountIconFor(live[i].iconKey).icon,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Text(
                                    live[i].name,
                                    style: theme.textTheme.bodyLarge,
                                  ),
                                ),
                                // Скринридеру ручка не нужна: у строки есть
                                // действия «переместить».
                                ExcludeSemantics(
                                  child: ReorderableDragStartListener(
                                    index: i,
                                    child: const SizedBox(
                                      width: 48,
                                      height: 48,
                                      child: Icon(Icons.drag_handle),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
