# CORE — API ядра логики (для вида, сохранений и баланса)

Ядро — `scripts/core/`, чистые `RefCounted`-классы без узлов сцены. Их одинаково гоняют игра
(автолоад `Game`), тесты (`tests/test_core.gd`) и headless-симуляция (`tools/simulate.sh`).
Решения и почему так — DECISIONS.md D-016…D-023.

| Файл | Класс | Что делает |
|---|---|---|
| `game_core.gd` | `GameCore` | фасад: tick, события, покупки, боссы, доход/с, сохранение |
| `game_state.gd` | `GameState` | всё сохраняемое: ресурсы, башни, уровни, боссы, статистика; `to_dict/from_dict` |
| `game_data.gd` | `GameData` | контент из `config/*.json` + проверка (неизвестный эффект/цель/ресурс → ошибка) |
| `mods.gd` | `Mods` | эффекты → производные статы (башни, враги, линза, ров), пересчёт с нуля |
| `battle.gd` | `Battle` | поле: враги, башни, снаряды, линза, ров, пачки, босс |
| `sim_bot.gd` | `SimBot` | бот-игрок (симуляция, тесты, `--bot` в игре) |

## Жизненный цикл

```gdscript
var core: GameCore = Game.start()      # новая игра (контент — из автолоада Config), Game тикает сам
# или вручную, без автолоадов:
var core := GameCore.create(seed)      # seed < 0 -> economy.seed
core.tick(delta)                       # любой dt; режется на шаги <= core.max_step (0.1 с)
```

`Game._process` вызывает `core.tick(delta)` каждый кадр (с учётом `Engine.time_scale`).
Отладочные аргументы: `--bot[=idle]`, `--ff=<сек>` (промотать на старте), `--seed=<n>`.

## Курсор (Паровая линза)

Каждый кадр вид передаёт позицию мыши в координатах поля и флаг «мышь над полем»:

```gdscript
core.set_cursor(mouse_pos, mouse_over_field)   # = state.cursor_pos / state.cursor_active
```

Остальное решает ядро: если курсор над полем и двигался за последние `lens.idle_to_auto` (2 с) —
линза в ручном режиме и стоит под курсором; иначе — авто (овал, урон × `auto_mult`) или «наводчик»
(плывёт к самой плотной группе). Читать: `battle.lens_pos`, `battle.lens_mode`
(`"manual" | "auto" | "seek"`), радиус `core.mods.lens["radius"]`. `battle.in_field(p)` — та же
проверка «над полем», что использует ядро.

## Что рисовать (читать каждый кадр)

Координаты поля = пиксели экрана 1280×720: стена x≈100–210, край рва `battle.moat_x` (290),
появление `battle.spawn_x` (900, +разброс до 45 вправо), полоса `battle.y_min..y_max` (130–610).

- `battle.enemies: Array[Battle.Enemy]` — `uid, type, role ("normal"/"escort"/"boss"), pos, hp, max_hp,
  radius, speed, age, scald_t (>0 — ошпарен, рисовать пар), alive`. Мёртвые удаляются в конце тика.
- `battle.towers: Array[Battle.Tower]` — `type, index, pos, cd (до выстрела), shots, aim (куда был последний выстрел)`.
- `battle.projectiles: Array[Battle.Projectile]` — `uid, kind ("bullet"/"rivet"/"shell"), tower, pos, crit`;
  заклёпка: `dir`; снаряд мортиры: `start, dest, t, flight` — дугу рисовать по `t/flight`
  (ядро двигает `pos` по прямой).
- Босс: `battle.boss_enemy` (null, если нет), `battle.boss_id`; полоса здоровья — `hp/max_hp`.
- Ров: паровая завеса бьёт врагов с `x < moat_x + waves.curtain_width`, если `core.mods.moat_dps > 0`.
- Доход: `core.income[res]` — среднее за 10 с, ресурсы: `core.state.res(id)`.
- Статистика: `state.stats` — `kills, falls, purchases, kills_by_type, falls_by_type, dmg_by_source`
  (`"lens"`, `"moat"`, `"scald"`, `"tower:<тип>"`).

## События (`core.drain_events()` раз в кадр)

Массив словарей, поле `type`. Позиции — `Vector2` в координатах поля.

| type | поля | когда |
|---|---|---|
| `pack_spawned` | index | новая пачка |
| `enemy_spawned` | uid, enemy, role, pos | враг появился |
| `projectile_fired` | uid, kind, tower, tower_index, from, to, crit | выстрел (вспышка у башни) |
| `enemy_hit` | uid, amount, dmg_type, crit, pos, source | попадание (не шлётся для тиков завесы и ошпаривания) |
| `enemy_status` | uid, status ("scald"), pos, duration | наложен статус |
| `shell_exploded` | uid, pos, radius, crit | взрыв мортиры |
| `lens_tick` | pos, radius, mode | тик линзы (искры/жар) |
| `enemy_killed` | uid, enemy, pos, loot {res: amount} | убит, добыча уже начислена |
| `enemy_fell_in_moat` | uid, enemy, pos | сорвался в ров, без награды |
| `purchased` | id, level, price | покупка |
| `tower_built` | tower, index, pos | новая башня на стене |
| `unlocked` | what ("enemy"/"tower"/"region"/"behavior"), id | открытие (behavior: id = тип эффекта) |
| `boss_spawned` | boss, uid, hp | босс вышел |
| `boss_retreated` | boss, pos | дошёл до рва и отступил («вернётся, когда будешь готов») |
| `boss_defeated` | boss, pos | побеждён |
| `boss_reward` | boss, loot | награда начислена |

Если события не нужны (симуляция): `core.emit_events = false`.

## Покупки

Id: `tower:<тип>` (ещё одна башня), `upg:<id>` (улучшение в магазине, шестерни), `node:<id>` (узел карты, чертежи).

```gdscript
core.offer_ids()          # всё видимое игроку сейчас (башни открытых типов, улучшения, доступные узлы)
core.price(id)            # {res: amount} следующего уровня = base*(1+growth)^level, вверх до целого
core.can_buy(id) / core.buy(id)
core.level_of(id), core.max_of(id)        # для башен: число и текущий лимит
core.is_available(id)                     # видимо, не максимум, есть место на стене
core.node_status(node_id)                 # "hidden" | "locked" | "available" | "maxed"
core.preview_mods(id)                     # Mods после покупки — для «было → станет»
```

Сравнение «было → станет»: `core.mods.tower_stats[t]["dmg"]` vs `core.preview_mods(id).tower_stats[t]["dmg"]`
(аналогично `reload`, `limit`, `pierce`, `splash`, `crit_chance`; `enemy_stats[e]["hp"/"pack"/"loot"]`;
`lens["radius"/"dmg"/"interval"/"auto_mult"/"seek"]`; `moat_dps`).

Тексты: башня — `data.towers[t].name/desc`, улучшение — `data.upgrades[u].name` (+`_DESC`),
узел — `GameData.node_name_key(id)` / `node_desc_key(id)` (`NODE_<ID>`, `NODE_<ID>_DESC`),
ресурс — `RES_<ID>` / `RES_<ID>_SHORT`, урон — `data.damage_types[t].name`.
Для карты: `data.nodes[id]` — `region, parents, pos [x,y] (координаты карты 0..1000×0..700), kind`
(`spine/bait/tower/lens/moat/synergy/global/boss/region` — цвет узла), `data.children[id]`, `data.regions`.

## Боссы

Узел с эффектом `call_boss` вызывает босса при покупке. Дальше:
`core.state.boss_status(id)` — `"none" | "active" | "retreated" | "defeated"`,
`core.can_call_boss(id)` → показать кнопку «Вызвать снова», `core.call_boss(id)`,
`core.active_boss()`. Пока босс на поле, обычные пачки на паузе (`waves.boss_pauses_packs`).

## Сохранение

```gdscript
var d: Dictionary = core.save_state()   # JSON-совместимо (ключ version)
core.load_state(d)                      # поле начинается пустым, статы пересчитываются
```

Офлайн-прогресс пока не реализован (SV1): проще всего — `core.income` × время × коэффициент.

## Конфиги (все числа баланса)

| Файл | Что |
|---|---|
| `economy.json` | ресурсы (все 7, сейчас используются шестерни и чертежи), старт, сид |
| `waves.json` | геометрия поля, интервал пачек (3 с), лимит врагов, ширина завесы |
| `enemies.json` | типы урона, враги (hp, speed, radius, pack, loot, resist, role), боссы (свита, награда, on_defeat) |
| `towers.json` | башни (урон, тип, перезарядка, дальность, снаряд, пробитие, взрыв, крит, лимит, цена) и улучшения магазина |
| `lens.json` | линза: радиус, урон, тик, авто-путь, скорость, простой до авто |
| `map.json` | регионы и узлы карты (id, region, parents, pos, kind, cost, growth, max, effects) |

Эффект: `{"type", "target" (тип башни/врага или "all"), "value", ...}`, применяется ×уровень.
Типы: `unlock_enemy, enemy_spawn_add, enemy_loot_mult (+hp), enemy_bp_mult (+hp), enemy_hp_mult,
unlock_tower, tower_limit_add, tower_dmg_mult, tower_reload_mult (скорострельность), tower_pierce_add,
tower_splash_add (px), tower_crit_chance_add, tower_crit_mult_add, tower_range_add,
tower_on_hit_status (status "scald", value = доля урона попадания паром за duration с),
lens_radius (px), lens_dmg, lens_rate, lens_auto_mult, lens_seek, global_dmg_mult, global_loot_mult,
global_bp_mult, moat_damage (урон/с завесы), call_boss (target = id босса), unlock_region (value = регион)`.
`"stack": "mul"` — множитель `(1+value)^уровень` вместо сложения процентов. Формула — `Mods`.
Новый тип эффекта: добавить в `GameData.EFFECT_TYPES`, применить в `Mods.apply_effect`/`_derive`
(и в `GameData.NOVEL_EFFECTS`, если он меняет картинку — это учитывает отчёт темпа).

## Симуляция баланса

`tools/simulate.sh [минут=20] [--idle | --active] [--seed=N] [--dt=0.05] [--strict]` — без флага
оба режима. Пишет `sim_out/report.md` (проверки темпа DESIGN §9 PASS/FAIL, доля линзы, урон по
источникам, «что нового» с таймингом, бой с боссом, таймлайн, все покупки с паузами) и
`sim_out/timeline.csv` / `timeline_idle.csv` (раз в 10 с: ресурсы, доход/с, DPS по источникам,
враги на поле, убийства, падения, покупки). 20 минут ≈ 3 с реального времени. `--strict` — код 1,
если проверка активного режима не прошла.
