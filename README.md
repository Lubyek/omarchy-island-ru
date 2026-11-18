# Island RU

Русскоязычная версия [Island для Omarchy](https://github.com/Guilhermerisu/island): Dynamic Island, меню приложений и пункт управления в одной панели.

Это отдельный форк с ID `huesos.island`. Автор оригинального Island — Guilhermerisu. Исходная лицензия MIT сохранена; CAVA-сервис основан на работе Dave Brown, см. [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Возможности

- Русский и английский интерфейс, переключение языка без перезапуска.
- Поиск приложений и вложенных пунктов меню на русском и английском.
- Тонкая светлая обводка и контрастные цвета для тёмных тем.
- Скрытие в полноэкранном режиме: сжатие в точку и уход за верхний край.
- Появление при наведении на верхний край с растяжением и пружиной.
- Активности Codex, Claude Code, OpenCode и других CLI с приоритетом над видео, счётчиком и баннерами вопросов и завершения.
- Настоящий аудиовизуализатор CAVA в островке и плеере.

CAVA-сервис включён в этот репозиторий. Отдельный `my.cava` widget и файлы с компьютера автора не нужны. На паузе или при тишине столбики опускаются; случайная анимация не используется.

## Установка

Нужна Omarchy с системой плагинов Quickshell и командами `omarchy plugin` / `omarchy bar`.

Сначала установите CAVA:

```sh
omarchy pkg add cava
```

Установите опубликованную версию:

```sh
omarchy plugin add https://github.com/Lubyek/omarchy-island-ru.git --enable
```

Для переключения панели вручную:

```sh
omarchy bar use huesos.island
```

Если островок предлагает первоначальную настройку, нажмите его. Companion-настройка добавляет свои горячие клавиши и службу уведомлений с резервными копиями изменяемых конфигураций; выполняется только после нажатия.

## Замена прежнего Island

Если установлен `guilhermerisu.island`, после установки Island RU нажмите на островок **«Заменить прежний Island»**. Настройка:

- уберёт старые `guilhermerisu.island` и `guilhermerisu.notifications` из установленных плагинов;
- перенаправит пункты меню и горячие клавиши на `huesos.island`;
- сохранит прежние папки целиком, включая локальные изменения, в `~/.local/state/omarchy/backups/replace-island-*` (или соответствующей папке `XDG_STATE_HOME`);
- скопирует старые настройки и сочетания клавиш, если файлов новой версии ещё нет. Уже настроенная версия RU не перезаписывается. Прежний `island.json` также остаётся на месте.

Запустить ту же настройку вручную можно так:

```sh
bash ~/.config/omarchy/plugins/huesos.island/companion/install.sh
```

Если версия RU уже установлена, сначала обновите её:

```sh
omarchy plugin update huesos.island
```

Язык: **Настройки Island → Основные → Язык**.

Собственные настройки этого форка хранятся в `~/.config/omarchy/huesos-island.json`. Личные настройки автора в репозиторий не включены.

## YouTube в Chromium

Правая кнопка плеера переключает фокус на окно Chromium. Дополнительное
расширение открывает конкретную вкладку с видео и добавляет управление
следующим и предыдущим видео. Shuffle выбирает непросмотренные видео из
текущего плейлиста YouTube.

1. Зарегистрируйте локальный мост командой
   `python3 ~/.config/omarchy/plugins/huesos.island/browser/bridge.py install-host`.
2. Откройте `chrome://extensions`, включите режим разработчика и загрузите
   распакованное расширение из `~/.config/omarchy/plugins/huesos.island/browser/chromium`.
3. Обновите уже открытые вкладки YouTube. Откройте видео или плейлист и
   раскройте плеер островка.

Расширение работает на `www.youtube.com` и обменивается командами с островком
через локальный сокет.

## Активности агентов

Codex и Claude Code отслеживаются по локальным журналам. При работе
агента щелчок по островку открывает главную панель. Раздел **«Активности»**
находится под регуляторами. Щелчок по строке агента или баннеру открывает
его окно, если Island может сопоставить его с задачей. Приоритет над
плеером можно изменить в **Настройки → Дополнения → Агенты**.

Баннеры вопросов и завершения появляются и поверх полноэкранного окна.
У Codex используется Stacky. Island загружает его официальный лист кадров
с CDN OpenAI при первом обнаружении задачи Codex и сохраняет его в локальный
кэш. Встроенный пиксельный маскот доступен сразу, в том числе без сети.

Для OpenCode установите интеграцию и перезапустите его:

```sh
install -Dm644 ~/.config/omarchy/plugins/huesos.island/companion/opencode-island-activity.js \
  ~/.config/opencode/plugins/island-activity.js
```

У любой другой CLI-команды можно показать статус через обёртку:

```sh
~/.config/omarchy/plugins/huesos.island/companion/island-activity run "Сборка" npm run build
```

## Проверка звука

```sh
omarchy-shell huesos.island audioStatus
```

При работающем звуке `available` должен быть `true`, а значения массива `levels` — меняться.

## Обновление

```sh
omarchy plugin update huesos.island
```

Обновления берутся из репозитория, из которого установлен форк.

## Удаление

Предварительно посмотреть изменения:

```sh
bash ~/.config/omarchy/plugins/huesos.island/companion/uninstall.sh --dry-run
```

Удалить форк и его companion-настройку:

```sh
bash ~/.config/omarchy/plugins/huesos.island/companion/uninstall.sh
```

## Проверки перед публикацией

```sh
omarchy plugin validate .
omarchy plugin validate companion/huesos.notifications
bash -n companion/check.sh companion/install.sh companion/uninstall.sh companion/bindings.sh
python3 -m unittest discover -s tests -v
```

См. [PUBLISH.md](PUBLISH.md) для обновления репозитория и подачи в каталог. Добавление в каталог Omarchy необязательно для установки по ссылке.

Этот пакет подготовлен из работавшей локальной версии. На отдельной чистой установке Omarchy весь сценарий установки пока не проверен.
