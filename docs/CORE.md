# CORE — API ядра логики (для вида, сохранений и баланса)

Ядро — `scripts/core/`, чистые `RefCounted`-классы без узлов сцены. Их одинаково гоняют игра
(автолоад `Game`), тесты (`tests/test_core*.gd`) и headless-симуляция (`tools/simulate.sh`).
Решения и почему так — DECISIONS.md D-016…D-030.

| Файл | Класс | Что делает |
|---|---|---|
| `game_core.gd` | `GameCore` | фасад: tick, события, покупки, выборы, боссы, цель, доход/с, сохранение |
| `game_state.gd` | `GameState` | сохраняемое: забег (ресурсы, башни и их места, уровни, боссы, статистика) + `meta` (печати, изобретения, рекорды, статистика за всё время) |
| `game_data.gd` | `GameData` | контент из `config/*.json` + строгая проверка (нет обязательного поля / неизвестная ссылка → ошибка) |
| `mods.gd` | `Mods` | эффекты → производные статы + «подпись поведений» `behaviours()` |
| `battle.gd` | `Battle` | поле: враги, башни, снаряды, лужи, линзы, механизмы, ров, пачки, босс |
| `sim_bot.gd` | `SimBot` | бот-игрок (`active` / `real` / `idle`) |

## Жизненный цикл

```gdscript
var core: GameCore = Game.start()      # новая игра (контент — из автолоада Config), Game тикает сам
var core := GameCore.create(seed)      # без автолоадов; seed < 0 -> economy.seed
core.tick(delta)                       # любой dt; шаги <= core.max_step (0.1 с), предел economy.max_tick
core.new_run()                         # престиж (позже): забег сначала, meta остаётся
```

Отладочные аргументы игры: `--bot[=real|idle]`, `--ff=<сек>` (промотать на старте), `--seed=<n>`.

## Курсор (Паровая линза)

Каждый кадр: `core.set_cursor(mouse_pos, mouse_over_field)`. Ядро само решает режим главной линзы:
курсор над полем и двигался за последние `lens.idle_to_auto` (2 с) → `manual` (под курсором, полный урон);
иначе `auto` — каждые `auto_retarget` с находит полосу дороги (`auto_band` px) с наибольшим числом врагов
и ходит над ней вверх-вниз, урон × `auto_mult`; с «Наводчиком» — `seek`, летит прямо к самой плотной группе.
Урон тика = `dmg + dmg_pct_hp · макс. здоровье` (боссам процентная часть × `boss_pct_mult`).
Читать: `battle.lenses` (`Battle.Lens`: `index, pos, mode`), `battle.lens_pos`/`lens_mode` — главная линза,
радиус `core.mods.lens["radius"]`. Дополнительные линзы (трофей) всегда автоматические.

## Что рисовать (читать каждый кадр)

Поле = пиксели 1280×720: стена x≈100–210 (места — `data.wall_slots`, 3 ряда по 12), край рва `battle.moat_x`
(290), появление `battle.spawn_x` (900), полоса `battle.y_min..y_max` (130–610).

- `battle.enemies` (`Battle.Enemy`): `uid, type, role, pos, hp, max_hp, radius, scald_t (>0 — ошпарен), slow_t/slow_f
  (замедлен), underground (в норе: рисовать холмик, неуязвим), age, alive`.
- `battle.towers` (`Battle.Tower`): `type, index, slot, pos, cd, shots, aim`. Вид башни: `core.tower_tier(type)`
  (1 — железо, 2 — латунь, 3 — позолота; растёт вехами улучшений).
- `battle.projectiles`: `kind ("bullet"/"rivet"/"shell"), tower, pos, crit`; заклёпка `dir`; снаряд `start, dest, t,
  flight, fragment` (дуга по `t/flight`; осколки кассетного снаряда — маленькая дуга).
- `battle.zones` (`Battle.Zone`): лужи кипятка котлобоя — `pos, radius, t, duration, dmg_type`.
- Ров: завеса бьёт врагов с `x < moat_x + core.mods.moat_width`, если `mods.moat_dps > 0`; `mods.moat_slow > 0` — цепи.
- Механизмы: `core.mods.abilities` (сейчас `kettle` — чайник Короля), таймеры `battle.ability_timers`.
- Босс: `battle.boss_enemy` / `battle.boss_id`.
- Цель (строка над полем): `core.next_goal()` → `{id, text_key, args, progress 0..1, cost}`;
  `text_key` — `GOAL_NODE` / `GOAL_BOSS_FIGHT` / `GOAL_BOSS_RETRY` / `GOAL_NONE`, `args` — ключи i18n
  (`tr(text_key) % args.map(tr)`). Приоритет: бой с боссом → повторный вызов → самый дешёвый узел с чем-то новым → любой.
- Доход: `core.income[res]` (окно `economy.income_window`), ресурсы `core.state.res(id)`.
- Статистика: `state.stats` (забег), `state.meta["stats"]` (за всё время), `state.meta["high"]` (рекорды).

## События (`core.drain_events()` раз в кадр)

| type | поля | когда |
|---|---|---|
| `pack_spawned` | index | новая пачка |
| `enemy_spawned` | uid, enemy, role, pos | враг появился |
| `enemy_burrow` | uid, pos, under | крот ушёл под землю / вылез |
| `projectile_fired` | uid, kind, tower, tower_index, from, to, crit | выстрел |
| `cone_fired` | tower, tower_index, from, dir, length, angle, hits, crit | конус пароструя (мгновенный) |
| `enemy_hit` | uid, amount, dmg_type, crit, pos, source | попадание (прямое) |
| `enemy_dot` | uid, pos, source ("scald"/"moat"/"zone"), amount, total | урон со временем, сводка раз в `waves.dot_event_interval` (0.25 с) на врага и источник; total — весь DoT по врагу |
| `enemy_status` | uid, status ("scald"/"slow"), pos, duration | статус наложен заново |
| `crit_chain` | from, to | искра крита перескочила |
| `bullet_burst` | pos, radius | разрывная пуля |
| `shell_exploded` | uid, tower, pos, radius, crit, fragment | взрыв снаряда / осколка |
| `zone_created` | uid, pos, radius, duration, dmg_type | лужа кипятка |
| `ability_fired` | id, pos, radius, hits, damage | чайник выплеснул кипяток |
| `lens_tick` | index, pos, radius, mode, damage, hits | тик линзы с суммой урона |
| `enemy_killed` | uid, enemy, pos, loot | убит, добыча начислена |
| `enemy_fell_in_moat` | uid, enemy, pos | упал в ров |
| `purchased` | id, level, price | покупка |
| `tower_built` | tower, index, pos | новая башня на стене |
| `milestone` | upgrade, tower, name, level | веха улучшения (name — ключ i18n `MS_*`, описание `MS_*_DESC`) |
| `tier_up` | tower, tier | башня сменила вид |
| `choice_made` | id, excluded | выбор сделан, ветки `excluded` закрыты |
| `unlocked` | what ("enemy"/"tower"/"region"/"behavior"), id | открытие; behavior: id — ключ из `Mods.behaviours()` |
| `boss_spawned` / `boss_retreated` / `boss_defeated` / `boss_reward` | boss, … | бой с боссом |

`core.emit_events = false` — без событий (симуляция).

## Покупки и выборы

Id: `tower:<тип>`, `upg:<id>` (магазин, шестерни), `node:<id>` (карта, чертежи и материалы).

```gdscript
core.offer_ids()                  # видимое сейчас
core.price(id) / can_buy(id) / buy(id) / level_of(id) / max_of(id) / is_available(id)
core.node_status(node_id)         # hidden | locked | excluded | available | maxed
core.preview_mods(id)             # Mods после покупки — «было → станет»
core.novelty_of(id)               # что нового на экране принесёт покупка (ключи behaviours); [] = только числа
core.purchase_category(id)        # "novel" | "tower" | "numeric"
```

- Выбор: узлы с `excludes` (взаимно). Купил один — остальные `excluded`. Для показа обеих веток со статами
  сравнивай `preview_mods("node:a")` и `preview_mods("node:b")`. Награда за босса — пара узлов с
  `requires: {"boss": id}` и ценой 0 (скрыты до победы).
- Вехи (`upgrades.*.milestones`): эффекты применяются один раз при достижении уровня; `tower_tier_add` — смена вида.
- Узел «нового» показывай подсветкой: `novelty_of(id)` не пуст.

## Боссы

`state.boss_status(id)`: `none | active | retreated | defeated`; `can_call_boss(id)`, `call_boss(id)`, `active_boss()`.
Пока босс на поле — пачки на паузе. После победы каждого босса старые враги (регион < числа побеждённых
боссов) приходят реже: пачка × `waves.old_region_pack_factor`^разница.

## Сохранение

`core.save_state()` → `{version: 2, run: {...}, meta: {...}}`; `core.load_state(d)`. Места башен на стене
сохраняются (`run.tower_slots`). Ресурсы с `"meta": true` в `economy.resources` (печати) хранятся в meta.

## Конфиги

| Файл | Что |
|---|---|
| `economy.json` | ресурсы (meta-флаг), старт, сид, округление цен, окно дохода, предел tick |
| `waves.json` | поле, пачки, разброс скорости/по y, покачивание, прореживание старых врагов, завеса, интервал DoT-событий |
| `enemies.json` | типы урона, враги (`burrow` — норы), боссы (свита, награда, on_defeat) |
| `towers.json` | `wall.rows`, `combat` (константы боя), башни (`row`, `on_hit`, `puddle`, `cone_angle`), улучшения с `milestones`, `abilities` |
| `lens.json` | линза: урон, % здоровья, тик, авто-полоса и развёртка, наводчик |
| `map.json` | регионы и узлы (`excludes`, `requires`) |

Обязательные поля перечислены в `GameData.*_REQ`; в ядре нет значений по умолчанию для чисел баланса.

Эффекты (×уровень): `unlock_enemy, enemy_spawn_add, enemy_bait (value = +доля добычи и чертежей, hp = ×(1+hp)
за уровень), enemy_loot_mult, enemy_bp_mult (поле hp — тоже множителем), enemy_hp_mult, unlock_tower,
tower_limit_add, tower_dmg_mult, tower_reload_mult, tower_pierce_add, tower_splash_add, tower_crit_chance_add,
tower_crit_mult_add, tower_range_add, tower_on_hit_status (scald: доля урона попадания паром за duration;
slow: −value скорости), tower_multishot_add, tower_knockback_add (px), tower_cluster_add (осколки),
tower_crit_chain_add, tower_tier_add, lens_radius, lens_dmg, lens_rate, lens_auto_mult, lens_seek, lens_status,
lens_extra_add, global_dmg_mult, global_loot_mult, global_bp_mult, moat_damage, moat_slow_add, moat_width_add,
unlock_ability, ability_dmg_mult, ability_status, ability_count_add, call_boss, unlock_region`.
`"stack": "mul"` — множитель вместо сложения. Новый тип: `GameData.EFFECT_TYPES` + `Mods.apply_effect/_derive`;
если это новое поведение — добавить ключ в `Mods.behaviours()` (по нему считается «новое на экране»).

## Симуляция

`tools/simulate.sh [минут=20] [--active | --real | --idle] [--seed=N] [--dt=0.05] [--strict]` — без флага все
три режима. `sim_out/report.md`: проверки (темп DESIGN §9, покупок между новинками ≤ 8, доля чисто числовых
< 50%, давление ≥ 5% падений в какую-то минуту и не > 35%, пара башен R2 до 20:00), выборы бота, урон по
источникам, «что нового» с ключами поведений, по минутам — падения в ров, средний x убийств и доля убийств у рва,
таймлайн, все покупки с категориями. `timeline*.csv` — раз в 10 с. ~13 с реального времени на 20 минут режима.
