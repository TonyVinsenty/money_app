import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/features/accounts/presentation/account_texts.dart';

/// Тексты удаления счёта из архива (ADR 0010, п. 19; шаг 7.30h).
void main() {
  String text(int transactions, int transfers) =>
      accountDeleteDialogText(transactions: transactions, transfers: transfers);

  test('без привязок — коротко', () {
    expect(text(0, 0), 'Счёт удалится насовсем.');
  });

  test('операции с падежами', () {
    expect(
      text(1, 0),
      'К счёту привязана 1 операция. '
      'После удаления она останется без привязки к счёту.',
    );
    expect(
      text(2, 0),
      'К счёту привязаны 2 операции. '
      'После удаления они останутся без привязки к счёту.',
    );
    expect(
      text(5, 0),
      'К счёту привязано 5 операций. '
      'После удаления они останутся без привязки к счёту.',
    );
    expect(text(11, 0), startsWith('К счёту привязано 11 операций.'));
    expect(text(12, 0), startsWith('К счёту привязано 12 операций.'));
    expect(text(21, 0), startsWith('К счёту привязана 21 операция.'));
    expect(text(22, 0), startsWith('К счёту привязаны 22 операции.'));
  });

  test('операции и переводы — оба предложения', () {
    expect(
      text(12, 3),
      'К счёту привязано 12 операций. '
      'После удаления они останутся без привязки к счёту. '
      'Переводы с этим счётом (3) будут удалены.',
    );
  });

  test('только переводы', () {
    expect(text(0, 3), 'Переводы с этим счётом (3) будут удалены.');
    expect(text(0, 1), 'Перевод с этим счётом (1) будет удалён.');
  });

  test('заголовок, сообщение, озвучка кнопок', () {
    expect(accountDeleteDialogTitle('Тест'), 'Удалить счёт «Тест»?');
    expect(accountDeletedMessage('Тест'), 'Счёт «Тест» удалён');
    expect(accountDeleteLabel('Тест'), 'Удалить «Тест»');
    expect(accountRestoreLabel('Тест'), 'Вернуть «Тест» из архива');
  });
}
