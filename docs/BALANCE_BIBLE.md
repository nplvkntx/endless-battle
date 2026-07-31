# Endless Battle — Balance Bible

> Extracted from the live codebase. No values were changed.
> **Canonical balance tables:** `scripts/balance/` (`UnitStats`, `BuildingStats`, `HeroStats`, `UpgradeStats`, `ItemStats`, `EconomyStats`).
> Change numbers there only; other scripts re-export or reference those consts.

**Document date:** 2026-07-31

---

## Source map

| Area | Canonical files |
|------|-----------------|
| Match start / economy / kill rewards | `scripts/balance/economy_stats.gd` (`MatchConfig`, `GatheringConfig`, `HeroXpRewards` re-export) |
| Building costs / HP / construction | `scripts/balance/building_stats.gd` (player + AI) |
| Unit combat / train costs | `scripts/balance/unit_stats.gd` |
| Hero combat / growth / abilities | `scripts/balance/hero_stats.gd` |
| Upgrades | `scripts/balance/upgrade_stats.gd` (`UpgradeManager` re-exports) |
| Items | `scripts/balance/item_stats.gd` (`HeroItemCatalog` builds from these) |
| Victory / defeat | `scripts/systems/match_manager.gd` |
| Building footprints | `scripts/systems/enemy_build_placement.gd` |
| Scene HP / move_speed mirrors | `scenes/units/*.tscn`, `scenes/buildings/*.tscn` (keep in sync with balance tables) |
| Tech unlocks | `autoloads/tech_tree.gd`, `scripts/buildings/command_center.gd` |
| Ability rank multipliers | `scripts/systems/hero_ability_stats.gd` |
| Creeps | `scenes/world/neutral_creep_camps.tscn`, `scripts/systems/creep_camp.gd` |
| Combat formulas | `scripts/systems/unit_combat_damage.gd`, `scripts/systems/splash_damage.gd`, `scripts/components/health_component.gd` |
| AI economy / timing (not shared balance) | `scripts/systems/enemy_*.gd` |

---

# 1. Match Rules

**Sources:** `match_config.gd`, `resource_manager.gd`, `enemy_resource_manager.gd`, `match_manager.gd`, `farm.gd`

| Rule | Value | Notes |
|------|------:|-------|
| Starting Gold | **500** | Same for human and AI (`MatchConfig.NORMAL_STARTING_GOLD`) |
| Starting Wood | **500** | Same for human and AI |
| Starting Food (used) | **5** | Equals starting worker count (`HUMAN_STARTING_FOOD`) |
| Starting Food Cap | **15** | `STARTING_FOOD_MAX` |
| Starting Workers | **5** | Placed in scene; food usage starts at 5 |
| Population Cap | **Food Max** | Soft cap: cannot train if `food_current + cost > food_max` |
| Food per Farm | **+8** | `Farm.FOOD_CAP_BONUS` when construction completes |
| Absolute hard pop limit | *None* | Cap grows only via farms |

### Victory / Defeat

| Condition | Result | Source |
|-----------|--------|--------|
| Enemy main Command Center destroyed | **Victory** | `match_manager.gd` |
| Player main Command Center destroyed | **Defeat** | `match_manager.gd` |
| Other win conditions | *None* | No score / time / elimination modes |

Debug-only: F8 destroys enemy CC, F9 destroys player CC (debug builds).

---

# 2. Economy

**Sources:** `gathering_config.gd`, `gold_mine.gd`, `tree.gd`, `worker.gd` / `worker_gathering.gd`

## Resources

| Resource | Gather chunk | Carry capacity | Gather wait | Stockpile start |
|----------|-------------:|---------------:|------------:|----------------:|
| Gold | **5** per tick | **10** | **1.0 s** | Mine: **20,000** |
| Wood | **2** per tick | **10** | **1.0 s** | Tree: **5,000** |
| Food | N/A (cap only) | N/A | N/A | Cap **15** |

### Gather timing formulas

- Wait between gather ticks: `GATHER_WAIT_SECONDS / max(speed_multiplier, 0.01)`
- Base wait = **1.0 s**
- With Academy **Faster Gathering**: speed multiplier **1.25** → wait = **0.8 s**
- Full load: Gold needs `ceil(10/5) = 2` ticks; Wood needs `ceil(10/2) = 5` ticks (plus travel)

### Carry / return

| Value | Amount | Source |
|-------|-------:|--------|
| Worker carry capacity | 10 | `GatheringConfig.WORKER_CARRY_CAPACITY` |
| Return / deposit | Travel to nearest completed Command Center | No fixed return-time constant; pathing-based |
| CC deposit reach bonus | 0.75 | `COMMAND_CENTER_DEPOSIT_REACH_BONUS` |
| CC extended deposit reach | 3.0 | `COMMAND_CENTER_DEPOSIT_EXTENDED_REACH` |
| Resource interaction reach bonus | 1.25 | `RESOURCE_INTERACTION_REACH_BONUS` |
| Wood chop reach bonus | 0.65 | `WOOD_CHOP_REACH_BONUS` |

### Worker assignment recommendations (AI-defined)

From `enemy_gather_manager.gd` / `enemy_build_manager.gd`:

| Setting | Value |
|---------|------:|
| Starting gold workers (AI) | 4 |
| Early gold:wood ratio | 0.70 gold |
| Mid gold:wood ratio | 0.60 gold |
| Late gold:wood ratio | 0.55 gold |
| Building-pressure gold ratio | 0.45 gold |
| Min wood workers when trees exist | 1 |
| Soft gold mine assignments | max 8 (`MAX_SOFT_GOLD_ASSIGNMENTS`) |
| Soft tree assignments | max 4 (`MAX_SOFT_TREE_ASSIGNMENTS`) |

### Income formulas (derived)

No passive income. Income is purely gather:

| Resource | Steady-state income (1 worker, no travel, no upgrade) |
|----------|------------------------------------------------------|
| Gold | `10 / (2 × 1.0s + travel_roundtrip)` → **5 gold/s** if travel=0 |
| Wood | `10 / (5 × 1.0s + travel_roundtrip)` → **2 wood/s** if travel=0 |
| With Faster Gathering | Wait × 0.8 → gold **6.25/s**, wood **2.5/s** (travel=0) |

Kill gold (see §5 / §6) is a secondary gold source.

### Gold mine / tree

| Node | Default amount | Source |
|------|---------------:|--------|
| Gold Mine | 20,000 | `GatheringConfig.GOLD_MINE_STARTING_GOLD` / `GoldMine.@export gold_amount` default 20000 |
| Tree | 5,000 | `GatheringConfig.TREE_STARTING_WOOD` / `Tree.@export wood_amount` default 5000 |

---

# 3. Buildings

**Costs / build times:** `build_manager.gd`  
**HP:** scene `HealthComponent.max_health`  
**Footprints (XZ size):** `enemy_build_placement.gd`  
**Armor:** *not implemented for buildings* (damage applied as `maxi(0, int(amount))`)  
**Sight / vision:** *not implemented* (`FogOfWarManager` is a TODO stub)

## Construction durations

Shared worker-count scaling (`build_manager.gd`):

| Workers | Default buildings | Shop | Wall segment |
|--------:|------------------:|-----:|-------------:|
| 1 | 4.0 s | 3.5 s | 8.0 s |
| 2 | 2.5 s | 2.2 s | 5.0 s |
| 3+ | 2.0 s | 1.8 s | 4.0 s |

Academy **Improved Tools** multiplies construction speed by **1.2** (duration ÷ 1.2).

## Building table

| Building | Gold | Wood | HP | Footprint (X×Z) | Requirements | Unlocks / produces |
|----------|-----:|-----:|---:|-----------------|--------------|--------------------|
| Command Center | 200 | 400 | 500 | 3.5×3.5 | — | Workers; drop-off; Tier 2/3 research |
| Farm | 80 | 20 | 250 | 2.0×1.4 | — | +8 food cap |
| Barracks | 150 | 100 | 300 | 3.5×2.5 | — | Spearman; Swordsman/Archer (need Blacksmith) |
| Hero Altar | 180 | 110 | 350 | 3.0×3.0 | — | Hero (1 living hero per side) |
| Shop | 80 | 120 | 600 | 2.0×1.6 | — | Hero item purchases |
| Tower | 120 | 80 | 350 | 2.0×2.0 | — | Auto-attacks |
| Wall Segment | 0 | 40 | 500 | 1.0×1.0 | — | Blocking; Gate convert (100 wood) |
| Blacksmith | 100 | 150 | 700 | 2.2×1.8 | CC Tier ≥ 2 | Infantry upgrades; required for Stable / advanced units |
| Stable | 175 | 125 | 700† | 3.0×2.2 | CC Tier ≥ 2 **and** completed Blacksmith | Cavalry units + cavalry upgrades |
| Artillery Depot | 225 | 175 | 750 | 3.2×2.4 | CC Tier ≥ 3 **and** Blacksmith | Cannon |
| Academy | 200 | 150 | 720 | 3.0×2.2 | CC Tier ≥ 3 **and** Blacksmith | Economy / global upgrades |

† **AI placement override:** when the AI constructs a Stable via `enemy_build_manager.gd`, it sets `max_health = 320` (`STABLE_MAX_HEALTH`). Player / scene default remains **700**.

## Command Center tiers

| Tier | Gold | Wood | Research time | Source |
|------|-----:|-----:|--------------:|--------|
| Tier 1 | — | — | — | Starting |
| Tier 2 | 800 | 500 | 60.0 s | `CommandCenter` |
| Tier 3 | 2000 | 1200 | 120.0 s | `CommandCenter` |

## Defensive tower combat

| Stat | Value | Source |
|------|------:|--------|
| Damage | 12 | `tower.gd` |
| Range | 10.0 | |
| Cooldown | 1.5 s | |
| DPS | 8.0 | 12 / 1.5 |
| Projectile | Arrow, speed 20 | |
| Ballistics upgrade | ×1.2 damage | Same as Cannon |

## Trainable units by building

| Building | Units |
|----------|-------|
| Command Center | Worker |
| Barracks | Spearman, Swordsman*, Archer* |
| Stable | Light Cavalry, Cavalry Archer, Heavy Cavalry |
| Artillery Depot | Cannon |
| Hero Altar | Hero |

\* Requires completed Blacksmith (`TechTree.can_train_swordsman_or_archer`).

## Research available by building

| Building | Research |
|----------|----------|
| Command Center | Tier 2, Tier 3 |
| Blacksmith | Swordsman Attack/Armor; Archer Attack/Attack Speed/Range (5 levels each, 5.0 s/level) |
| Stable | Per-cavalry Attack & Defense (5 levels each, 5.0 s/level) |
| Academy | Faster Gathering, Faster Unit Training, Improved Tools, Engineering, Ballistics (1 level each) |

---

# 4. Units

**Combat stats:** unit scripts  
**HP / move speed:** scenes (override `Unit` defaults: move_speed 5.0, stopping_distance 0.25)  
**Food costs:** training building constants / `unit_food_supply.gd`  
**Wood cost:** **0** for all trained units  
**Armor type / damage type:** *not implemented* (flat integer armor only)  
**Vision:** *not implemented*

### Raw combat overview (base, no upgrades)

| Unit | HP | Armor | Dmg | CD | DPS | Range | Move | Collision (box) | Nav radius | Gold | Food | Train time | Req at |
|------|---:|------:|----:|---:|----:|------:|-----:|-----------------|----------:|-----:|-----:|-----------:|---------|
| Worker | 70 | 0 | — | — | — | — | 5.0† | 1×1×1 | 0.55 | 50 | 1 | 3.0 s | CC |
| Spearman | 70 | 0 | 6 | 1.0 | 6.00 | 2.4 | 4.25 | 1×1×1 | 0.55 | 65 | 1 | 5.0 s | Barracks |
| Swordsman | 100 | 0 | 10 | 1.0 | 10.00 | 2.0 | 5.0† | 1×1×1 | 0.55 | 100 | 1 | 4.0 s | Barracks* |
| Archer | 100 | 0‡ | 7 | 1.2 | 5.83 | 8.0 | 5.0† | 1×1×1 | 0.55 | 100 | 1 | 4.0 s | Barracks* |
| Light Cavalry | 80 | 0 | 8 | 0.9 | 8.89 | 2.0 | 9.0 | 1×1×1 | 0.55 | 85 | 1 | 3.5 s | Stable |
| Cavalry Archer | 90 | 0 | 6 | 1.1 | 5.45 | 7.5 | 7.5 | 1×1×1 | 0.55 | 130 | 1 | 5.5 s | Stable |
| Heavy Cavalry | 150 | 2 | 14 | 1.1 | 12.73 | 2.2 | 7.0 | 1×1×1 | 0.55 | 150 | 2 | 7.0 s | Stable |
| Cannon | 120 | 0 | 45 | 5.5 | 8.18 | 14.0 | 6.0 | 1.4×1×1.8 | 0.55 | 275 | 2 | 14.0 s | Artillery Depot |
| Hero (Paladin) | 200 | 0§ | 18 | 0.85 | 21.18 | 2.0 | 5.5 | 1.2×1.2×1.2 | 0.55 | 200 | 2 | 6.0 s | Hero Altar |
| Hero (Shadow Assassin) | 180 | 0§ | 20 | 0.75 | 26.67 | 2.0 | 6.0 | 1.2×1.2×1.2 | 0.55 | 200 | 2 | 6.0 s | Hero Altar |
| Hero (Ranger) | 160 | 0§ | 22 | 0.90 | 24.44 | 8.0 | 5.8 | 1.2×1.2×1.2 | 0.55 | 200 | 2 | 6.0 s | Hero Altar |

† Inherited from `Unit.move_speed = 5.0` (scene does not override).  
‡ Archer **incoming** damage ignores armor (`Archer._compute_incoming_damage` returns `int(amount)`).  
§ Hero **incoming** damage ignores armor (`Hero.take_damage` uses `int(amount)` with no armor subtract, all kits).  
\* Requires Blacksmith. All hero kits cost the same gold/food/train time — see §5 for kit selection at the altar.

DPS = `attack_damage / attack_cooldown` (single-target; Cannon splash can exceed this).

### Special abilities / notes

| Unit | Special |
|------|---------|
| Archer | Fires Arrow projectile (speed 20, hit distance 0.45, max lifetime 5.0 s) |
| Cavalry Archer | Same Arrow projectile |
| Cannon | Artillery shell (speed 14); splash radius **3.5**, min damage ratio **0.5**; Ballistics ×1.2 |
| Hero (Paladin) | Q/W/E/R abilities (see §5); Divine Protection blocks all damage while active |
| Hero (Shadow Assassin) | Q/W/E/R abilities (see §5); Smoke (W) grants combat-hidden status — hidden units are skipped by auto-targeting but remain valid for committed attacks, player orders, and area damage |
| Hero (Ranger) | Q/W/E/R abilities (see §5); ranged basic attacks; Camouflage (R) uses combat-hidden; Bear Trap roots via Buff system; Hunter's Precision every 3rd AA vs same non-building target |
| Worker | Gather, build, repair; no combat attack |

### Passive regen (units)

| Owner | Regen | Source |
|-------|------:|--------|
| Hero | 0.5 HP/s | `HealthComponent.HERO_PASSIVE_REGEN_PER_SECOND` |
| Other army units | 0.25 HP/s | `ARMY_PASSIVE_REGEN_PER_SECOND` |
| Neutral creeps | 0 | Explicitly disabled |
| Buildings | 0 | |

### Projectile speeds

| Projectile | Speed | Hit distance | Max lifetime | Source |
|------------|------:|-------------:|-------------:|--------|
| Arrow | 20.0 | 0.45 | 5.0 s | `arrow.gd` |
| Artillery Shell | 14.0 | 0.60 | 8.0 s | `artillery_shell.gd` |

---

# 5. Heroes

**Three hero kits** exist, selected at the Hero Altar and resolved via `scripts/systems/hero_catalog.gd`
(`HeroCatalog.KIT_PALADIN`, `HeroCatalog.KIT_SHADOW_ASSASSIN`, `HeroCatalog.KIT_RANGER`). All extend the shared
`scripts/units/melee_hero.gd` → `scripts/base/hero.gd` → `scripts/base/unit.gd` chain, and share
ability rank rules, XP/leveling, inventory, and item math. Kit-specific numbers live in
`scripts/balance/hero_stats.gd` (Paladin), `scripts/balance/shadow_assassin_stats.gd` (Assassin), and
`scripts/balance/ranger_stats.gd` (Ranger); ability scaling per rank is resolved kit-aware via
`scripts/systems/hero_ability_stats.gd`.

- **Human Paladin** (`scripts/units/hero.gd`) — durable frontline fighter: Ground Slam, Divine
  Protection, Power Strike, Execute. Passive: **Holy Recovery**.
- **Shadow Assassin** (`scripts/units/shadow_assassin.gd`) — mobile burst/pick assassin: Axe Mark,
  Smoke, Slash, Dash. Passive: **Assassin** (bonus damage on consecutive hits vs. the same target).
- **Ranger** (`scripts/units/ranger.gd`) — fragile ranged ADC/marksman: Combat Roll, Bear Trap,
  Crossbow Bolt, Camouflage. Passive: **Hunter's Precision** (every 3rd consecutive AA vs. the same
  non-building target deals 10% max HP bonus Physical Damage).

All kits share the same ability rank rules, XP curve, respawn/retrain flow, and item interaction
caps documented below; per-kit numbers are called out where they differ.

## Base stats (Level 1)

| Stat | Paladin | Shadow Assassin | Ranger | Source |
|------|--------:|-----------------:|-------:|--------|
| HP | 200 | 180 | 160 | `HeroStats` / `ShadowAssassinStats` / `RangerStats` |
| Mana | 100 | 100 | 100 | shared |
| Mana regen | 5.0 /s | 5.0 /s | 5.0 /s | `mana_regen_rate` |
| Attack damage | 18 | 20 | 22 | |
| Attack cooldown | 0.85 s | 0.75 s | 0.90 s | |
| Attack range | 2.0 | 2.0 | **8.0** | Ranger is ranged |
| Move speed | 5.5 | 6.0 | 5.8 | |
| Armor | *none applied* | *none applied* | *none applied* | Incoming damage ignores armor |
| Inventory slots | 6 | 6 | 6 | `INVENTORY_SLOT_COUNT` (shared) |

## Growth per level

| Stat | Paladin / level | Assassin / level | Ranger / level | Notes |
|------|-----------------:|------------------:|---------------:|-------|
| HP | +25 | +22 | +18 | Levels 2–30 |
| Mana | +10 | +10 | +10 | |
| Attack damage | +2 | +2 | +3 | Ranger stronger AD curve |
| Armor | *none* | *none* | *none* | No armor growth |
| Move speed | +0.05 | +0.05 | +0.05 | **Only after level 18** (shared) |
| Ability points | +1 | +1 | +1 | Levels **2–18** inclusive (shared) |

Max level: **30**. Ability point window: levels 2–18 → **17** points total. Rank rules (max ranks,
level-gated ultimate) are identical for both kits — see **Abilities** below.

### XP requirements

`xp_to_next = 100 × current_level` (`XP_PER_LEVEL_MULTIPLIER`)

| From → To | XP required | Cumulative XP to reach To |
|-----------|------------:|--------------------------:|
| 1 → 2 | 100 | 100 |
| 2 → 3 | 200 | 300 |
| 3 → 4 | 300 | 600 |
| … | `100×L` | … |
| 29 → 30 | 2900 | 43,500 |

Formula for XP to reach level L from 1: `50 × (L−1) × L`.

## Respawn rules

| Rule | Value |
|------|-------|
| Auto-respawn timer | *None* |
| Revival method | Retrain at Hero Altar |
| Retrain cost | 200 gold, 2 food (same for both kits) |
| Retrain time | 6.0 s |
| Progression on death | Saved via `HeroProgressionStore` (level, XP, abilities, inventory, **kit id**) and restored on next train |
| Kit on retrain | Altar auto-spawns the previously trained kit (`HeroProgressionStore.get_saved_kit_id`) — dying as Shadow Assassin and retraining spawns another Shadow Assassin, not the default selection |
| Living hero limit | 1 per side (altar blocks train while hero lives / is training) |

## Kill XP / gold rewards (hero recipient)

**Source:** `hero_xp_rewards.gd`

| Victim | XP | Gold |
|--------|---:|-----:|
| Enemy Worker | 10 | 2 |
| Enemy Military (any army unit) | 25 | 5 |
| Enemy Hero | 150 | 50 |
| Creep (atk ≤ 8) | 25 | 5 |
| Creep (atk 9–12) | 50 | 10 |
| Creep (atk ≥ 13) | 100 | 20 |

Creep XP share range: **18.0** world units from hero.

## Abilities

**Rank rules** (`hero_ability_progression.gd`, shared by both kits):

- Q/W/E: max rank **5**, learnable from level 1 (with points)
- R (ultimate): max rank **3**; unlock ranks at levels **6 / 11 / 16**

**Base stats** (`hero_ability_stats.gd`, resolved kit-aware via `get_stat(ability_id, stat, rank, overrides, kit_id)`);
Paladin mana costs are also mirrored as `@export` on the hero scene script.

## 5a. Human Paladin abilities

### Q — Ground Slam

| Rank | Damage | Radius | Cooldown | Mana |
|-----:|-------:|-------:|---------:|-----:|
| 1 | 35 | 3.5 | 9.0 | 40 |
| 2 | 42 | 3.85 | 8.55 | 44 |
| 3 | 49 | 4.2 | 8.1 | 48 |
| 4 | 56 | 4.55 | 7.65 | 52 |
| 5 | 63 | 4.9 | 7.2 | 56 |

Multipliers: dmg `[1.0,1.2,1.4,1.6,1.8]`, splash `[1.0,1.1,1.2,1.3,1.4]`, CD `[1.0,0.95,0.9,0.85,0.8]`, mana `[1.0,1.1,1.2,1.3,1.4]`.

Effect: instant AoE damage to hostile combat targets in radius (no falloff).

### W — Divine Protection

| Rank | Duration (invuln) | Cooldown | Mana |
|-----:|------------------:|---------:|-----:|
| 1 | 4.0 s | 20.0 | 30 |
| 2 | 4.8 s | 19.0 | 33 |
| 3 | 5.6 s | 18.0 | 36 |
| 4 | 6.4 s | 17.0 | 39 |
| 5 | 7.2 s | 16.0 | 42 |

While active: **all incoming damage ignored**. Cooldown starts when effect ends.

Item Ability Power scales duration by `+0.01 s` per AP point.

### E — Power Strike

| Rank | Damage | Cooldown | Mana |
|-----:|-------:|---------:|-----:|
| 1 | 45 | 10.0 | 25 |
| 2 | 54 | 9.5 | 28 |
| 3 | 63 | 9.0 | 30 |
| 4 | 72 | 8.5 | 33 |
| 5 | 81 | 8.0 | 35 |

Single-target melee nuke. Damage also gains **+item_ability_power**.

### R — Execute

| Rank | HP threshold | Cooldown | Mana |
|-----:|-------------:|---------:|-----:|
| 1 | 40% | 45.0 | 50 |
| 2 | 48% | 40.5 | 60 |
| 3 | 56% | 36.0 | 70 |

Clamped max threshold **75%**. Instantly deals remaining HP as damage if target below threshold. Item AP adds `+0.001` threshold per point (also clamped to 0.75).

### Passive — Holy Recovery

**Source:** `scripts/passives/holy_recovery_passive.gd`, numbers in `scripts/balance/hero_passive_stats.gd`.

| Stat | Value |
|------|------:|
| Out-of-combat delay | 5.0 s (`HOLY_RECOVERY_OUT_OF_COMBAT_SECONDS`) |
| Regen rate | 2% max HP / s (`HOLY_RECOVERY_REGEN_PERCENT_PER_SECOND`) |

While out of combat for the delay window, heals a percentage of max HP per second until back to full or re-engaged.

## 5b. Shadow Assassin abilities

**Source:** `scripts/balance/shadow_assassin_stats.gd` (edit assassin balance only there); scaling
multipliers per rank are the same curves used by the Paladin (`BASIC_*_MULT` / `ULTIMATE_*_MULT` in
`hero_ability_stats.gd`), applied to the Assassin's own base numbers.

### Q — Axe Mark

| Rank | Damage | Consume Bonus | Mark Duration | Cooldown | Mana |
|-----:|-------:|---------------:|--------------:|---------:|-----:|
| 1 | 28 | 40 | 5.0 s | 10.0 | 35 |
| 2 | 34 | 48 | 6.0 s | 9.5 | 39 |
| 3 | 39 | 56 | 7.0 s | 9.0 | 42 |
| 4 | 45 | 64 | 8.0 s | 8.5 | 46 |
| 5 | 50 | 72 | 9.0 s | 8.0 | 49 |

Throws a spinning axe (`SpinningAxe`, travel speed `AXE_MARK_PROJECTILE_SPEED = 16.0`) that deals
damage and applies a mark (`AxeMarkBuff`) to the target for the mark duration. The assassin's next
basic attack on a marked target consumes the mark for the consume bonus damage and refunds
**50%** of the ability's mana cost (`AXE_MARK_MANA_REFUND_RATIO`).

### W — Smoke

| Rank | Duration | Radius | Cooldown | Mana |
|-----:|---------:|-------:|---------:|-----:|
| 1 | 6.0 s | 4.0 | 18.0 | 35 |
| 2 | 7.2 s | 4.4 | 17.1 | 39 |
| 3 | 8.4 s | 4.8 | 16.2 | 42 |
| 4 | 9.6 s | 5.2 | 15.3 | 46 |
| 5 | 10.8 s | 5.6 | 14.4 | 49 |

Drops a ground zone (`AreaBuffZone`) at the assassin's feet. While standing inside: **hidden**
from enemy auto-targeting (`Unit.is_combat_hidden`) and gains `+1.5` move speed
(`SMOKE_MOVE_SPEED_BONUS`). Attacking or casting an ability reveals the assassin for
`SMOKE_REVEAL_SECONDS = 1.25s` before it can re-hide inside the zone.

### E — Slash

| Rank | Damage | Radius | Cooldown | Mana |
|-----:|-------:|-------:|---------:|-----:|
| 1 | 38 | 2.8 | 8.0 | 30 |
| 2 | 46 | 3.08 | 7.6 | 33 |
| 3 | 53 | 3.36 | 7.2 | 36 |
| 4 | 61 | 3.64 | 6.8 | 39 |
| 5 | 68 | 3.92 | 6.4 | 42 |

Instant AoE damage to hostile combat targets in radius around the assassin (no falloff), same
mechanic as Ground Slam.

### R — Dash

| Rank | Damage | Range | Cooldown | Mana |
|-----:|-------:|------:|---------:|-----:|
| 1 | 55 | 7.0 | 20.0 | 40 |
| 2 | 66 | 7.35 | 18.0 | 48 |
| 3 | 77 | 7.7 | 16.0 | 56 |

Prefers the lowest-HP hostile hero in range, otherwise the current attack target, otherwise nearest
hostile. Teleports to melee range of the target (`DASH_ARRIVAL_OFFSET = 1.15`) and deals damage on
arrival.

### Passive — Assassin

**Source:** `scripts/passives/assassin_passive.gd`, numbers in `scripts/balance/hero_passive_stats.gd` /
`shadow_assassin_stats.gd`.

| Stat | Value |
|------|------:|
| Bonus damage per consecutive hit | `+8` flat (`ASSASSIN_PASSIVE_BONUS_DAMAGE`) |
| Bonus damage ratio | `+25%` of attack damage (`ASSASSIN_PASSIVE_ATTACK_DAMAGE_RATIO`) |

Grants bonus physical damage on every basic attack against the same target after the first (i.e.
rewards committing to a single target rather than spreading attacks).

## 5c. Ranger abilities

**Source:** `scripts/balance/ranger_stats.gd` (edit ranger balance only there); scaling multipliers per
rank are the same curves used by other kits (`BASIC_*_MULT` / `ULTIMATE_*_MULT`), except Camouflage
duration which uses explicit per-rank values **12 / 18 / 24**.

### Passive — Hunter's Precision

| Stat | Value |
|------|------:|
| Hits required | Every **3rd** consecutive basic attack vs same target |
| Bonus damage | **10%** of target Maximum Health (`HUNTERS_PRECISION_MAX_HEALTH_RATIO`) |
| Valid targets | Heroes, Units, Creeps |
| Invalid targets | Buildings |
| Reset | Switching targets resets the counter |

### Q — Combat Roll

| Rank | Dash range | Cooldown | Mana |
|-----:|-----------:|---------:|-----:|
| 1 | 5.0 | 10.0 | 25 |
| 2 | 5.25 | 9.5 | 28 |
| 3 | 5.5 | 9.0 | 30 |
| 4 | 5.75 | 8.5 | 33 |
| 5 | 6.0 | 8.0 | 35 |

No damage. Repositions via navigation-snapped movement (cannot pass through blocked terrain). Using
Combat Roll while Camouflaged briefly reveals the Ranger; if no other attack/ability follows,
Camouflage restores after **3.0 s**.

### W — Bear Trap

| Rank | Damage | Root | Cooldown | Mana |
|-----:|-------:|-----:|---------:|-----:|
| 1 | 18 | 2.0 s | 1.0 | 20 |
| 2 | 22 | 2.4 s | 0.95 | 22 |
| 3 | 25 | 2.8 s | 0.9 | 24 |
| 4 | 29 | 3.2 s | 0.85 | 26 |
| 5 | 32 | 3.6 s | 0.8 | 28 |

Charge-based: **3** max charges, **14.0 s** recharge per charge. Trap lifetime **45.0 s**. Trigger
radius **0.85**. Multiple traps may exist. On trigger: Physical Damage + Root buff + reveal while
rooted. Enemy AI soft-avoids hostile traps when pathing.

### E — Crossbow Bolt

| Rank | Damage | Range | Cooldown | Mana |
|-----:|-------:|------:|---------:|-----:|
| 1 | 48 | 12.0 | 12.0 | 40 |
| 2 | 58 | 12.6 | 11.4 | 44 |
| 3 | 67 | 13.2 | 10.8 | 48 |
| 4 | 77 | 13.8 | 10.2 | 52 |
| 5 | 86 | 14.4 | 9.6 | 56 |

Piercing line skillshot. After each pierce, remaining damage is multiplied by
`CROSSBOW_BOLT_PIERCE_DAMAGE_MULT = 0.7`. Projectile speed **22**.

### R — Camouflage

| Rank | Duration | Cooldown | Mana |
|-----:|---------:|---------:|-----:|
| 1 | **12.0 s** | 40.0 | 50 |
| 2 | **18.0 s** | 36.0 | 60 |
| 3 | **24.0 s** | 32.0 | 70 |

While active: combat-hidden (enemies cannot auto-target; friendly player still sees a transparency
cue) and **+1.5** move speed. Ends immediately on Basic Attack, W, or E. Q uses the restore window
described above.

### Item interaction caps

| Cap | Value |
|-----|------:|
| Max cooldown reduction | 40% (shared) |
| Max mana cost reduction | 40% (shared) |
| Ability damage | `base + item_ability_power` (Assassin/Ranger also scale off attack damage per-ability — see `HeroAbilityStats.KIT_ABILITY_SCALING`) |
| Spell radius | `base + item_spell_radius_bonus` (shared) |

---

# 6. Creeps

**Sources:** `neutral_creep.tscn`, `neutral_creep_camps.tscn`, `creep_camp.gd`, `creep_camp_safety.gd`, `enemy_dummy.gd`, `hero_xp_rewards.gd`

## Shared creep defaults

| Stat | Value |
|------|------:|
| HP | 80 |
| Armor | 0 (EnemyDummy path: flat damage) |
| Default attack (script) | 8 |
| Default range | 2.0 |
| Default cooldown | 1.2 |
| Move speed | 3.5 (`CreepCampSafety.CREEP_MOVE_SPEED`) |
| Passive regen | None |
| Special | Camp alert on damage; leash **16**; return home |

## Camp catalog (`scenes/world/neutral_creep_camps.tscn`)

| Camp | Difficulty (name) | Creeps | Atk | CD | DPS each | XP/gold each* |
|------|-------------------|-------:|----:|---:|---------:|---------------|
| StrongCampExpansionUpperRight | Strong | 5 | 16 | 0.95 | 16.84 | 100 XP / 20 G |
| StrongCampExpansionLowerLeft | Strong | 5 | 16 | 0.95 | 16.84 | 100 / 20 |
| StrongCampExpansionUpperMiddle | Strong | 5 | 16 | 0.95 | 16.84 | 100 / 20 |
| StrongCampExpansionLowerMiddle | Strong | 5 | 16 | 0.95 | 16.84 | 100 / 20 |
| MediumCampNorthCenter | Medium | 6 | 11 | 1.1 | 10.00 | 50 / 10 |
| MediumCampSouthCenter | Medium | 6 | 11 | 1.1 | 10.00 | 50 / 10 |
| MediumCampCentralCrossroads | Medium | 6 | 11 | 1.1 | 10.00 | 50 / 10 |

\* Reward tier from attack_damage: ≤8 weak, ≤12 medium, else strong.

### Respawn / leash rules

| Rule | Value |
|------|------:|
| Respawn delay after camp clear | **180 s** |
| Respawn blocked if units nearby | radius **20** |
| Camp guards resources | radius **20** |
| Creep leash | **16** |
| Home tolerance | 1.25 |

---

# 7. Items

**Sources:** `hero_item_catalog.gd`, `hero_item_service.gd`, `hero_item_definition.gd`

**Sell value:** `floor(gold_cost × 0.5)` (`SELL_REFUND_RATIO = 0.5`)  
**Stack rules:** No stacking; one item per inventory slot; 6 slots.  
**Active effects:** *None* (`is_active_item` unused).  
**Requirements:** Hero in shop range (world fallback **4.5**, or camera-projected **200 px**); shop completed; inventory space; gold.

### Sold in starter shop (`SHOP_ITEM_ORDER`)

| Item | Cost | Stats / on-purchase | Sell |
|------|-----:|---------------------|-----:|
| Long Sword | 350 | +10 attack damage | 175 |
| Ruby Crystal | 400 | +100 max HP; heal 100 on buy | 200 |
| Boots | 300 | +10.0 move speed | 150 |
| Wizard Orb | 450 | +75 max mana; restore 75 mana on buy | 225 |

### Defined but not in starter shop order

| Item | Cost | Stats | Sell |
|------|-----:|-------|-----:|
| Mage Ring | 400 | +20 Ability Power | 200 |
| Mana Crystal | 450 | +100 max mana; +10% mana cost reduction | 225 |
| Sorcerer Staff | 550 | +40 AP; +10% CDR | 275 |
| Arcane Boots | 400 | +10.0 move speed; +10% CDR | 200 |
| Archmage Orb | 700 | +80 AP; +15% CDR | 350 |

---

# 8. Upgrades

**Source:** `upgrade_manager.gd` (+ research durations on buildings)

## Blacksmith (max level 5 each)

Research time: **5.0 s** per level (`Blacksmith.RESEARCH_SECONDS`).

**Cost per next level** (gold = wood = `LEVEL_COSTS[level]`):

| Current → Next | Gold | Wood |
|----------------|-----:|-----:|
| 0 → 1 | 100 | 100 |
| 1 → 2 | 150 | 150 |
| 2 → 3 | 225 | 225 |
| 3 → 4 | 325 | 325 |
| 4 → 5 | 450 | 450 |

| Upgrade ID | Exact bonus per level |
|------------|------------------------|
| `swordsman_attack` | Swordsman damage **+2** |
| `swordsman_armor` | Swordsman armor **+1** (armor = level) |
| `archer_attack` | Archer damage **+2** |
| `archer_attack_speed` | Archer cooldown × `(1 − 0.05 × level)` |
| `archer_range` | Archer range **+8.0** per level |

**Fully upgraded examples:**

| Unit / upgrade | Base | Max (L5) |
|----------------|------|----------|
| Swordsman damage | 10 | 20 |
| Swordsman armor | 0 | 5 |
| Archer damage | 7 | 17 |
| Archer cooldown | 1.2 | 0.9 |
| Archer range | 8.0 | **48.0** |

## Stable cavalry upgrades (max level 5 each)

Research time: **5.0 s** per level.

Cost: `gold = 150 + level×100`, `wood = 75 + level×50` (level = current):

| Current → Next | Gold | Wood |
|----------------|-----:|-----:|
| 0 → 1 | 150 | 75 |
| 1 → 2 | 250 | 125 |
| 2 → 3 | 350 | 175 |
| 3 → 4 | 450 | 225 |
| 4 → 5 | 550 | 275 |

| Upgrade | Bonus per level |
|---------|-----------------|
| `*_attack` (light / heavy / cavalry_archer) | **+3** damage |
| `*_defense` | **+1** armor |

## Academy (max level 1 each)

| Upgrade | Gold | Wood | Time | Effect |
|---------|-----:|-----:|-----:|--------|
| Faster Gathering | 1000 | 700 | 60 s | Gather speed × **1.25** |
| Faster Unit Training | 1200 | 900 | 75 s | Train time ÷ **1.2** |
| Improved Tools | 900 | 700 | 60 s | Construction speed × **1.2** |
| Engineering | 1500 | 1200 | 90 s | Building max HP × **1.2** (completed buildings) |
| Ballistics | 1800 | 1200 | 90 s | Tower & Cannon damage × **1.2** |

Requirements: Academy built (needs CC Tier 3 + Blacksmith).

---

# 9. Combat Formula

## Damage calculation

1. Attacker deals `attack_damage` (float passed into pipeline).
2. Victim applies armor (when implemented):

```
final_damage = max(1, int(amount) - armor)
```

Source: `UnitCombatDamage.compute_armored_damage`.

3. Exceptions:
   - **Archer** receiving damage: `int(amount)` (armor ignored)
   - **Hero** receiving damage: `int(amount)` (armor ignored); if Divine Protection active → **0**
   - **Buildings / CC / Tower**: `maxi(0, int(amount))` (no armor, can be 0)
   - **Cannon / Heavy Cavalry / Cavalry Archer** (custom `take_damage`): same as armored formula `max(1, int(amount) - armor)`

## Armor calculation

- Flat integer subtract.
- Minimum damage **1** after armor (for units using the armored formula).
- No armor types, no percent mitigation, no hard/soft armor.

## Critical strikes

**Not implemented.**

## Lifesteal

**Not implemented.**

## Regeneration

| Target | Rate |
|--------|-----:|
| Hero HP | 0.5 /s |
| Army unit HP | 0.25 /s |
| Hero mana | 5.0 /s |
| Creeps / buildings | 0 |

Regen accumulates fractional HP and heals integer amounts when accumulator ≥ 1.

## Projectile hit logic

| Type | Behavior |
|------|----------|
| Arrow | Flies in straight horizontal line at spawn→target direction; hits after traveling `distance + 0.45` or lifetime 5 s; applies damage to original target if still valid |
| Artillery shell | Aims at target position at launch; on impact applies **splash** (does not require target still alive at impact) |

## Splash damage

```
falloff = lerp(1.0, min_damage_ratio, distance / radius)
damage = max(1.0, base_damage * falloff)
```

Default `min_damage_ratio = 0.5`. Used by Cannon (radius 3.5). Ground Slam does **not** use falloff (full damage in radius).

## Cleave

**Not implemented.**

## Magic damage

**Not implemented** (no damage schools).

## Healing

| Source | Behavior |
|--------|----------|
| `HealthComponent.heal` | Adds HP up to max |
| Ruby Crystal | +100 max HP and heal 100 on purchase |
| Passive regen | See above |
| Level-up | +25 current & max HP |

## Death handling

1. `health_depleted` → unit/building death callback.
2. `HeroXpRewards.notify_unit_killed` grants XP/gold (once; meta guard).
3. Units: `die()` then `queue_free()`.
4. Buildings: destroy / free; Farm removes food-cap contribution on death path.
5. If destroyed node is the tracked main CC → match Victory/Defeat.
6. Hero death: progression saved; altar can retrain.

---

# 10. AI Economy

**No resource cheats.** AI starts with the same 500/500/15 as the player (`EnemyResourceManager` uses `MatchConfig`).

## Starting resources

| Resource | AI value |
|----------|---------:|
| Gold | 500 |
| Wood | 500 |
| Food current | 0 then initialized from scene workers |
| Food max | 15 |

## Worker targets by match time

| Phase | Time gate | Target workers |
|-------|----------:|---------------:|
| Early | < 180 s | 14 |
| Mid | ≥ 180 s | 22 |
| Late | ≥ 360 s | 30 |
| Endgame | ≥ 600 s | 36 |
| Endgame high | (extra) | 45 |
| Hard safety cap | — | 50 |

Other worker gates:

| Gate | Value |
|------|------:|
| Min workers before military | 6 (4 if abundant) |
| Opening first farm at worker count | 5 |
| Worker rebuild threshold | 60% of target |
| Opening worker target (director) | 12 |
| Expansion saturation workers | 16 |

## Expansion timing

| Rule | Value |
|------|------:|
| Expansion desire near mine distance | 22 |
| Placement retry | 10 s |
| Expansion mine min workers | 5 |

## Attack timing

| Rule | Value | Source |
|------|------:|--------|
| Standard attack timer | 240 s | `EnemyArmyCommand` / `EnemyWaveManager` |
| Desperate attack timer | 360 s | |
| Min combat units (fallback) | 12 | |
| Min non-hero for standard attack | 6–12 (wave dependent) | |
| Strength ratio to attack (normal) | 1.15× player | |
| Aggressive ratio | 1.05× | |
| Min hero level for attack | 2 | `EnemyWaveManager` |
| Min cleared camps for attack | 2 | |
| Hero retreat HP | 35% | |
| Hero wave join HP | 60% | |

Wave non-hero minima: Wave1 **6**, Wave2 **12**, Wave3 **16**.

## Tech timing (AI buffers / gates)

| Gate | Value |
|------|------:|
| Tier 2 gold/wood buffer before upgrade | +250 G / +150 W |
| Tier 3 gold/wood buffer | +400 G / +250 W |
| Tier 3 min workers | 14 |
| Tier 3 min farms | 3 |
| Tier 3 min free population | 6 |
| Tier 3 min army | 18 |
| Max enemy cannons | 3 |
| Min player army before cannons | 12 |
| Shop gold buffer before Stable spend | 350 |
| Academy research army gold buffer | `2 × Barracks.TRAIN_GOLD_COST` = 200 |

## Desired army sizes

| Phase | Desired army |
|-------|-------------:|
| Early | 28 |
| Mid (≥300 s) | 45 |
| Late (≥600 s) | 60 |

Director early pikemen targets: soft 8, target 10, min 5.

## Gather ratios

See §2 AI assignment recommendations.

---

# 11. Global Constants

Gameplay-affecting constants not fully listed above:

### Match / population

| Constant | Value | File |
|----------|------:|------|
| `NORMAL_STARTING_GOLD` | 500 | match_config.gd |
| `NORMAL_STARTING_WOOD` | 500 | |
| `STARTING_FOOD_MAX` | 15 | |
| `STARTING_WORKER_COUNT` | 5 | |
| `FOOD_CAP_BONUS` | 8 | farm.gd |

### Gathering

| Constant | Value | File |
|----------|------:|------|
| `GATHER_WAIT_SECONDS` | 1.0 | gathering_config.gd |
| `WORKER_CARRY_CAPACITY` | 10 | |
| `GATHER_CHUNK_GOLD` | 5 | |
| `GATHER_CHUNK_WOOD` | 2 | |
| `TREE_STARTING_WOOD` | 5000 | |
| `GOLD_MINE_STARTING_GOLD` | 20000 | |
| `FASTER_GATHERING_SPEED_MULTIPLIER` | 1.25 | upgrade_manager.gd |

### Construction

| Constant | Value | File |
|----------|------:|------|
| Default 1/2/3+ worker durations | 4.0 / 2.5 / 2.0 | build_manager.gd |
| Shop 1/2/3+ | 3.5 / 2.2 / 1.8 | |
| Wall 1/2/3+ | 8.0 / 5.0 / 4.0 | |
| `IMPROVED_TOOLS_CONSTRUCTION_SPEED_MULTIPLIER` | 1.2 | upgrade_manager.gd |
| `ENGINEERING_MAX_HEALTH_MULTIPLIER` | 1.2 | |
| `BUILD_RANGE` | 2.5 | building.gd |
| `BUILDING_PADDING` | 0.8 | enemy_build_placement.gd |
| `GRID_SIZE` | 1.0 | |
| Map bounds | X/Z ∈ [−50, 50] | |

### Combat / movement shared

| Constant | Value | File |
|----------|------:|------|
| Default unit `move_speed` | 5.0 | unit.gd |
| `stopping_distance` | 0.25 | |
| Attack-move engagement range | 14.0 (18.0 cannon) | military / unit scripts |
| Opportunistic chase leash | 18.0 | |
| Combat target scan interval | 0.45 ± jitter 0.30 | unit.gd |
| Armor formula floor | 1 | unit_combat_damage.gd |
| Splash default min ratio | 0.5 | splash_damage.gd |
| `BALLISTICS_DAMAGE_MULTIPLIER` | 1.2 | upgrade_manager.gd |
| `FASTER_UNIT_TRAINING_SPEED_MULTIPLIER` | 1.2 | |
| Hero regen / army regen | 0.5 / 0.25 | health_component.gd |

### Hero system

| Constant | Value | File |
|----------|------:|------|
| `MAX_LEVEL` | 30 | hero.gd |
| `XP_PER_LEVEL_MULTIPLIER` | 100 | |
| `HEALTH_PER_LEVEL` | 25 | |
| `MANA_PER_LEVEL` | 10 | |
| `ATTACK_DAMAGE_PER_LEVEL` | 2 | |
| `MAX_COOLDOWN_REDUCTION` | 0.4 | |
| `MAX_MANA_COST_REDUCTION` | 0.4 | |
| `SELL_REFUND_RATIO` | 0.5 | hero_item_service.gd |
| `CREEP_XP_SHARE_RANGE` | 18.0 | hero_xp_rewards.gd |

### Creeps

| Constant | Value | File |
|----------|------:|------|
| `RESPAWN_DELAY_SECONDS` | 180 | creep_camp.gd |
| `CREEP_LEASH_DISTANCE` | 16 | creep_camp_safety.gd |
| `CAMP_GUARD_RADIUS` | 20 | |
| `CREEP_MOVE_SPEED` | 3.5 | |

### Gate conversion

| Constant | Value | File |
|----------|------:|------|
| `GATE_CONVERSION_WOOD_COST` | 100 | wall_segment.gd |

---

# 12. Balance Summary

Computed from **base (unupgraded) stats only**. Suggestions are omitted; items below are **observations visible from the data**.

## Strongest units by raw combat stats

| Metric | Leader | Value |
|--------|--------|------:|
| Highest DPS | Hero | 21.18 |
| Highest single-hit damage | Cannon | 45 (splash) |
| Highest HP (army) | Heavy Cavalry | 150 |
| Highest HP (overall trainable) | Hero | 200 |
| Highest armor | Heavy Cavalry | 2 |
| Longest range | Cannon | 14.0 |
| Fastest move | Light Cavalry | 9.0 |

## Weakest units (raw)

| Metric | Unit | Value |
|--------|------|------:|
| Lowest military HP | Spearman | 70 |
| Lowest military damage | Spearman / Cavalry Archer | 6 |
| Lowest military DPS | Cavalry Archer | 5.45 |
| Slowest military | Spearman | 4.25 |

## Most efficient (DPS per gold)

| Unit | DPS | Gold | DPS/Gold |
|------|----:|-----:|---------:|
| Hero | 21.18 | 200 | 0.106 |
| Light Cavalry | 8.89 | 85 | 0.105 |
| Swordsman | 10.00 | 100 | 0.100 |
| Spearman | 6.00 | 65 | 0.092 |
| Heavy Cavalry | 12.73 | 150 | 0.085 |
| Cannon | 8.18 | 275 | 0.030 |
| Archer | 5.83 | 100 | 0.058 |
| Cavalry Archer | 5.45 | 130 | 0.042 |

(Food cost ignored in this ratio.)

## Cost extremes

| | Unit | Gold | Food |
|--|------|-----:|-----:|
| Cheapest military | Spearman | 65 | 1 |
| Most expensive military | Cannon | 275 | 2 |
| Cheapest trainable | Worker | 50 | 1 |

## Fastest units

1. Light Cavalry — 9.0  
2. Cavalry Archer — 7.5  
3. Heavy Cavalry — 7.0  
4. Cannon — 6.0  
5. Hero — 5.5  

## Highest DPS units

1. Hero — 21.18  
2. Heavy Cavalry — 12.73  
3. Swordsman — 10.00  
4. Light Cavalry — 8.89  
5. Cannon — 8.18 (single target; splash can exceed)  

## Highest HP units

1. Hero — 200  
2. Heavy Cavalry — 150  
3. Cannon — 120  
4. Swordsman / Archer — 100  
5. Cavalry Archer — 90  

## Existing balance concerns visible from the data only

1. **Archer range upgrade scales +8 per level** → max range **48**, while towers are range 10 and cannons 14.
2. **Boots grant +10.0 move_speed** on a hero whose base is 5.5 → resulting speed **15.5** (faster than Light Cavalry at 9.0).
3. **Armor is inconsistently applied:** Archers and Heroes ignore armor when taking damage; other units use flat armor.
4. **No damage/armor types, crits, lifesteal, cleave, or magic** — combat is nearly flat arithmetic.
5. **AI Stable HP override 320 vs scene 700** — AI stables are weaker than player stables if that path is used.
6. **Building costs are duplicated** in `build_manager.gd` and `enemy_build_manager.gd` (currently equal; drift risk).
7. **Cavalry Archer** has low DPS/gold (0.042) versus Light Cavalry (0.105) at similar tech.
8. **Spearman** shares Worker HP (70) and is the only Barracks unit that does not require Blacksmith, but has the lowest damage.
9. **Five catalog items** (Mage Ring, Mana Crystal, Sorcerer Staff, Arcane Boots, Archmage Orb) exist in code but are **not** listed in `SHOP_ITEM_ORDER`.
10. **Fog of war / sight radii are unimplemented** — vision is not a balance lever yet.
11. **Hero Divine Protection** is full invulnerability (not damage reduction), duration up to 7.2 s at rank 5 before item scaling.
12. **Population** starts at 15 with 5 workers already using food → **10 free** population at match start before the first farm.

---

*End of Balance Bible. All values traced to the repository sources listed in each section.*
