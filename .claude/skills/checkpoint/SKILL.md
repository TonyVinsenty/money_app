---
name: checkpoint
description: Контрольная точка в Git - прогоняет форматирование, анализ и тесты, затем делает коммит.
disable-model-invocation: true
argument-hint: [что сделано]
allowed-tools: Bash(git status *) Bash(git diff *) Bash(git add *) Bash(git commit *) Bash(git log *) Bash(dart format *) Bash(flutter analyze *) Bash(flutter test *) PowerShell(git status *) PowerShell(git diff *) PowerShell(git add *) PowerShell(git commit *) PowerShell(git log *) PowerShell(dart format *) PowerShell(flutter analyze *) PowerShell(flutter test *)
---

Сделай контрольную точку (чекпоинт) в Git для проекта MoneyAPP. Описание от пользователя: $ARGUMENTS

Объясняй шаги простыми словами: пользователь — новичок.

1. **Проверки.** Если в корне есть `pubspec.yaml`, выполни по порядку `dart format .`, `flutter analyze`, `flutter test`. При любой ошибке **остановись**, покажи вывод, объясни причину и не коммить. Если `pubspec.yaml` ещё нет, скажи, что проверки пропущены, потому что приложения ещё нет (например, коммитятся только настройки/документы).
2. **Что войдёт в коммит.** Выполни `git status --short` и `git diff --stat`. Кратко перечисли изменения. Если среди них есть секреты (`.env*`, `key.properties`, `*.jks`, `*.keystore`) или сгенерированные файлы (`build/`, `.dart_tool/`), не добавляй их и предупреди.
3. **Коммит.** Добавь нужные файлы по именам или папкам (не `git add -A` вслепую), затем `git commit` с сообщением `checkpoint: <описание>` (описание — из аргументов; если их нет, сформулируй по диффу на английском, коротко). Добавь атрибуцию `Co-Authored-By`, принятую в этой сессии.
4. **Итог.** Покажи `git log --oneline -3`: хеш и сообщение нового коммита. Напомни, что вернуться к этой точке можно по хешу, а `git push` не выполнялся.

Не делай `git push`, `git reset`, `git rebase`, `--amend` и не переписывай историю. Если нечего коммитить, так и скажи.
