# Idle King — стимпанк-крепость

Idle/инкрементальная игра про паровую крепость (Godot 4.7.2, GDScript, рендерер Compatibility).
Документы: `docs/ARCHITECTURE.md` (структура и правила), `DECISIONS.md` (журнал решений).

## Запуск
```bash
godot --headless --path . --import          # импорт ресурсов (после новых PNG/CSV)
godot --path . --audio-driver Dummy          # играть (нужен дисплей)
godot --path . --audio-driver Dummy -- --lang=en --timescale=4
```

## Тесты
```bash
tools/run_tests.sh                    # все тесты, код 0 = всё зелёное
tools/run_tests.sh --filter=test_fmt  # только часть
```

## Скриншот и симуляция
```bash
tools/screenshot.sh 2 shots/main.png [--timescale=10]   # кадр через 2 с игрового времени (xvfb)
tools/simulate.sh 60                                     # headless-симуляция (пока заглушка)
```

## Сборка
```bash
tools/export_web.sh       # build/web/index.html; запуск: python3 -m http.server -d build/web 8000
tools/check_web.sh        # экспорт + проверка загрузки в headless Chrome, скриншот shots/web.png
tools/export_windows.sh   # build/windows/IdleKing.exe
```

## Арт
```bash
python3 tools/art/gen_art.py   # спрайты в assets/sprites/, палитра в config/palette.json
```
