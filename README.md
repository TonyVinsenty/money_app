# MoneyAPP

Приложение для учёта личных доходов и расходов на Flutter (Android + iOS).
Local-first: все данные хранятся на устройстве, работает без аккаунта и без сети.

Видимое имя приложения пока временное: «Money App».

## Требования

- Flutter 3.47.x / Dart 3.13.x
- Android SDK и эмулятор (AVD `Pixel_8`)

## Ежедневные команды

```powershell
flutter pub get                       # подтянуть зависимости
dart format .                         # форматирование
flutter analyze                       # статический анализ
flutter test                          # тесты
flutter emulators --launch Pixel_8    # запустить эмулятор
flutter run                           # запустить приложение
```

## Окружение разработчика

- Android SDK, Gradle и AVD лежат на `D:\Android`; заданы переменные
  `ANDROID_HOME`, `GRADLE_USER_HOME`, `ANDROID_AVD_HOME`.
- Из-за VPN загрузки с серверов Google медленные. Для эмулятора собираем только
  под его архитектуру: `--target-platform android-x64`.
- iOS-версию можно собрать только на macOS с Xcode.

## Документы

- [CLAUDE.md](CLAUDE.md) — принципы и процесс разработки
- [docs/ROADMAP.md](docs/ROADMAP.md) — план и этапы
- [docs/decisions/](docs/decisions/) — архитектурные решения (ADR)
