# Архитектура и соглашения

Документ для всех, кто пишет код в репозитории. Коротко и обязательно.

## Окружение
- Godot 4.7.2: бинарь `godot` в PATH. Рендерер `gl_compatibility`.
- Импорт ресурсов: `godot --headless --path . --import` (после добавления новых PNG/CSV).
- Тесты: `tools/run_tests.sh` → `godot --headless --path . -s res://tests/run_tests.gd`. Код возврата 0 = всё зелёное.
- Скриншоты: `tools/screenshot.sh <секунд> <out.png> [аргументы игры]` — запуск под xvfb, игра сама сохраняет кадр через N секунд игрового времени (аргумент `--shot=<path> --shot-time=<sec>`), можно ускорять время `--timescale=<k>`.
- Аргументы игры после `--` (автолоад `DevTools`): `--shot=<path>`, `--shot-time=<сек игрового времени>`, `--timescale=<k>`, `--quit-after=<сек реального времени>`, `--lang=ru|en`; прочие `--key=value` читаются через `DevTools.get_arg()`.
- Симуляция баланса: `tools/simulate.sh [минут=20] [--active|--real|--idle] [--seed=N]` → headless-бот (`SimBot`, три режима игрока) играет по ядру логики, пишет `sim_out/report.md` (проверки темпа) и `sim_out/timeline*.csv`.
- API ядра (состояние, события, покупки, курсор-линза, конфиги эффектов): `docs/CORE.md`.
- Отладочные аргументы игры: `--bot[=real|idle]` (играет бот), `--ff=<сек>` (промотать на старте), `--seed=<n>`.
- Web-сборка: `tools/export_web.sh` → `build/web/`. Запуск: `python3 -m http.server -d build/web 8000`. Проверка: `tools/check_web.sh` (экспорт + headless Chrome, скриншот `shots/web.png`, код 0 = игра загрузилась).
- Windows-сборка: `tools/export_windows.sh` → `build/windows/IdleKing.exe` (pck встроен).
- Арт: `python3 tools/art/gen_art.py` → спрайты `assets/sprites/` + `manifest.json`, шрифты `fonts/`, тема `themes/`, `config/palette.json`; затем `--import`. Подробно — `docs/ART.md`.
- Запуск игры всегда с `--audio-driver Dummy` в контейнере (звука в игре нет).

## Структура
```
project.godot
config/          JSON-конфиги баланса (все числа здесь, не в коде)
i18n/strings.csv тексты интерфейса: keys,ru,en (запятая; значения с запятой — в кавычках)
assets/sprites/  PNG + manifest.json, сгенерированные tools/art/gen_art.py
fonts/           пиксельный шрифт Kotel (BMFont .fnt)
themes/          main_theme.tres + текстуры 9-slice (генерируются)
scripts/core/    логика без узлов сцены (RefCounted/Object): состояние, экономика, бой, волны, улучшения, сохранения
scripts/view/    узлы отображения: поле боя, эффекты, UI
scripts/autoload/ синглтоны (Config, Fmt, DevTools, Game)
scenes/          .tscn
tests/           тесты (run_tests.gd + test_*.gd)
tools/           скрипты: тесты, скриншоты, симуляция, экспорт, генерация арта
docs/            документация
```

## Правила кода
- Ядро (`scripts/core`) не трогает сцену, ввод, время кадра напрямую. Шаг симуляции: `tick(dt)`. Вид подписывается на сигналы ядра (`enemy_killed`, `purchased`, `unlocked` …) и рисует отклик.
- Детерминизм: случайность в ядре — через собственный `RandomNumberGenerator` с сидом в состоянии.
- Все числа баланса — из `config/*.json` через автолоад `Config`. В коде допустимы только 0, 1 и чисто визуальные константы (длительность анимации и т.п.; их тоже лучше в `config/visual.json`).
- Все строки интерфейса — через `tr("KEY")`, ключи в `i18n/strings.csv`. Никакого русского текста в .gd/.tscn.
- Числа на экране — только через `Fmt.num(x)`, время — `Fmt.time(sec)`. Ядро/инструменты без автолоадов используют статические `NumFmt`, `Num`, `ConfigLoader`.
- Цвета — только из палитры: `Config.color("brass_3")` (имена в `config/palette.json`).
- Типизированный GDScript (`var x: float`), предупреждения не игнорировать. В логе запуска не должно быть ERROR/SCRIPT ERROR.
- Новые механики — с тестом в `tests/`. Тест: файл `tests/test_*.gd`, `extends "res://tests/test_case.gd"`, методы `test_*`, проверки `assert_eq/assert_true/assert_almost/...`. Любая ошибка движка во время теста (SCRIPT ERROR, push_error) валит тест; намеренные ошибки — `expected_errors = N`.

## Числа
- double (`float`). `Fmt.num`: <1000 — до 1 знака после запятой там, где нужно; далее K, M, B, T, Qa, Qi, Sx, Sp, Oc, No, Dc; выше — `5.6e15`-нотация. NaN/inf никогда не показываются (`Num.safe`).

## Сохранения
- `user://save.json`, автосейв каждые N секунд и при выходе; версия формата в файле. Офлайн-прогресс считается при загрузке по времени отсутствия (с ограничением из конфига).
