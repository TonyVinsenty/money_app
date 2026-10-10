import 'dart:async';

import 'package:flutter/material.dart';
import 'package:money_app/app/app_services.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/recurring_rule_text.dart';
import 'package:money_app/core/ui/tap_to_dismiss_snack_content.dart';
import 'package:money_app/core/ui/transaction_rule_text.dart';
import 'package:money_app/features/recurring/domain/recurring_repository.dart';
import 'package:money_app/features/recurring/presentation/recurring_texts.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_rules.dart';
import 'package:money_app/features/transactions/presentation/quick_add/saved_snack_bar.dart';

/// Действия блока «К оплате», которые собирают чужие слои (ADR 0002):
/// запись в репозиторий регулярных платежей, имена категорий для сообщения
/// «Сохранено: ...» и «Отменить». Ошибки возвращаются текстом, не падают.
class DueActions {
  DueActions(this._services);

  final AppServices _services;

  void _say(ScaffoldMessengerState messenger, String text) => messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: TapToDismissSnackContent(child: Text(text))),
    );

  /// «Оплачено»: операция + сообщение с «Отменить» (= удаление операции;
  /// запись сама вернётся в «К оплате»).
  Future<String?> pay(
    BuildContext context,
    RecurringDue due, {
    required Money amount,
    required DateOnly day,
    required String? accountId,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final payment = due.payment;
    try {
      final transactionId = await _services.recurring.markPaid(
        due.id,
        amount: amount,
        day: day,
        accountId: accountId,
      );
      // Если запись уже была оплачена (двойное касание), вернулась id чужой
      // операции: сообщение строим по ней, а не по сумме из листа.
      Transaction? stored;
      try {
        stored = await _services.transactions.findById(transactionId);
      } on Object {
        stored = null;
      }
      if (stored == null) return null; // Операция записана, показать нечего.
      var categoryName = payment.title;
      String? subcategoryName;
      try {
        categoryName =
            (await _services.categories.findById(payment.categoryId))?.name ??
            categoryName;
        final subId = payment.subcategoryId;
        if (subId != null) {
          subcategoryName = (await _services.categories.findById(subId))?.name;
        }
      } on Object {
        // Имя нужно только для сообщения; операция уже записана.
      }
      final text = SavedSnackBar.text(
        type: payment.type,
        amount: stored.amount,
        categoryName: categoryName,
        subcategoryName: subcategoryName,
      );
      final spoken = SavedSnackBar.spokenText(
        type: payment.type,
        amount: stored.amount,
        categoryName: categoryName,
        subcategoryName: subcategoryName,
      );
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SavedSnackBar.build(
            text: text,
            spokenText: spoken,
            textScaler: scaler,
            onUndo: () => unawaited(_undoPay(messenger, transactionId)),
          ),
        );
      return null;
    } on TransactionRuleException catch (error) {
      return transactionRuleMessage(error.rule, type: payment.type);
    } on Object {
      return recurringSaveFailedText;
    }
  }

  Future<void> _undoPay(
    ScaffoldMessengerState messenger,
    String transactionId,
  ) async {
    try {
      await _services.transactions.softDelete(transactionId);
    } on Object {
      _say(messenger, SavedSnackBar.undoFailedText);
    }
  }

  /// «Пропустить»: сообщение с «Отменить» (= вернуть в «К оплате»).
  Future<String?> skip(BuildContext context, RecurringDue due) async {
    final messenger = ScaffoldMessenger.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    try {
      await _services.recurring.skip(due.id);
    } on Object {
      return recurringSaveFailedText;
    }
    final text = dueSkippedMessage(due.payment.title, due.dueOn);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SavedSnackBar.build(
          text: text,
          spokenText: text,
          textScaler: scaler,
          onUndo: () => unawaited(_undoSkip(messenger, due.id)),
        ),
      );
    return null;
  }

  Future<void> _undoSkip(ScaffoldMessengerState messenger, String id) async {
    try {
      await _services.recurring.unskip(id);
    } on Object {
      _say(messenger, SavedSnackBar.undoFailedText);
    }
  }
}
