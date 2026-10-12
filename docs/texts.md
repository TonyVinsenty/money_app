# Тексты интерфейса Zuno (шаг 7.40, Т4)

Выгрузка 2026-10-12: все тексты, которые видит или слышит (VoiceOver/TalkBack) пользователь, — по экранам, с файлом и строкой. Сверху — найденный разнобой: по каждому пункту нужен ваш выбор. Ниже — полная таблица: если хотите поменять конкретную формулировку, впишите новый текст в колонку «Правка» (или напишите в чат: «строка такая-то → так»).

Как отвечать: проще всего в чате — «всё по рекомендации» или «Р3 — Б, Р8 — В, остальное по рекомендации». Правки делаются только по вашим отметкам.

В таблице `{…}` — подставляемое значение (сумма, дата, название), `{name}` — имя подставляемого значения. Обрывки фраз (окончания «платёж/платежа/платежей», «доход»/«расход» внутри предложения) в таблицу не попали — они меняются вместе со своей фразой.

## Решения по разнобою

**Р1. Кнопка отмены в сообщении внизу экрана.** Сейчас «Отменить» — после новой операции, перевода, удаления платежа; «Вернуть» — после отправки счёта или категории в архив.
- [ ] **А (рекомендую):** везде «Отменить». Одно действие — одно слово, как в системных приложениях iOS и Android.
- [ ] **Б:** оставить как есть («Вернуть» звучит как «вернуть из архива»).

«Отмена» в окнах-вопросах (закрыть окно без действия) и «Вернуть из архива» в меню не трогаем — это другие действия.

**Р2. Кнопка «Перевод» на «Балансе».**
- [ ] **А (рекомендую):** оставить «Перевод» — в паре с «Доход» и «Расход» на «Главной», экран называется «Новый перевод».
- [ ] **Б:** «Перевести».

**Р3. Заголовки экранов правки.** Сейчас три вида: «Изменить счёт», «Изменить категорию», «Изменить подкатегорию»; «Правка перевода», «Правка расхода», «Правка дохода»; правка регулярного платежа — просто «Платёж».
- [ ] **А (рекомендую):** везде «Изменить …»: «Изменить перевод», «Изменить расход», «Изменить доход», «Изменить платёж».
- [ ] **Б:** везде «Правка …»: «Правка счёта», «Правка категории», «Правка подкатегории», «Правка платежа».

**Р4. Точка в конце.** В основном точек нет, но 5 мест выбиваются.
- [ ] **А (рекомендую), правило:** подсказки, пустые экраны, сообщения внизу, ошибки под полем и строки состояния — без точки в конце (даже если внутри два предложения); текст в окнах-вопросах и абзацы экрана ошибки базы — законченные предложения с точкой. По правилу: убрать точку в 4 местах (пометка Р4 в таблице: «Подкатегорий пока нет…», «Уведомления для Zuno выключены…», «В файле есть ошибки…», «Здесь только операции в основной валюте…») и добавить точку в окне «Отправить счёт в архив?» («…Операции счёта сохранятся.»).
- [ ] **Б:** оставить как есть.

**Р5. «Последний экспорт: ещё не было»** (в «Настройках», пока экспорта не было) — фраза нескладная.
- [ ] **А (рекомендую):** «Экспорта ещё не было» и «Экспорта ещё не было — сделайте копию».
- [ ] **Б:** «Последний экспорт: не было».
- [ ] **В:** оставить.

**Р6. «Тип» или «вид».** Форма категории — «Тип», правка операции — «Тип операции», форма платежа — «Вид платежа», ошибка — «Эта категория из другого вида…», в ошибках CSV — «категорию другого типа».
- [ ] **А (рекомендую):** везде «тип»: «Тип платежа», «Эта категория другого типа: она для расходов, а вы вводите доход…».
- [ ] **Б:** оставить.

**Р7. Две формулировки одной ошибки в форме платежа.** Форма проверяет поля своими текстами, а сохранение — другими:
- «Введите название» / «Введите название платежа»;
- «Название — не длиннее 40 символов» / «Название слишком длинное: не больше 40 символов» (так же у счёта и категории);
- «Окончание не может быть раньше первого платежа» / «Дата окончания раньше даты первого платежа».
- [ ] **А (рекомендую):** по одному тексту: «Введите название платежа», «Название слишком длинное: не больше 40 символов», «Окончание не может быть раньше первого платежа».
- [ ] **Б:** оставить.

**Р8. Экспорт и загрузка в «Настройках»:** «Экспорт в CSV» (существительное) рядом с «Загрузить из CSV» (глагол); экран загрузки — «Загрузка из CSV».
- [ ] **А (рекомендую):** оставить — слова привычные, на них ссылаются подсказка на «Главной», «Последний экспорт» и инструкция для iPhone.
- [ ] **Б:** «Сохранить в CSV» и «Загрузить из CSV».
- [ ] **В:** «Экспорт в CSV» и «Импорт из CSV» (экран — «Импорт из CSV»).

**Р9. «Счёт с таким именем уже есть…»** (при возврате из архива) — везде в остальных местах «название».
- [ ] **А (рекомендую):** «Счёт с таким названием уже есть. Переименуйте его или оставьте этот в архиве».
- [ ] **Б:** оставить.

**Р10. Пустой прошлый месяц.** «Главная» — «В сентябре 2025 операций не было», «История» — «За сентябрь 2025 операций нет», кольцо — «За сентябрь 2025 расходов нет».
- [ ] **А (рекомендую):** на «Главной» тоже «За сентябрь 2025 операций нет».
- [ ] **Б:** оставить.

**Р11 (только для сведения, решения не нужно).** Многоточие у загрузки: на экране видны «Загрузка…», «Проверяем файл…», «Загружаем…» — с многоточием; «Загрузка», «Готовим файл», «Стираем данные», «Загрузка итогов», «Загрузка операций» только озвучиваются VoiceOver, там многоточие не нужно. Разнобой кажущийся, не трогаем.

**Т1 (техническая правка, уже решена в плане).** В подсказках «Аналитики» диапазон «1–11 сентября» больше не будет переноситься сразу после тире.

## Что не вошло в таблицу

- Названия валют (каталог, ~200), подписи значков категорий и счетов, названия месяцев и дней недели — справочники.
- Заголовки колонок и слова в файле CSV («расход», «доход», «перевод»…) — их менять нельзя: старые файлы перестанут загружаться.
- Служебные сообщения для разработчика (ошибки маршрутов, подробности на экране ошибки базы).

## Все тексты по экранам

### Нижняя панель

| Текст | Где | Пометка | Правка |
|---|---|---|---|
| Главная | `app_tabs.dart:45` |  |  |
| История | `app_tabs.dart:52` |  |  |
| Аналитика | `app_tabs.dart:58` |  |  |
| Баланс | `app_tabs.dart:64` |  |  |
| Настройки | `app_tabs.dart:72` |  |  |
| Основная валюта: {…} | `app_tabs.dart:172` |  |  |
| В разработке | `app_tabs.dart:667` |  |  |

### Экран загрузки и ошибки базы

| Текст | Где | Пометка | Правка |
|---|---|---|---|
| Загрузка | `database_gate.dart:10` |  |  |
| Не удалось открыть базу данных | `database_gate.dart:14` |  |  |
| Zuno не смог открыть свои данные на этом телефоне. Попробуйте ещё раз. Если не получается: освободите место на телефоне, перезагрузите его и обновите Zuno. | `database_gate.dart:19` |  |  |
| Не удаляйте приложение и не очищайте его данные: вместе с ними пропадут все записи. Откройте «Подробности» и передайте этот текст разработчику. | `database_gate.dart:25` |  |  |
| Повторить | `database_gate.dart:29` |  |  |
| Подробности (для разработчика) | `database_gate.dart:32` |  |  |
| Скопировать подробности | `database_gate.dart:35` |  |  |
| Скопировано | `database_gate.dart:38` |  |  |
| Не получилось. Попытка {attempt}. | `database_gate.dart:42` |  |  |
| Повторные попытки, скорее всего, не помогут. | `database_gate.dart:46` |  |  |
| Начать заново | `database_gate.dart:49` |  |  |
| Начать заново? | `database_gate.dart:52` |  |  |
| Файл со старыми данными не удаляется: он останется на телефоне под другим именем, но Zuno начнёт с пустой базы. | `database_gate.dart:54` |  |  |
| Точно начать заново? | `database_gate.dart:58` |  |  |
| Все записи будут потеряны, восстановить можно только из CSV. | `database_gate.dart:60` |  |  |
| Отмена | `database_gate.dart:63` |  |  |
| Продолжить | `database_gate.dart:64` |  |  |
| Не удалось начать заново. Файл базы занят или недоступен. Попробуйте ещё раз или перезагрузите телефон. | `database_gate.dart:68` |  |  |
| Ошибка «Начать заново»:  | `database_gate.dart:72` |  |  |

### Главная

| Текст | Где | Пометка | Правка |
|---|---|---|---|
| Доход | `home_action_bar.dart:31` |  |  |
| Добавить доход | `home_action_bar.dart:32` |  |  |
| Расход | `home_action_bar.dart:42` |  |  |
| Добавить расход | `home_action_bar.dart:43` |  |  |
| Добро пожаловать в Zuno | `home_welcome_card.dart:8` |  |  |
| Нажмите «\u2212 Расход» или «+ Доход» внизу — здесь появятся итоги месяца, а кольцо покажет, на что уходят деньги | `home_welcome_card.dart:10` |  |  |
| Есть записи из другого приложения? «Настройки» → «Загрузить из CSV» | `home_welcome_card.dart:13` | Р8 |  |
| В {…} операций пока нет | `home_welcome_card.dart:20` |  |  |
| В {…} {…} операций не было | `home_welcome_card.dart:21` | Р10 |  |
| Расходы по категориям | `month_chart_card.dart:208` |  |  |
| Не удалось посчитать расходы по категориям | `month_chart_card.dart:226` |  |  |
| Диаграмма расходов за {…}. {…}: {…}${line == null ?  :  | `month_chart_card.dart:340` |  |  |
| Остальное | `month_chart_card.dart:383` |  |  |
| В этом месяце расходов пока нет | `month_chart_card.dart:438` |  |  |
| За {…} {…} расходов нет | `month_chart_card.dart:439` |  |  |
| За {…} | `month_chart_card.dart:464` |  |  |
| На счетах | `month_chart_card.dart:468` |  |  |
| За всё время | `month_chart_card.dart:469` |  |  |
| плюс {…} | `month_chart_card.dart:540` |  |  |
| Ещё {count} ${pluralRu(count,  | `month_chart_card.dart:635` |  |  |
| Предыдущий месяц | `month_summary_card.dart:104` |  |  |
| Следующий месяц | `month_summary_card.dart:105` |  |  |
| Показать суммы | `month_summary_card.dart:120` |  |  |
| Скрыть суммы | `month_summary_card.dart:120` |  |  |
| Расходы | `month_summary_card.dart:229` |  |  |
| Доходы | `month_summary_card.dart:229` |  |  |
| Не удалось посчитать {…} за месяц | `month_summary_card.dart:257` |  |  |
| Пока нет | `month_summary_card.dart:268` |  |  |
| {title} за {monthName}: {…} | `month_summary_card.dart:291` |  |  |

### Быстрый ввод

| Текст | Где | Пометка | Правка |
|---|---|---|---|
| Доход | `amount_field.dart:116` |  |  |
| Расход | `amount_field.dart:116` |  |  |
| Сумма дохода | `amount_field.dart:120` |  |  |
| Сумма расхода | `amount_field.dart:120` |  |  |
| Без подкатегории | `category_grid.dart:33` |  |  |
| Без счёта | `account_chip.dart:6` |  |  |
| Счёт | `account_chip.dart:7` |  |  |
| Счёт не выбран, изменить | `account_chip.dart:11` |  |  |
| Счёт: {name}, изменить | `account_chip.dart:11` |  |  |
| Категория расхода | `category_picker_screen.dart:80` |  |  |
| Категория дохода | `category_picker_screen.dart:81` |  |  |
| Нет категорий для расходов | `category_picker_screen.dart:82` |  |  |
| Нет категорий для доходов | `category_picker_screen.dart:83` |  |  |
| Создайте первую категорию, чтобы записывать операции | `category_picker_screen.dart:85` |  |  |
| Добавить категорию | `category_picker_screen.dart:86` |  |  |
| Не удалось загрузить категории | `category_picker_screen.dart:87` |  |  |
| Комментарий (необязательно) | `note_field.dart:28` |  |  |
| Введено {length} из {transactionNoteMaxLength} символов | `note_field.dart:33` |  |  |
| Новый доход | `quick_add_screen.dart:78` |  |  |
| Новый расход | `quick_add_screen.dart:79` |  |  |
| Далее | `quick_add_screen.dart:83` |  |  |
| Отменить | `saved_snack_bar.dart:12` | Р1 |  |
| Не удалось загрузить счета. Операция сохранена без счёта | `saved_snack_bar.dart:17` |  |  |
| Сохранено: {…} {…} · {categoryName}{…} | `saved_snack_bar.dart:31` |  |  |
| Сохранить: {…} | `suggestion_row.dart:27` |  |  |
| Сохранить: {…}, {…} | `suggestion_row.dart:28` |  |  |

### Правка операции

| Текст | Где | Пометка | Правка |
|---|---|---|---|
| Категория расхода | `edit_category_picker_screen.dart:22` |  |  |
| Категория дохода | `edit_category_picker_screen.dart:23` |  |  |
| Нет категорий для расходов | `edit_category_picker_screen.dart:24` |  |  |
| Нет категорий для доходов | `edit_category_picker_screen.dart:25` |  |  |
| Не удалось загрузить категории | `edit_category_picker_screen.dart:26` |  |  |
| Счёт | `edit_transaction_screen.dart:57` |  |  |
| не найден | `edit_transaction_screen.dart:59` |  |  |
| Правка расхода | `edit_transaction_screen.dart:74` | Р3 |  |
| Правка дохода | `edit_transaction_screen.dart:75` | Р3 |  |
| Сохранить | `edit_transaction_screen.dart:76` |  |  |
| Изменения сохранены | `edit_transaction_screen.dart:77` |  |  |
| Категория | `edit_transaction_screen.dart:79` |  |  |
| Загрузка… | `edit_transaction_screen.dart:80` |  |  |
| Подкатегория | `edit_transaction_screen.dart:81` |  |  |
| Без подкатегории | `edit_transaction_screen.dart:82` |  |  |
| Подкатегория сброшена | `edit_transaction_screen.dart:83` |  |  |
| Удалить | `edit_transaction_screen.dart:84` |  |  |
| Удалить операцию | `edit_transaction_screen.dart:85` |  |  |
| Операция удалена | `edit_transaction_screen.dart:86` |  |  |
| Эта операция уже удалена | `edit_transaction_screen.dart:87` |  |  |
| Не удалось удалить. Попробуйте ещё раз | `edit_transaction_screen.dart:88` |  |  |
| Эта операция уже удалена, сохранить нечего | `edit_transaction_screen.dart:89` |  |  |
| Тип операции | `edit_transaction_screen.dart:90` | Р6 |  |
| Расход | `edit_transaction_screen.dart:91` |  |  |
| Доход | `edit_transaction_screen.dart:92` |  |  |

### История

| Текст | Где | Пометка | Правка |
|---|---|---|---|
| не найден | `history_filter_label.dart:7` |  |  |
| Без счёта | `history_filter_label.dart:26` |  |  |
| Счёт: {…} | `history_filter_label.dart:27` |  |  |
| Расходы | `history_filter_label.dart:35` |  |  |
| Доходы | `history_filter_label.dart:38` |  |  |
| Все | `history_filter_label.dart:43` |  |  |
| расходы: {…} | `history_filter_label.dart:44` |  |  |
| доходы: {…} | `history_filter_label.dart:45` |  |  |
| Фильтр: ${parts.join( | `history_filter_label.dart:48` |  |  |
| нет категорий | `history_filter_label.dart:61` |  |  |
| Фильтр | `history_filter_label.dart:79` |  |  |
| Фильтр:  | `history_filter_label.dart:80` |  |  |
| Фильтр, включён: {…}{…} | `history_filter_label.dart:86` |  |  |
| Счёт | `history_filter_sheet.dart:97` |  |  |
| Все счета | `history_filter_sheet.dart:100` |  |  |
| {…} (в архиве) | `history_filter_sheet.dart:106` |  |  |
| Выбрать все | `history_filter_sheet.dart:175` |  |  |
| Снять все | `history_filter_sheet.dart:180` |  |  |
| Не выбрана ни одна категория | `history_filter_sheet.dart:210` |  |  |
| Сбросить | `history_filter_sheet.dart:275` |  |  |
| Категории расходов | `history_filter_sheet.dart:312` |  |  |
| Категории доходов | `history_filter_sheet.dart:328` |  |  |
| Готово | `history_filter_sheet.dart:346` |  |  |
| Здесь будут все ваши доходы и расходы | `history_screen.dart:34` |  |  |
| Добавить расход | `history_screen.dart:35` |  |  |
| Во всех месяцах | `history_screen.dart:389` |  |  |
| Предыдущий месяц | `history_screen.dart:393` |  |  |
| Следующий месяц | `history_screen.dart:394` |  |  |
| Доход  | `history_screen.dart:470` |  |  |
| Расход  | `history_screen.dart:470` |  |  |
| За {…} {…} операций нет | `history_screen.dart:546` |  |  |
| Выберите другой месяц стрелками вверху | `history_screen.dart:549` |  |  |
| Сбросить фильтр | `history_screen.dart:622` |  |  |
| Сначала новые | `history_screen.dart:639` |  |  |
| Сначала старые | `history_screen.dart:640` |  |  |
| Сначала крупные | `history_screen.dart:641` |  |  |
| Сначала мелкие | `history_screen.dart:642` |  |  |
| Сортировка: {…} | `history_screen.dart:725` |  |  |
| Комментарий или подкатегория | `history_screen.dart:762` |  |  |
| Очистить поиск | `history_screen.dart:768` |  |  |
| Ничего не найдено | `history_screen.dart:807` |  |  |
| Нет операций с «{query}» в комментарии или подкатегории | `history_screen.dart:813` |  |  |
| За {…} {…} нет операций, подходящих под фильтр | `history_screen.dart:863` |  |  |
| Загрузка операций | `history_screen.dart:927` |  |  |
| расходы  | `history_screen.dart:998` |  |  |
| доходы  | `history_screen.dart:999` |  |  |

### Аналитика

| Текст | Где | Пометка | Правка |
|---|---|---|---|
| Предыдущий день | `analytics_screen.dart:64` |  |  |
| Следующий день | `analytics_screen.dart:64` |  |  |
| Предыдущая неделя | `analytics_screen.dart:65` |  |  |
| Следующая неделя | `analytics_screen.dart:65` |  |  |
| Предыдущий месяц | `analytics_screen.dart:66` |  |  |
| Следующий месяц | `analytics_screen.dart:66` |  |  |
| Предыдущий год | `analytics_screen.dart:67` |  |  |
| Следующий год | `analytics_screen.dart:67` |  |  |
| Следующий период | `analytics_screen.dart:68` |  |  |
| Предыдущий период | `analytics_screen.dart:68` |  |  |
| Операций пока нет. Добавьте первую — и здесь появится статистика | `analytics_screen.dart:440` |  |  |
| За этот период операций нет | `analytics_screen.dart:441` |  |  |
| Не удалось посчитать итоги за период | `analytics_screen.dart:467` |  |  |
| Загрузка итогов | `analytics_screen.dart:491` |  |  |
| Категории | `analytics_texts.dart:30` |  |  |
| Динамика | `analytics_texts.dart:31` |  |  |
| Сравнение | `analytics_texts.dart:32` |  |  |
| Операции | `analytics_texts.dart:33` |  |  |
| в {…}{yearSuffix} | `analytics_texts.dart:52` |  |  |
| в {…} году | `analytics_texts.dart:54` |  |  |
| Расходы | `analytics_texts.dart:67` |  |  |
| Доходы | `analytics_texts.dart:67` |  |  |
| меньше 1 процента | `analytics_texts.dart:102` |  |  |
| плюс  | `analytics_texts.dart:105` |  |  |
| минус  | `analytics_texts.dart:107` |  |  |
| {…} {what} не было | `analytics_texts.dart:124` |  |  |
| столько же, сколько {phrase} | `analytics_texts.dart:127` |  |  |
| на {money} {word}, {percentText}, чем {phrase} | `analytics_texts.dart:137` |  |  |
| на {money} {word} {percentText}, чем {phrase} | `analytics_texts.dart:138` |  |  |
| {now} · было {…} | `analytics_texts.dart:157` |  |  |
| раньше не было | `analytics_texts.dart:165` |  |  |
| = столько же | `analytics_texts.dart:167` |  |  |
| {arrow} на {amount} ({…}) | `analytics_texts.dart:172` |  |  |
| {name}, {now}, раньше не было | `analytics_texts.dart:183` |  |  |
| {name}, {now}, раньше было {…}, {percentText} | `analytics_texts.dart:189` |  |  |
| {name}, {now}, столько же | `analytics_texts.dart:192` |  |  |
| За этот период расходов нет | `analytics_texts.dart:206` |  |  |
| За этот период доходов нет | `analytics_texts.dart:207` |  |  |
| Крупные расходы | `analytics_texts.dart:211` |  |  |
| Крупные доходы | `analytics_texts.dart:211` |  |  |
| Частота и средний чек ${type == TransactionType.expense ?  | `analytics_texts.dart:215` |  |  |
| Чаще всего {_emDash} {name} ({…}) | `analytics_texts.dart:226` |  |  |
| {…} · средний чек {…} | `analytics_texts.dart:234` |  |  |
| {name}, {…}, средний чек {…} | `analytics_texts.dart:244` |  |  |
| Подсказки по расходам | `analytics_texts.dart:248` |  |  |
| за предыдущие {days} ${pluralRu(days,  | `analytics_texts.dart:269` |  |  |
| вчера за весь день | `analytics_texts.dart:273` |  |  |
| за всю прошлую неделю | `analytics_texts.dart:274` |  |  |
| за весь {…}${start.year == today.year ?  :  | `analytics_texts.dart:276` |  |  |
| за весь {…} год | `analytics_texts.dart:278` |  |  |
| {name}: уже потрачено {now}, больше, чем {tail}, {before} | `analytics_texts.dart:308` |  |  |
| {name}: уже потрачено {now} {_emDash} больше, чем {tail} ({before}) | `analytics_texts.dart:309` |  |  |
| {…}: средний чек на {percent} ${hint.percent > 0 ?  | `analytics_texts.dart:316` |  |  |
| Больше всего тратите по {day}, {percent} расходов | `analytics_texts.dart:325` |  |  |
| Больше всего тратите по {day} {_emDash} {percent} расходов | `analytics_texts.dart:326` |  |  |
| В среднем {…} ${step == BucketStep.month ?  | `analytics_texts.dart:343` |  |  |
| Если тратить так же, к {…} будет ${spoken ?  | `analytics_texts.dart:354` |  |  |
| ЯФМАМИИАСОНД | `analytics_texts.dart:379` |  |  |
| Выберите неделю, месяц, год или свой период — здесь появятся столбики по дням | `analytics_texts.dart:434` |  |  |
| По месяцам | `analytics_texts.dart:439` |  |  |
| По дням | `analytics_texts.dart:439` |  |  |
| Больше всего {…}: {…} | `analytics_texts.dart:475` |  |  |
| за {…}${start.year == today.year ?  :  | `analytics_texts.dart:493` |  |  |
| за {…} год | `analytics_texts.dart:496` |  |  |
| за {…} | `analytics_texts.dart:501` |  |  |
| с {…} {…} по {…} {…} | `analytics_texts.dart:504` |  |  |
| с {from} по {…}{year} | `analytics_texts.dart:513` |  |  |
| Все категории | `analytics_texts.dart:518` |  |  |
| Категория | `analytics_texts.dart:519` |  |  |
| В архиве | `analytics_texts.dart:522` |  |  |
| Категория: {name}, изменить | `analytics_texts.dart:525` |  |  |
| В категории «{name}» за этот период ${type == TransactionType.expense ?  | `analytics_texts.dart:530` |  |  |
| День | `analytics_texts.dart:535` |  |  |
| Неделя | `analytics_texts.dart:536` |  |  |
| Месяц | `analytics_texts.dart:537` |  |  |
| Год | `analytics_texts.dart:538` |  |  |
| Свой период | `analytics_texts.dart:539` |  |  |
| Свой период\u2026 | `analytics_texts.dart:543` |  |  |
| Период: {name}, изменить | `analytics_texts.dart:554` |  |  |
| минус {…} | `category_breakdown_card.dart:209` |  |  |
| плюс {…} | `category_breakdown_card.dart:209` |  |  |
| Диаграмма {what} по категориям. {label}: {totalSpoken} | `category_breakdown_card.dart:237` |  |  |
| Остальное | `category_breakdown_card.dart:246` |  |  |
| Без подкатегории | `category_breakdown_screen.dart:27` |  |  |
| Неизвестная подкатегория | `category_breakdown_screen.dart:28` |  |  |
| Не удалось посчитать итоги категории | `category_breakdown_screen.dart:137` |  |  |
| За этот период в категории операций нет | `category_breakdown_screen.dart:167` |  |  |
| Всего за период | `category_breakdown_screen.dart:219` |  |  |
| Диаграмма по подкатегориям. Всего: {…} | `category_breakdown_screen.dart:244` |  |  |
| Доход  | `category_breakdown_screen.dart:313` |  |  |
| Расход  | `category_breakdown_screen.dart:313` |  |  |
| Всего | `category_breakdown_screen.dart:340` |  |  |
| Баланс | `period_summary_card.dart:79` |  |  |
| Операций: {…} | `period_summary_card.dart:87` |  |  |

### Баланс: счета, переводы, история счетов

| Текст | Где | Пометка | Правка |
|---|---|---|---|
| Счета | `account_texts.dart:13` |  |  |
| Всего на счетах | `account_texts.dart:14` |  |  |
| Добавьте счёт: карту, наличные, вклад — и укажите, сколько на нём сейчас | `account_texts.dart:16` |  |  |
| Добавить счёт | `account_texts.dart:17` |  |  |
| Ещё | `account_texts.dart:18` |  |  |
| Не удалось загрузить счета | `account_texts.dart:19` |  |  |
| Новый счёт | `account_texts.dart:22` |  |  |
| Изменить счёт | `account_texts.dart:23` | Р3 |  |
| Название | `account_texts.dart:24` |  |  |
| Например, Карта | `account_texts.dart:25` |  |  |
| Иконка | `account_texts.dart:26` |  |  |
| Сколько на счёте сейчас | `account_texts.dart:27` |  |  |
| Можно оставить пустым — будет 0 | `account_texts.dart:28` |  |  |
| Минус (долг) | `account_texts.dart:29` |  |  |
| Например, долг по кредитной карте | `account_texts.dart:30` |  |  |
| Сохранить | `account_texts.dart:31` |  |  |
| Валюта | `account_texts.dart:32` |  |  |
| У счёта с этой валютой другое число знаков после запятой | `account_texts.dart:34` |  |  |
| {…} — не меняется | `account_texts.dart:43` |  |  |
| Остаток | `account_texts.dart:46` |  |  |
| Изменить | `account_texts.dart:47` |  |  |
| Поправить остаток | `account_texts.dart:48` |  |  |
| В архив | `account_texts.dart:49` |  |  |
| Операции не изменятся — поменяется только стартовый остаток счёта | `account_texts.dart:52` |  |  |
| Отмена | `account_texts.dart:53` |  |  |
| Вернуть | `account_texts.dart:54` | Р1 |  |
| Счёт с таким именем уже есть. Переименуйте его или оставьте этот в архиве | `account_texts.dart:56` | Р9 |  |
| Вернуть из архива | `account_texts.dart:59` |  |  |
| Архив ({count}) | `account_texts.dart:61` |  |  |
| Счёт «{name}» снова в списке | `account_texts.dart:63` |  |  |
| Порядок счетов | `account_texts.dart:66` |  |  |
| Перетащите счёт за значок справа | `account_texts.dart:67` |  |  |
| {name}: позиция {position} из {total} | `account_texts.dart:70` |  |  |
| Операции | `account_texts.dart:72` |  |  |
| {name} — основной счёт | `account_texts.dart:75` |  |  |
| Вернуть «{name}» из архива | `account_texts.dart:78` |  |  |
| Удалить | `account_texts.dart:81` |  |  |
| Удалить «{name}» | `account_texts.dart:85` |  |  |
| Удалить счёт «{name}»? | `account_texts.dart:87` |  |  |
| Счёт удалится насовсем. | `account_texts.dart:97` |  |  |
| К счёту ${pluralRu(transactions,  | `account_texts.dart:100` |  |  |
| Перевод с этим счётом (1) будет удалён. Остаток другого счёта изменится на сумму этого перевода. | `account_texts.dart:108` |  |  |
| Переводы с этим счётом ({transfers}) будут удалены. Остатки других счетов изменятся на сумму этих переводов. | `account_texts.dart:110` |  |  |
| Счёт «{name}» удалён | `account_texts.dart:116` |  |  |
| Не удалось удалить счёт. Ничего не изменилось | `account_texts.dart:119` |  |  |
| Основной счёт теперь «{name}» | `account_texts.dart:122` |  |  |
| Основной | `account_texts.dart:125` |  |  |
| Сделать основным | `account_texts.dart:126` |  |  |
| Основной счёт — выбирается сам при вводе операции | `account_texts.dart:128` |  |  |
| Отправить «{name}» в архив? | `account_texts.dart:130` |  |  |
| На счёте {…}. Счёт в архиве не входит во «Всего на счетах». Операции счёта сохранятся | `account_texts.dart:137` | Р4 |  |
| Счёт «{name}» в архиве | `account_texts.dart:140` |  |  |
| Иконка: {label} | `account_texts.dart:144` |  |  |
| Введите название счёта | `account_texts.dart:151` |  |  |
| Название слишком длинное: не больше {accountNameMaxLength} символов | `account_texts.dart:153` |  |  |
| Такой счёт уже есть. Выберите другое название | `account_texts.dart:156` |  |  |
| Выберите иконку | `account_texts.dart:160` |  |  |
| плюс {spoken} | `account_texts.dart:187` |  |  |
| Своя валюта | `account_texts.dart:200` |  |  |
| Код и число знаков после запятой потом не поменять | `account_texts.dart:202` |  |  |
| Код | `account_texts.dart:203` |  |  |
| Например, ABC | `account_texts.dart:204` |  |  |
| Код — от 3 до 10 латинских букв и цифр, первая — буква | `account_texts.dart:206` |  |  |
| Знаков после запятой | `account_texts.dart:207` |  |  |
| От 0 до 8 | `account_texts.dart:208` |  |  |
| Введите число от 0 до 8 | `account_texts.dart:209` |  |  |
| Готово | `account_texts.dart:210` |  |  |
| Как у счёта «{name}» | `account_texts.dart:213` |  |  |
| Есть в списке: {name}. Знаков после запятой: {digits} | `account_texts.dart:217` |  |  |
| Перевод | `account_texts.dart:220` | Р2 |  |
| Новый перевод | `account_texts.dart:221` |  |  |
| Правка перевода | `account_texts.dart:222` | Р3 |  |
| Откуда | `account_texts.dart:223` |  |  |
| Куда | `account_texts.dart:224` |  |  |
| Сумма перевода | `account_texts.dart:225` |  |  |
| Комментарий (необязательно) | `account_texts.dart:226` |  |  |
| Выберите, куда перевести | `account_texts.dart:228` |  |  |
| Изменения сохранены | `account_texts.dart:229` |  |  |
| Отменить | `account_texts.dart:230` | Р1 |  |
| Не удалось сохранить. Попробуйте ещё раз | `account_texts.dart:232` |  |  |
| Не удалось отменить. Попробуйте ещё раз | `account_texts.dart:233` |  |  |
| Сумма перевода должна быть больше нуля | `account_texts.dart:236` |  |  |
| {name} (в архиве) | `account_texts.dart:239` |  |  |
| Перевод {…}: {from} → {to} | `account_texts.dart:247` |  |  |
| Перевод {…} со счёта {from} на счёт {to} | `account_texts.dart:256` |  |  |
| Переводы | `account_texts.dart:259` |  |  |
| Удалить перевод | `account_texts.dart:261` |  |  |
| Перевод удалён | `account_texts.dart:262` |  |  |
| Не удалось удалить. Попробуйте ещё раз | `account_texts.dart:264` |  |  |
| другой счёт | `account_texts.dart:267` |  |  |
| Перевод на счёт {name}, {…} | `account_texts.dart:302` |  |  |
| Перевод со счёта {name}, плюс {…} | `account_texts.dart:303` |  |  |
| Валюта изменилась — выберите счёт и введите сумму | `account_texts.dart:309` |  |  |
| Нужны два счёта в одной валюте | `account_texts.dart:312` |  |  |
| История счетов | `account_texts.dart:316` |  |  |
| Здесь появятся новые счета, переводы и счета, отправленные в архив | `account_texts.dart:319` |  |  |
| Не удалось загрузить историю. Попробуйте открыть экран ещё раз | `account_texts.dart:321` |  |  |
| Создан счёт «{name}» | `account_texts.dart:323` |  |  |
| Счёт «{name}» отправлен в архив | `account_texts.dart:325` |  |  |
| Создан счёт {name}, {day} | `account_texts.dart:328` |  |  |
| Счёт {name} отправлен в архив, {day} | `account_texts.dart:331` |  |  |
| Перевод со счёта {from} на счёт {to}, {…}, {day}${note == null ?  :  | `account_texts.dart:347` |  |  |

### Регулярные платежи и «К оплате»

| Текст | Где | Пометка | Правка |
|---|---|---|---|
| Не удалось сохранить. Попробуйте ещё раз | `recurring_rule_text.dart:7` |  |  |
| Введите название платежа | `recurring_rule_text.dart:19` | Р7 |  |
| Название слишком длинное: не больше {recurringTitleMaxLength} символов | `recurring_rule_text.dart:21` | Р7 |  |
| Сумма должна быть больше нуля | `recurring_rule_text.dart:24` |  |  |
| Повтор: от {recurringEveryMin} до {recurringEveryMax} | `recurring_rule_text.dart:26` |  |  |
| Дата окончания раньше даты первого платежа | `recurring_rule_text.dart:28` | Р7 |  |
| Эта категория из другого вида: она для {categoryFor}, а вы вводите {entered}. Выберите другую категорию | `recurring_rule_text.dart:34` | Р6 |  |
| Эта подкатегория относится к другой категории. Выберите подкатегорию заново или нажмите «Без подкатегории» | `recurring_rule_text.dart:37` |  |  |
| Эта категория в архиве. Выберите другую | `recurring_rule_text.dart:40` |  |  |
| Этот счёт в архиве. Выберите другой счёт или «Без счёта» | `recurring_rule_text.dart:42` |  |  |
| Валюта счёта не совпадает с валютой платежа. Выберите другой счёт | `recurring_rule_text.dart:44` |  |  |
| Доход | `reminder_plan.dart:151` |  |  |
| Расход | `reminder_plan.dart:151` |  |  |
| Поступление сегодня: {…} | `reminder_plan.dart:162` |  |  |
| Платёж сегодня: {…} | `reminder_plan.dart:163` |  |  |
| Регулярные платежи | `recurring_texts.dart:15` |  |  |
| Добавить платёж | `recurring_texts.dart:18` |  |  |
| Добавьте то, что платите регулярно: связь, подписки, аренду. В день платежа Zuno напомнит о нём | `recurring_texts.dart:22` |  |  |
| Завершён | `recurring_texts.dart:26` |  |  |
| Новый платёж | `recurring_texts.dart:30` |  |  |
| Название | `recurring_texts.dart:31` |  |  |
| Например, Интернет | `recurring_texts.dart:32` |  |  |
| Вид платежа | `recurring_texts.dart:35` | Р6 |  |
| Категория | `recurring_texts.dart:36` |  |  |
| Выберите категорию | `recurring_texts.dart:37` |  |  |
| Счёт | `recurring_texts.dart:38` |  |  |
| Без счёта | `recurring_texts.dart:39` |  |  |
| Повтор | `recurring_texts.dart:40` |  |  |
| Первый платёж | `recurring_texts.dart:41` |  |  |
| Окончание | `recurring_texts.dart:42` |  |  |
| Напомнить в день платежа | `recurring_texts.dart:43` |  |  |
| Уведомления для Zuno выключены. Включите их в настройках телефона, иначе напоминаний не будет. | `recurring_texts.dart:45` | Р4 |  |
| Открыть настройки | `recurring_texts.dart:47` |  |  |
| Без окончания | `recurring_texts.dart:48` |  |  |
| Убрать окончание | `recurring_texts.dart:49` |  |  |
| Сохранить | `recurring_texts.dart:50` |  |  |
| Введите название | `recurring_texts.dart:53` | Р7 |  |
| Название — не длиннее 40 символов | `recurring_texts.dart:54` | Р7 |  |
| Окончание не может быть раньше первого платежа | `recurring_texts.dart:57` | Р7 |  |
| Каждый месяц | `recurring_texts.dart:64` |  |  |
| Каждую неделю | `recurring_texts.dart:65` |  |  |
| Каждые 2 недели | `recurring_texts.dart:66` |  |  |
| Каждые 3 месяца | `recurring_texts.dart:67` |  |  |
| Каждые 6 месяцев | `recurring_texts.dart:68` |  |  |
| Каждый год | `recurring_texts.dart:69` |  |  |
| В месяцы, где нет {day}-го, — в последний день месяца | `recurring_texts.dart:74` |  |  |
| Каждые {n} ${_plural(n,  | `recurring_texts.dart:116` |  |  |
| {head}, по {…} | `recurring_texts.dart:117` |  |  |
| {head}, {…}-го | `recurring_texts.dart:122` |  |  |
| {…} · следующий {…} | `recurring_texts.dart:135` |  |  |
| {head}, завершён | `recurring_texts.dart:148` |  |  |
| {head}, {repeat}, следующий {…} | `recurring_texts.dart:152` |  |  |
| Платёж | `recurring_texts.dart:157` | Р3 |  |
| Удалить платёж | `recurring_texts.dart:158` |  |  |
| Уже внесённые операции останутся в «Истории» | `recurring_texts.dart:160` |  |  |
| Отменить | `recurring_texts.dart:161` | Р1 |  |
| Платёж «{title}» удалён | `recurring_texts.dart:164` |  |  |
| Не удалось удалить. Попробуйте ещё раз | `recurring_texts.dart:167` |  |  |
| К оплате | `recurring_texts.dart:171` |  |  |
| Оплачено | `recurring_texts.dart:172` |  |  |
| Пропустить | `recurring_texts.dart:173` |  |  |
| Изменить | `recurring_texts.dart:174` |  |  |
| Сумма | `recurring_texts.dart:175` |  |  |
| Дата | `recurring_texts.dart:176` |  |  |
| Оплата: {title} | `recurring_texts.dart:183` |  |  |
| Сегодня | `recurring_texts.dart:188` |  |  |
| Вчера | `recurring_texts.dart:189` |  |  |
| Платёж «{title}» за {…} пропущен | `recurring_texts.dart:219` |  |  |
| {dueSectionTitleBase}: {…}, {spoken}. Открыть | `recurring_texts.dart:252` |  |  |
| {dueSectionTitleBase} {…}. Открыть | `recurring_texts.dart:255` |  |  |
| к оплате: {count} | `recurring_texts.dart:262` |  |  |
| Категория «{name}» в архиве — выберите другую | `recurring_texts.dart:266` |  |  |
| Подкатегория «{name}» в архиве — выберите другую | `recurring_texts.dart:270` |  |  |
| Счёт «{name}» в архиве — выберите другой | `recurring_texts.dart:272` |  |  |

### Категории по умолчанию (первый запуск)

| Текст | Где | Пометка | Правка |
|---|---|---|---|
| Продукты | `default_categories.dart:31` |  |  |
| Кафе | `default_categories.dart:36` |  |  |
| Транспорт | `default_categories.dart:41` |  |  |
| Дом | `default_categories.dart:44` |  |  |
| Здоровье | `default_categories.dart:47` |  |  |
| Одежда | `default_categories.dart:52` |  |  |
| Развлечения | `default_categories.dart:57` |  |  |
| Связь | `default_categories.dart:62` |  |  |
| Подарки | `default_categories.dart:67` |  |  |
| Прочее | `default_categories.dart:72` |  |  |
| Зарплата | `default_categories.dart:78` |  |  |
| Подработка | `default_categories.dart:83` |  |  |
| Подарок | `default_categories.dart:88` |  |  |

### Категории

| Текст | Где | Пометка | Правка |
|---|---|---|---|
| Не удалось сохранить. Попробуйте ещё раз | `category_rule_text.dart:6` |  |  |
| Введите название подкатегории | `category_rule_text.dart:21` |  |  |
| Введите название категории | `category_rule_text.dart:22` |  |  |
| Название слишком длинное: не больше {categoryNameMaxLength} символов | `category_rule_text.dart:24` |  |  |
| Выберите иконку | `category_rule_text.dart:27` |  |  |
| Такая подкатегория уже есть. Выберите другое название | `category_rule_text.dart:30` |  |  |
| Такая категория уже есть. Выберите другое название | `category_rule_text.dart:31` |  |  |
| В списке уже есть категория с таким названием. Переименуйте её или оставьте эту в архиве | `category_rule_text.dart:43` |  |  |
| В списке уже есть подкатегория с таким названием. Переименуйте её или оставьте эту в архиве | `category_rule_text.dart:48` |  |  |
| Не удалось загрузить подкатегории | `category_rule_text.dart:53` |  |  |
| Категории | `categories_screen.dart:25` |  |  |
| Расходы | `categories_screen.dart:28` |  |  |
| Доходы | `categories_screen.dart:29` |  |  |
| Добавить категорию | `categories_screen.dart:32` |  |  |
| Категория «{name}» в архиве | `categories_screen.dart:35` |  |  |
| Старые операции по этим категориям сохранены | `categories_screen.dart:38` |  |  |
| Категорий пока нет | `categories_screen.dart:41` |  |  |
| Не удалось загрузить категории | `categories_screen.dart:44` |  |  |
| Новая категория | `category_form_screen.dart:19` |  |  |
| Изменить категорию | `category_form_screen.dart:20` | Р3 |  |
| Новая подкатегория · {parentName} | `category_form_screen.dart:22` |  |  |
| Изменить подкатегорию | `category_form_screen.dart:23` | Р3 |  |
| Название | `category_form_screen.dart:26` |  |  |
| Тип | `category_form_screen.dart:27` | Р6 |  |
| Расход | `category_form_screen.dart:28` |  |  |
| Доход | `category_form_screen.dart:29` |  |  |
| Иконка | `category_form_screen.dart:30` |  |  |
| Сохранить | `category_form_screen.dart:31` |  |  |
| Иконка: {iconName} | `category_form_screen.dart:39` |  |  |
| В архив | `category_list.dart:10` |  |  |
| Вернуть из архива | `category_list.dart:11` |  |  |
| Подкатегории | `category_list.dart:12` |  |  |
| Вернуть | `category_list.dart:15` | Р1 |  |
| Подкатегорий: {count} | `category_list.dart:23` |  |  |
| Архив ({count}) | `category_list.dart:26` |  |  |
| {name}: позиция {position} из {total} | `category_list.dart:30` |  |  |
| Добавить подкатегорию | `subcategories_screen.dart:16` |  |  |
| Подкатегория «{name}» в архиве | `subcategories_screen.dart:20` |  |  |
| Старые операции по этим подкатегориям сохранены | `subcategories_screen.dart:24` |  |  |
| Подкатегорий пока нет. Нажмите «{subcategoriesAddAction}» внизу, чтобы создать первую. | `subcategories_screen.dart:28` | Р4 |  |

### Настройки

| Текст | Где | Пометка | Правка |
|---|---|---|---|
| Отмена | `reminder_time_wheel.dart:7` |  |  |
| Готово | `reminder_time_wheel.dart:8` |  |  |
| Внешний вид | `settings_screen.dart:19` |  |  |
| Кольцо на «Главной» | `settings_screen.dart:20` |  |  |
| Учёт | `settings_screen.dart:21` |  |  |
| Данные | `settings_screen.dart:22` |  |  |
| Сброс | `settings_screen.dart:23` |  |  |
| Системная | `settings_screen.dart:26` |  |  |
| Светлая | `settings_screen.dart:27` |  |  |
| Тёмная | `settings_screen.dart:28` |  |  |
| Тема | `settings_screen.dart:31` |  |  |
| Вторая строка в кольце | `settings_screen.dart:34` |  |  |
| За всё время | `settings_screen.dart:35` |  |  |
| Все доходы минус все расходы | `settings_screen.dart:36` |  |  |
| На счетах | `settings_screen.dart:37` |  |  |
| Счета в основной валюте | `settings_screen.dart:38` |  |  |
| Скрыть суммы | `settings_screen.dart:41` |  |  |
| Вместо цифр — облачко, как в банковских приложениях | `settings_screen.dart:43` |  |  |
| Не показывать | `settings_screen.dart:44` |  |  |
| Категории | `settings_screen.dart:47` |  |  |
| Основная валюта | `settings_screen.dart:50` |  |  |
| Сделать основной валютой «{name}»? | `settings_screen.dart:54` |  |  |
| Новые доходы и расходы будут вноситься в этой валюте. В быстрый ввод попадут только счета в этой валюте. «Главная», «История» и «Аналитика» покажут только операции в ней. Операции в других валютах сохранятся и снова появятся, если вернуть их валюту. | `settings_screen.dart:56` |  |  |
| Сменить | `settings_screen.dart:62` |  |  |
| Время напоминаний | `settings_screen.dart:65` |  |  |
| Экспорт в CSV | `settings_screen.dart:68` | Р8 |  |
| Не удалось подготовить файл экспорта. Файл не создан | `settings_screen.dart:72` |  |  |
| Не удалось открыть окно «Поделиться». Файл не отправлен | `settings_screen.dart:76` |  |  |
| Готовим файл | `settings_screen.dart:79` |  |  |
| Загрузить из CSV | `settings_screen.dart:82` | Р8 |  |
| Добавить операции из файла | `settings_screen.dart:83` |  |  |
| Не удалось открыть файл. Попробуйте ещё раз | `settings_screen.dart:86` |  |  |
| Загружена | `settings_screen.dart:91` |  |  |
| Загружены | `settings_screen.dart:91` |  |  |
| Загружено | `settings_screen.dart:91` |  |  |
| регулярные платежи: {…} | `settings_screen.dart:102` |  |  |
| Добавлены {tail} | `settings_screen.dart:106` |  |  |
| Создан | `settings_screen.dart:116` |  |  |
| Созданы | `settings_screen.dart:116` |  |  |
| Создано | `settings_screen.dart:116` |  |  |
| Загружен | `settings_screen.dart:127` |  |  |
| {…} и {transferText} | `settings_screen.dart:130` |  |  |
| Очистить всё | `settings_screen.dart:140` |  |  |
| Стереть операции, категории и счета | `settings_screen.dart:141` |  |  |
| Стереть все операции, категории и счета? | `settings_screen.dart:144` |  |  |
| Это действие нельзя отменить. Восстановить данные можно только из файла экспорта CSV. | `settings_screen.dart:146` |  |  |
| Сначала экспорт | `settings_screen.dart:148` |  |  |
| Стереть всё | `settings_screen.dart:150` |  |  |
| Данные стёрты. Категории — как при первом запуске | `settings_screen.dart:153` |  |  |
| Не удалось стереть данные. Ничего не изменилось | `settings_screen.dart:154` |  |  |
| Стираем данные | `settings_screen.dart:157` |  |  |
| Версия {…} ({…}) | `settings_screen.dart:163` |  |  |
| Версия {version} | `settings_screen.dart:164` |  |  |
| Последний экспорт: ещё не было | `settings_screen.dart:176` | Р5 |  |
| Последний экспорт: {text} | `settings_screen.dart:178` |  |  |
| Последний экспорт: ещё не было — сделайте копию | `settings_screen.dart:198` | Р5 |  |
| {…} — давно, сделайте копию | `settings_screen.dart:199` |  |  |

### Загрузка из CSV

| Текст | Где | Пометка | Правка |
|---|---|---|---|
| регулярный расход | `parse_csv_import.dart:415` |  |  |
| регулярный доход | `parse_csv_import.dart:416` |  |  |
| Загрузка из CSV | `csv_import_texts.dart:21` | Р8 |  |
| Проверяем файл… | `csv_import_texts.dart:22` |  |  |
| Загружаем… | `csv_import_texts.dart:23` |  |  |
| Загрузить | `csv_import_texts.dart:24` |  |  |
| Отмена | `csv_import_texts.dart:25` |  |  |
| Закрыть | `csv_import_texts.dart:26` |  |  |
| Не удалось прочитать файл. Попробуйте выбрать его ещё раз | `csv_import_texts.dart:29` |  |  |
| Не удалось загрузить. Ничего не добавлено, попробуйте ещё раз | `csv_import_texts.dart:31` |  |  |
| В файле есть ошибки, поэтому ничего не загружено. Исправьте их в файле и загрузите его снова. | `csv_import_texts.dart:33` | Р4 |  |
| В файле нет операций: есть только строка с названиями колонок | `csv_import_texts.dart:36` |  |  |
| Нечего добавлять: всё из файла уже есть в приложении | `csv_import_texts.dart:38` |  |  |
| Будут созданы категории | `csv_import_texts.dart:39` |  |  |
| Будут созданы счета | `csv_import_texts.dart:40` |  |  |
| … и ещё {…} | `csv_import_texts.dart:56` |  |  |
| Будет добавлена | `csv_import_texts.dart:63` |  |  |
| Будут добавлены | `csv_import_texts.dart:64` |  |  |
| Будет добавлено | `csv_import_texts.dart:65` |  |  |
| Будет добавлен | `csv_import_texts.dart:76` |  |  |
| Будут добавлены регулярные платежи: {…} | `csv_import_texts.dart:86` |  |  |
| Будет создан | `csv_import_texts.dart:92` |  |  |
| Будут созданы | `csv_import_texts.dart:93` |  |  |
| Будет создано | `csv_import_texts.dart:94` |  |  |
| {…} (остаток {text}) | `csv_import_texts.dart:111` |  |  |
| {…}, остаток {text} | `csv_import_texts.dart:119` |  |  |
| Пропущено (уже есть в приложении): {…} | `csv_import_texts.dart:146` |  |  |
| Пропущено (удалены в приложении): {…} | `csv_import_texts.dart:149` |  |  |
| Расходы | `csv_import_texts.dart:170` |  |  |
| Доходы | `csv_import_texts.dart:171` |  |  |
| {name} (новая) | `csv_import_texts.dart:200` |  |  |
| Файл сохранён не в той кодировке. В Excel сохраните его заново: «Файл» → «Сохранить как» → тип «CSV UTF-8 (разделитель - запятая)» | `csv_import_texts.dart:207` |  |  |
| Не получилось разобрать файл: похоже, в нём не закрыта кавычка. Откройте его в таблице и сохраните заново как CSV | `csv_import_texts.dart:210` |  |  |
| Файл пустой | `csv_import_texts.dart:212` |  |  |
| Колонка «{column}» встречается в первой строке дважды. Оставьте одну | `csv_import_texts.dart:218` |  |  |
| Строка {…}: {…} | `csv_import_texts.dart:223` |  |  |
| не указана дата | `csv_import_texts.dart:230` |  |  |
| дата {value} — нужна настоящая дата в виде ДД.ММ.ГГГГ | `csv_import_texts.dart:231` |  |  |
| дата {value} ещё не наступила | `csv_import_texts.dart:232` |  |  |
| не указан тип | `csv_import_texts.dart:235` |  |  |
| тип {value} — нужен «{csvTypeExpense}», «{csvTypeIncome}», «{csvTypeRecurringExpense}», «{csvTypeRecurringIncome}», «{csvTypeOpeningBalance}» или «{csvTypeTransfer}» | `csv_import_texts.dart:236` |  |  |
| не указана сумма | `csv_import_texts.dart:241` |  |  |
| сумма {value} — {…} | `csv_import_texts.dart:242` |  |  |
| сумма {value} — минус можно ставить только у расхода и начального остатка | `csv_import_texts.dart:244` |  |  |
| валюта {value} — у расхода и дохода нужен код обычной валюты, например RUB или USD, или пусто | `csv_import_texts.dart:247` |  |  |
| код валюты {value} — нужно 3–10 латинских букв и цифр, первая — буква, например USD или USDT | `csv_import_texts.dart:250` |  |  |
| счёт длиннее {accountNameMaxLength} символов | `csv_import_texts.dart:252` |  |  |
| у начального остатка не указан счёт | `csv_import_texts.dart:253` |  |  |
| у начального остатка категория {value} — ячейка должна быть пустой. Похоже, колонки съехали | `csv_import_texts.dart:255` |  |  |
| второй начальный остаток счёта {…} (первый — в строке {firstLine}). Оставьте одну строку | `csv_import_texts.dart:258` |  |  |
| валюта {…} не совпадает с валютой счёта {…} — у него {accountCurrency} | `csv_import_texts.dart:261` |  |  |
| счёт с ID «{…}» не найден. Укажите имя счёта в колонке «{csvColumnTransferAccount}» | `csv_import_texts.dart:265` |  |  |
| перевод в валюте {…}: в файле нет начального остатка счёта в этой валюте | `csv_import_texts.dart:268` |  |  |
| в колонке «{column}» стоит {value} — у обычной операции она должна быть пустой. Похоже, колонки съехали | `csv_import_texts.dart:271` |  |  |
| не указан повтор — нужно «{csvRepeatWeek}», «{csvRepeatMonth}» или «{csvRepeatYear}» | `csv_import_texts.dart:275` |  |  |
| повтор {value} — нужно «{csvRepeatWeek}», «{csvRepeatMonth}» или «{csvRepeatYear}» | `csv_import_texts.dart:277` |  |  |
| в колонке «{csvColumnEvery}» ${value ??  | `csv_import_texts.dart:280` |  |  |
| в колонке «{csvColumnUntil}» {value} — нужна настоящая дата в виде ДД.ММ.ГГГГ или пусто | `csv_import_texts.dart:283` |  |  |
| в колонке «{csvColumnUntil}» {value} — это раньше даты первого платежа | `csv_import_texts.dart:286` |  |  |
| в колонке «{csvColumnRemind}» ${value ??  | `csv_import_texts.dart:288` |  |  |
| сумма {value} — у регулярного платежа нужна сумма больше нуля | `csv_import_texts.dart:291` |  |  |
| у регулярного платежа не указано название (колонка «{csvColumnNote}») | `csv_import_texts.dart:294` |  |  |
| название регулярного платежа длиннее {recurringTitleMaxLength} символов | `csv_import_texts.dart:296` |  |  |
| регулярный платёж привязан к архивному счёту {…}: верните его из архива или очистите ячейку с ID | `csv_import_texts.dart:300` |  |  |
| регулярный платёж привязан к архивной категории {…}: верните её из архива или очистите ячейку с ID | `csv_import_texts.dart:303` |  |  |
| регулярный платёж привязан к архивной подкатегории {…}: верните её из архива или очистите ячейку с ID | `csv_import_texts.dart:306` |  |  |
| у перевода не указан счёт | `csv_import_texts.dart:309` |  |  |
| у перевода не указан счёт зачисления | `csv_import_texts.dart:310` |  |  |
| у перевода счёт и счёт зачисления совпадают | `csv_import_texts.dart:311` |  |  |
| сумма {value} — у перевода нужна сумма больше нуля | `csv_import_texts.dart:313` |  |  |
| у перевода категория {value} — ячейка должна быть пустой. Похоже, колонки съехали | `csv_import_texts.dart:315` |  |  |
| счёт с ID «{…}» не найден. Укажите имя счёта в колонке «{csvColumnAccount}» | `csv_import_texts.dart:318` |  |  |
| не указана категория | `csv_import_texts.dart:320` |  |  |
| категория длиннее {categoryNameMaxLength} символов | `csv_import_texts.dart:321` |  |  |
| подкатегория длиннее {categoryNameMaxLength} символов | `csv_import_texts.dart:323` |  |  |
| комментарий длиннее {transactionNoteMaxLength} символов | `csv_import_texts.dart:325` |  |  |
| в колонке «{…}» не ID. Очистите эту ячейку | `csv_import_texts.dart:327` |  |  |
| «{csvColumnTransactionId}» повторяется: такой уже есть выше в файле | `csv_import_texts.dart:329` |  |  |
| «{csvColumnCategoryId}» указывает на категорию другого типа (доход вместо расхода или наоборот). Очистите эту ячейку | `csv_import_texts.dart:331` |  |  |
| «{csvColumnCategoryId}» указывает на подкатегорию. Очистите эту ячейку | `csv_import_texts.dart:334` |  |  |
| «{csvColumnSubcategoryId}» указывает на подкатегорию другой категории. Очистите эту ячейку | `csv_import_texts.dart:336` |  |  |
| ячеек больше, чем колонок. Похоже, сумма или текст с запятой без кавычек: нужно "350,50" | `csv_import_texts.dart:340` |  |  |
| ячеек больше, чем колонок. Похоже, в тексте есть «;» без кавычек вокруг ячейки | `csv_import_texts.dart:342` |  |  |
| нет цифр | `csv_import_texts.dart:350` |  |  |
| не число | `csv_import_texts.dart:351` |  |  |
| лишний минус | `csv_import_texts.dart:352` |  |  |
| слишком много запятых или точек | `csv_import_texts.dart:354` |  |  |
| слишком большая (не больше {…}) | `csv_import_texts.dart:356` |  |  |
| не больше {digits} цифр после запятой | `csv_import_texts.dart:362` |  |  |
| у {…} не бывает цифр после запятой | `csv_import_texts.dart:364` |  |  |
| у {…} не больше {digits} {noun} после запятой | `csv_import_texts.dart:367` |  |  |

### Общие подписи и ошибки ввода

| Текст | Где | Пометка | Правка |
|---|---|---|---|
| Сегодня | `day_label.dart:6` |  |  |
| Вчера | `day_label.dart:7` |  |  |
| меньше 1 процента | `percent_format.dart:10` |  |  |
| Введите сумму | `amount_failure_text.dart:41` |  |  |
| Введите сумму цифрами. Пример: {…} | `amount_failure_text.dart:43` |  |  |
| Знак не нужен: доход это или расход, зависит от нажатой кнопки | `amount_failure_text.dart:45` |  |  |
| После запятой или точки — не больше двух цифр. Тысячи пишите без точки: 1234 | `amount_failure_text.dart:48` |  |  |
| В этой валюте нет дробной части: введите целое число | `amount_failure_text.dart:52` |  |  |
| Не больше {…} ${info.digits == 1 ?  | `amount_failure_text.dart:54` |  |  |
| Слишком много запятых или точек. Пример: {…} | `amount_failure_text.dart:57` |  |  |
| Слишком большая сумма (не больше {…}) | `amount_failure_text.dart:60` |  |  |
| Не больше {…} | `amount_failure_text.dart:62` |  |  |
| Не удалось загрузить данные | `async_view.dart:55` |  |  |
| Без категории | `category_labels.dart:5` |  |  |
| Валюта | `currency_picker.dart:4` |  |  |
| Код, название или символ | `currency_picker.dart:5` |  |  |
| Очистить поиск | `currency_picker.dart:6` |  |  |
| Популярные | `currency_picker.dart:7` |  |  |
| Ваши валюты | `currency_picker.dart:8` |  |  |
| Все валюты | `currency_picker.dart:9` |  |  |
| Криптовалюты | `currency_picker.dart:10` |  |  |
| Ничего не найдено | `currency_picker.dart:11` |  |  |
| Своя валюта… | `currency_picker.dart:12` |  |  |
| Если нужной нет в списке | `currency_picker.dart:13` |  |  |
| Дата операции: {…} | `date_chip.dart:44` |  |  |
| сумма скрыта | `masked_amount.dart:8` |  |  |
| Здесь только операции в основной валюте ({symbol}). Остальные появятся снова, если вернуть их валюту в «Настройках». | `other_currencies_hint.dart:6` | Р4 |  |
| Скрыть | `tap_to_dismiss_snack_content.dart:4` |  |  |
| Не удалось сохранить. Попробуйте ещё раз | `transaction_rule_text.dart:7` |  |  |
| Комментарий слишком длинный: не больше {transactionNoteMaxLength} символов | `transaction_rule_text.dart:28` |  |  |
| Выберите категорию | `transaction_rule_text.dart:31` |  |  |
| Эта категория из другого вида: она для {categoryFor}, а вы вводите {entered}. Выберите другую категорию | `transaction_rule_text.dart:37` | Р6 |  |
| Эта подкатегория относится к другой категории. Выберите подкатегорию заново или нажмите «Без подкатегории» | `transaction_rule_text.dart:40` |  |  |
| Эта категория в архиве. Выберите другую | `transaction_rule_text.dart:43` |  |  |
| Этот счёт в архиве. Выберите другой счёт или «Без счёта» | `transaction_rule_text.dart:45` |  |  |
| Валюта счёта не совпадает с валютой операции. Выберите другой счёт | `transaction_rule_text.dart:47` |  |  |
| Не удалось отменить. Попробуйте ещё раз | `undo_texts.dart:3` |  |  |

