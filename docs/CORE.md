# CORE — API ядра логики (для вида, сохранений и баланса)

Ядро — `scripts/core/`, чистые `RefCounted`-классы без узлов сцены. Их одинаково гоняют игра
(автолоад `Game`), тесты (`tests/test_core*.gd`) и headless-симуляция (`tools/simulate.sh`).
Решения и почему так — DECISIONS.md D-016…D-030, R2 — D-051…D-057.

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
  (замедлен), underground (в норе: рисовать холмик, неуязвим), age, alive`. R2+:
  `stun_t` (>0 — оглушён, стоит: звёздочки), `immune` (`{"slow","stun","knockback"}` — вагонетка), `charging` (рывок
  Бура: пыль), `front_armor` (>0 — лобовая броня: латунная плита спереди), `shield_hp/shield_max` (>0 — медный шлем
  водолаза), `split` (не пусто — расколется: трещины), `parent_uid` (уголёк: из какого голема), `bait` (уровни приманки
  этого типа: мешки с добычей на спине), `scald_src` (кто ошпарил).
- `battle.towers` (`Battle.Tower`): `type, index, slot, pos, cd, shots, aim`. Вид башни: `core.tower_tier(type)`
  (1 — железо, 2 — латунь, 3 — позолота; растёт вехами улучшений).
- `battle.projectiles`: `kind ("bullet"/"rivet"/"shell"/"ricochet"), tower, pos, crit`; заклёпка `dir`; снаряд `start, dest, t,
  flight, fragment` (дуга по `t/flight`; осколки кассетного снаряда — маленькая дуга); ядро рикошета летит как пуля,
  `bounce` — сколько отскоков сделало (событие `ricochet` на каждый). Конус (пароструй) и молния (тесла) мгновенные —
  только события `cone_fired` / `chain_fired`.
- `battle.zones` (`Battle.Zone`): лужи — `pos, radius, t, duration, dmg_type, tower` (владелец: тип башни или
  `ability:kettle`), `statuses` (не пусто — липкая смоляная лужа: замедляет).
- Ров: завеса бьёт врагов с `x < moat_x + core.mods.moat_width`, если `mods.moat_dps > 0`; `mods.moat_slow > 0` — цепи.
- Механизмы: `core.mods.abilities` (`kettle` — чайник Короля, `geyser` — гейзеры у рва, `drill_ram` — бур-таран,
  трофей Бура), таймеры `battle.ability_timers`. У механизма `shape` (`splash` / `line`), `puddle` (не пусто — чайник
  оставляет лужу), `kill_loot_mult` (гейзер: убитые им дают 50% добычи).
- Цеха (производство): `core.mods.producers` — `{id: {interval, output {res: amount}, level}}` (`coal_mine` — Угольная
  шахта: колесо/вагонетки у стены), прогресс цикла `core.producer_progress(id)` 0..1 (заполнять колесо/вагонетку),
  выпуск — событие `producer_output` (рисовать вагонетку и всплывающие «+3 уголь +150 шест.»).
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
| `enemy_emerge` | uid, pos, forced | крот вылез (дополнительно к `enemy_burrow` under=false); forced — выбит линзой/взрывом/струёй |
| `enemy_charge` | uid, pos, duration | рывок (Бур-Великан) |
| `enemy_split` | uid, enemy, pos, child_type, children [uid] | голем раскололся на угольки (после `enemy_killed`) |
| `enemy_shield_broken` | uid, pos | с водолаза сорван медный шлем |
| `projectile_fired` | uid, kind, tower, tower_index, from, to, crit | выстрел |
| `cone_fired` | tower, tower_index, from, dir, length, angle, hits, crit | конус пароструя (мгновенный) |
| `chain_fired` | tower, tower_index, from, points [Vector2], hits, crit | молния теслы: ломаная from → points (мгновенная) |
| `ricochet` | uid, tower, from, to, bounce | ядро отскочило к следующему врагу |
| `enemy_hit` | uid, amount, dmg_type, crit, pos, source, armored, shielded | попадание (прямое); armored — лобовая броня погасила часть («дзынь», искры); shielded — по шлему |
| `enemy_dot` | uid, pos, source ("scald"/"moat"/"zone"), amount, total | урон со временем, сводка раз в `waves.dot_event_interval` (0.25 с) на врага и источник; total — весь DoT по врагу |
| `enemy_status` | uid, status ("scald"/"slow"), pos, duration | статус наложен заново |
| `crit_chain` | from, to | искра крита перескочила |
| `bullet_burst` | pos, radius | разрывная пуля |
| `shell_exploded` | uid, tower, pos, radius, crit, fragment | взрыв снаряда / осколка |
| `zone_created` | uid, pos, radius, duration, dmg_type, tower, statuses | лужа (котлобой, чайник); statuses `["slow"]` — смола |
| `ability_fired` | id, pos, radius, hits, damage, shape | чайник выплеснул кипяток |
| `geyser` | id, pos, radius, hits, damage, shape | гейзер у рва (вместо `ability_fired`) |
| `drill_ram` | id, pos (moat_x, y), x_end, width, hits, damage, shape "line" | бур-таран проехал по полосе y от рва до x_end |
| `producer_output` | id, amount {res: n}, level | цех выдал партию (уголь и шестерни; с «Подъёмником» — чертежи) |
| `lens_tick` | index, pos, radius, mode, damage, hits | тик линзы с суммой урона |
| `enemy_killed` | uid, enemy, pos, loot, source | убит, добыча начислена (гейзер: половина) |
| `enemy_fell_in_moat` | uid, enemy, pos | упал в ров |
| `purchased` | id, level, price | покупка |
| `tower_built` | tower, index, pos | новая башня на стене |
| `milestone` | upgrade, tower, name, level | веха улучшения (name — ключ i18n `MS_*`, описание `MS_*_DESC`) |
| `tier_up` | tower, tier | башня сменила вид |
| `choice_made` | id, excluded | выбор сделан, ветки `excluded` закрыты |
| `unlocked` | what ("enemy"/"tower"/"region"/"producer"/"behavior"), id | открытие; behavior: id — ключ из `Mods.behaviours()` |
| `boss_spawned` / `boss_retreated` / `boss_defeated` / `boss_reward` | boss, … | бой с боссом; retreated/defeated: `hp_left` (доля) |

`core.emit_events = false` — без событий (симуляция).

## Покупки и выборы

Id: `tower:<тип>`, `upg:<id>` (магазин, шестерни), `node:<id>` (карта, чертежи и материалы).

```gdscript
core.offer_ids()                  # видимое сейчас
core.price(id) / can_buy(id) / buy(id) / level_of(id) / max_of(id) / is_available(id)
core.node_status(node_id)         # hidden | locked | excluded | available | maxed
core.preview_mods(id)             # Mods после покупки — «было → станет»
core.novelty_of(id)               # что нового на экране принесёт покупка (ключи behaviours); [] = только числа
core.changes_of(id)               # то же + «косметика»: tier:* (новый вид), region:* (регион) — не считаются новым
core.purchase_category(id)        # "novel" | "tower" | "numeric"
core.next_milestone(upgrade_id)   # {level, levels_left, name, desc, novelty} ближайшей вехи или {} — для карточки цеха
core.producer_progress(id)        # 0..1 цикла цеха
```

- Выбор: узлы с `excludes` (взаимно). Купил один — остальные `excluded`. Для показа обеих веток со статами
  сравнивай `preview_mods("node:a")` и `preview_mods("node:b")`. Награда за босса — пара узлов с
  `requires: {"boss": id}` и ценой 0 (скрыты до победы).
- Вехи (`upgrades.*.milestones`): эффекты применяются один раз при достижении уровня; `tower_tier_add` — смена вида.
- Узел «нового» показывай подсветкой: `novelty_of(id)` не пуст. Честно (D-052): новый вид башни (`tier:*`) или открытый
  регион (`region:*`) сами по себе — не новое; отброс меньше `combat.knockback_novel_min` (20 px) — тоже.
- Ключи поведений R2 (для текстов «что нового»): `status:<башня>:stun`, `armor_pierce:<башня>` (пробивает лобовую броню),
  `dig:<башня>` / `lens_dig` (выбивает кротов из нор), `zone_status:<башня>:slow` (липкая лужа), `scald_shred`
  (паровая ржавчина), `wet_metal` (мокрый металл), `producer:<id>`, `producer_out:<id>:<res>`, `ability_puddle:<id>`,
  `ability:geyser`, `ability:drill_ram`, `tower:tesla` / `tower:ricochet`.
- Приманки — пары «Гудок» ↔ «Слухи о кладе» (`excludes`): больше врагов или богаче-но-толще (D-053).

## Боссы

`state.boss_status(id)`: `none | active | retreated | defeated`; `can_call_boss(id)`, `call_boss(id)`, `active_boss()`.
Пока босс на поле — пачки на паузе. После победы каждого босса старые враги (регион < числа побеждённых
боссов) приходят реже: пачка × `waves.old_region_pack_factor`^разница.
Бур-Великан (R2): лобовая броня `front_armor` 0.7 гасит прямой огонь (`combat.direct_kinds`: пули, заклёпки, конусы,
рикошеты, молнии); навесные снаряды, взрывы, лужи, линза, гейзеры, чайник — в полную силу. Рывки (`charge`), иммунен к
оглушению и отбросу. Награда за победу — выбор из двух качественных узлов (`r2_trophy_ram` / `r2_trophy_lens`),
затем открывается регион 3 (Медные болота, заглушка: водолазы, медь, Тесла ↔ Рикошетная пушка).

## Сохранение

`core.save_state()` → `{version: 2, run: {...}, meta: {...}}`; `core.load_state(d)`. Места башен на стене
сохраняются (`run.tower_slots`). Ресурсы с `"meta": true` в `economy.resources` (печати) хранятся в meta.

## Конфиги

| Файл | Что |
|---|---|
| `economy.json` | ресурсы (meta-флаг), старт, сид, округление цен, окно дохода, предел tick, `producers` (цеха) |
| `waves.json` | поле, пачки, разброс скорости/по y, покачивание, прореживание старых врагов, завеса, интервал DoT-событий |
| `enemies.json` | типы урона, враги (`burrow`, `immune`, `split`, `front_armor`, `charge`, `shield`), боссы (свита, награда, on_defeat) |
| `towers.json` | `wall.rows`, `combat` (константы боя), башни (`row`, `on_hit`, `puddle`, `cone_angle`, `chain*`, `bounce*`), улучшения с `milestones`, `abilities` (`shape`, `kill_loot_mult`, `event`) |
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
unlock_ability, ability_dmg_mult, ability_status, ability_count_add, call_boss, unlock_region`; R2: `unlock_producer,
producer_amount_mult, producer_rate_mult, producer_output_add (res), tower_zone_status (status, duration),
tower_armor_pierce, tower_dig, lens_dig, scald_shred, wet_metal, tower_chain_add, tower_bounce_add, ability_puddle
(radius, duration, dmg_type; value = доля среднего удара в секунду)`. Статусы: `scald, slow, stun`.
`"stack": "mul"` — множитель вместо сложения. Новый тип: `GameData.EFFECT_TYPES` + `Mods.apply_effect/_derive`;
если это новое поведение — добавить ключ в `Mods.behaviours()` (по нему считается «новое на экране»).

## Симуляция

`tools/simulate.sh [минут=35] [--active | --real | --idle] [--seed=N] [--seeds=1,2,3] [--compare] [--force=node,...]
[--baits=default|none|greedy] [--dt=0.05] [--out=report.md] [--strict]` — без флага режима все три. `sim_out/report.md`:
сводка всех прогонов (сиды), сравнение вариантов (`--compare`: принудительно Пароструй / Котлобой, без приманок, жадные
приманки), по каждому режиму — проверки за **весь** прогон (темп DESIGN §9, пара R2 в 14:30–18:00, Бур 26–34 мин,
вход в R3, паузы ≤ 3 мин, новое ≤ 5 мин, ≤ 8 покупок между новинками, числовых ≤ 40%, давление 5–35% падений,
запасы в конце ≤ 6 мин дохода), ритм по фазам, боссы с попытками и остатком здоровья при отступлении, выборы, купленные
приманки, урон по источникам (+ошпаривание по тому, кто ошпарил), новинки по времени, падения по минутам, таймлайн,
все покупки. ~25 с реального времени на 35 минут режима.
