/// Иконка приложения на выбор (ADR 0014). [id] — стабильное имя варианта:
/// по нему нативный код находит ярлык Android и набор картинок iOS.
///
/// [id] не переименовываются и не удаляются никогда (ADR 0014, п. 6): если
/// выбранный у человека ярлык исчезнет, приложение пропадёт из списка
/// приложений Android.
enum AppIconChoice {
  /// Вариант 1 «Кольцо крупнее» — иконка по умолчанию.
  ring('ring'),

  /// Вариант 2 «Кольцо на синем».
  ringBlue('ring_blue'),

  /// Вариант 6 «Монеты».
  coins('coins'),

  /// Вариант 7 «Кошелёк».
  wallet('wallet');

  const AppIconChoice(this.id);

  final String id;

  /// Иконка, которая стоит после установки.
  static const defaultChoice = ring;

  /// Вариант по [id] или `null`, если такого нет.
  static AppIconChoice? fromId(String? id) {
    for (final choice in values) {
      if (choice.id == id) return choice;
    }
    return null;
  }
}
