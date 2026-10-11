import 'package:flutter/material.dart';
import 'package:money_app/features/accounts/domain/accounts_repository.dart';
import 'package:money_app/features/accounts/presentation/account_texts.dart';

/// Подтверждение удаления архивного счёта [name] (ADR 0010, п. 19): в тексте
/// число привязанных операций и переводов из [links]. Возвращает `true` только
/// после «Удалить»; «Отмена», «Назад» и тап мимо — `false`.
Future<bool> confirmAccountDelete(
  BuildContext context, {
  required String name,
  required AccountLinks links,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(accountDeleteDialogTitle(name)),
      content: Text(
        accountDeleteDialogText(
          transactions: links.transactions,
          transfers: links.transfers,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text(accountDeleteCancel),
        ),
        TextButton(
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text(accountDeleteAction),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
