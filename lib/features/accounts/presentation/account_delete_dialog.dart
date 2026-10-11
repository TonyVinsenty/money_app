import 'package:flutter/material.dart';
import 'package:money_app/core/ui/adaptive_dialog_action.dart';
import 'package:money_app/features/accounts/domain/accounts_repository.dart';
import 'package:money_app/features/accounts/presentation/account_texts.dart';

/// Подтверждение удаления архивного счёта [name] (ADR 0010, п. 19): в тексте
/// число привязанных операций и переводов из [links]. Возвращает `true` только
/// после «Удалить»; «Отмена», «Назад» и тап мимо (на Android) — `false`.
/// На iPhone — системный вид (ADR 0013, п. 6).
Future<bool> confirmAccountDelete(
  BuildContext context, {
  required String name,
  required AccountLinks links,
}) async {
  final confirmed = await showAdaptiveDialog<bool>(
    context: context,
    builder: (context) => AlertDialog.adaptive(
      title: Text(accountDeleteDialogTitle(name)),
      content: Text(
        accountDeleteDialogText(
          transactions: links.transactions,
          transfers: links.transfers,
        ),
      ),
      actions: [
        AdaptiveDialogAction(
          onPressed: () => Navigator.of(context).pop(false),
          label: accountDeleteCancel,
        ),
        AdaptiveDialogAction(
          onPressed: () => Navigator.of(context).pop(true),
          label: accountDeleteAction,
          destructive: true,
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
