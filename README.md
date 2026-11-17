# Island RU

Русскоязычная версия [Island для Omarchy](https://github.com/Guilhermerisu/island): Dynamic Island, меню приложений и пункт управления в одной панели.

Это отдельный форк с ID `huesos.island`. Автор оригинального Island — Guilhermerisu. Исходная лицензия MIT сохранена; CAVA-сервис основан на работе Dave Brown, см. [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Возможности

- Русский и английский интерфейс, переключение языка без перезапуска.
- Поиск приложений и вложенных пунктов меню на русском и английском.
- Тонкая светлая обводка и контрастные цвета для тёмных тем.
- Скрытие в полноэкранном режиме: сжатие в точку и уход за верхний край.
- Появление при наведении на верхний край с растяжением и пружиной.
- Настоящий аудиовизуализатор CAVA в островке, плеере и мини-плеере.

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

Язык: **Настройки Island → Основные → Язык**.

Собственные настройки этого форка хранятся в `~/.config/omarchy/huesos-island.json`. Личные настройки автора в репозиторий не включены.

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
```

См. [PUBLISH.md](PUBLISH.md) для обновления репозитория и подачи в каталог. Добавление в каталог Omarchy необязательно для установки по ссылке.

Этот пакет подготовлен из работавшей локальной версии. На отдельной чистой установке Omarchy весь сценарий установки пока не проверен.
