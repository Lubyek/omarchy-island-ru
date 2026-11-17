# Репозиторий и обновления

Публичный репозиторий: <https://github.com/Lubyek/omarchy-island-ru>.

## Установка другом

```sh
omarchy pkg add cava
omarchy plugin add https://github.com/Lubyek/omarchy-island-ru.git --enable
```

## Обновление исходников

После изменений проверьте плагин и создайте коммит:

```sh
cd ~/Work/omarchy-island-ru
omarchy plugin validate .
omarchy plugin validate companion/huesos.notifications
git add .
git commit -m "Update Island RU"
git push origin main
```

Установившие плагин по ссылке смогут обновить его командой:

```sh
omarchy plugin update huesos.island
```

## Общий каталог

Отправьте ссылку на репозиторий через форму публикации на <https://omarchyplugins.com>. Каталогу нужны публичный репозиторий, manifest, README и лицензия; появление в каталоге требует проверки и одобрения сопровождающих.

Порядок подачи: <https://github.com/omacom/omarchy-plugin-marketplace/blob/main/SUBMISSION.md>.

Установка по GitHub-ссылке доступна независимо от добавления в каталог.
