# Endless Battle — Balance Bible V2

> Complete source-of-truth balance document generated from embedded code-extracted values.
> Calculated estimates are labeled `[CALC]`. Missing values: `NOT FOUND`. Disagreements: `CONFLICT`.
> No invented gameplay values. No rebalance proposals in §14.

**Document date:** 2026-08-04
**Canonical balance tables:** `scripts/balance/`

---

## Source map

| Area | Canonical path |
|------|----------------|
| economy | `scripts/balance/economy_stats.gd` |
| unit | `scripts/balance/unit_stats.gd` |
| building | `scripts/balance/building_stats.gd` |
| hero | `scripts/balance/hero_stats.gd` |
| assassin | `scripts/balance/shadow_assassin_stats.gd` |
| ranger | `scripts/balance/ranger_stats.gd` |
| passive | `scripts/balance/hero_passive_stats.gd` |
| upgrade | `scripts/balance/upgrade_stats.gd` |
| item | `scripts/balance/item_stats.gd` |
| ability | `scripts/systems/hero_ability_stats.gd` |
| progression | `scripts/systems/hero_ability_progression.gd` |
| damage | `scripts/systems/damage_service.gd` |
| matrix | `scripts/balance/damage_armor_matrix.gd` |
| placement | `scripts/systems/enemy_build_placement.gd` |
| barracks | `scripts/buildings/barracks.gd` |
| ai_cfg | `scripts/systems/military_ai_config.gd` |
| gather | `scripts/systems/enemy_gather_manager.gd` |
| build_mgr | `scripts/systems/enemy_build_manager.gd` |
| towers | `scripts/systems/enemy_attack_path_defense.gd` |
| creeps_scene | `scenes/world/neutral_creep_camps.tscn` |
| xp | `scripts/systems/hero_xp_rewards.gd` |
| match | `scripts/systems/match_manager.gd` |

# 1. Match rules and pacing

**Sources:** `scripts/balance/economy_stats.gd`, `scripts/systems/match_manager.gd`, `scripts/balance/building_stats.gd`, `scripts/systems/hero_ability_progression.gd`, `scripts/systems/military_ai_config.gd`

| Rule | Value | Source |
|------|------:|--------|
| Starting gold | 500 | `scripts/balance/economy_stats.gd` |
| Starting wood | 500 | `scripts/balance/economy_stats.gd` |
| Starting food used | 5 | equals starting workers |
| Starting food cap | 15 | `scripts/balance/economy_stats.gd` |
| Maximum population | food cap (grows via farms +8/farm) | farm |
| Starting workers | 5 | `scripts/balance/economy_stats.gd` |
| Victory | destroy enemy Command Center | `match_manager.gd` |
| Defeat | player Command Center destroyed | `match_manager.gd` |
| Other win conditions | NOT FOUND | — |
| Hero train cost | 200g / 2 food / 6.0s | `scripts/balance/hero_stats.gd` |
| Hero max level | 30 | `scripts/balance/hero_stats.gd` |
| Hero inventory slots | 6 | `scripts/balance/hero_stats.gd` |
| Hero limit per team | **1 living hero per faction** | `hero_altar.gd` (`has_living_owner_hero`) |
| Hero retraining | Same as train (200g / 2 food / 6.0s); restores level/XP/abilities/inventory snapshot; kit locked for match | `HeroStats` + `HeroProgressionStore` |
| Hero free respawn timer / cost-by-level | NOT FOUND (flat altar retrain only) | — |
| CC Tier 2 | 800g / 500w / 60.0s | `scripts/balance/building_stats.gd` |
| CC Tier 3 | 2000g / 1200w / 120.0s | `scripts/balance/building_stats.gd` |
| Ultimate unlock levels | 6 / 11 / 16 | `scripts/systems/hero_ability_progression.gd` |
| Ability points levels | 2–18 | `scripts/balance/hero_stats.gd` |

### AI V2 early timing thresholds (implemented)

| Threshold | Value |
|-----------|------:|
| Creep-ready military | 5 |
| Attack-ready military | 10 (preferred 12) |
| Lethal min military | 6 |
| Early creep hero level goal | 3 |
| Preferred camps before attack | 2 |
| Camp respawn | 180.0s |

# 2. Economy

**Sources:** `scripts/balance/economy_stats.gd`, `scripts/systems/enemy_gather_manager.gd`, `scripts/balance/building_stats.gd`

## Resources

| Resource | Chunk | Carry | Gather wait | Stockpile |
|----------|------:|------:|------------:|----------:|
| Gold | 5 | 10 | 1.0s | mine 20000 |
| Wood | 2 | 10 | 1.0s | tree 5000 |
| Food | cap only | — | — | start cap 15 |

## Worker

| Stat | Value | Source |
|------|------:|--------|
| HP | 70 | `scripts/balance/unit_stats.gd` |
| Move speed | 5.0 | `scripts/balance/unit_stats.gd` |
| Gold cost | 50 | `scripts/balance/unit_stats.gd` |
| Food | 1 | `scripts/balance/unit_stats.gd` |
| Train time | 3.0s | `scripts/balance/unit_stats.gd` |

- [CALC] ideal gold/worker/min (no travel) = (10 / (2×1.0s)) × 60 = 300.0
- [CALC] ideal wood/worker/min (no travel) = (10 / (5×1.0s)) × 60 = 120.0
- [CALC] worker gold payback (ideal) ≈ 50 / 300.0 gpm ≈ 10.0s
- [CALC] farm cost 80g/20w → +8 food; expansion CC 200g/400w
- [CALC] early 4-gold/1-wood split (AI STARTING_GOLD_WORKERS=4): ideal ≈ 1200 gpm + 120 wpm
- Travel/deposit times: pathing-based — NOT FOUND as fixed constants
- Repair cost/rate: NOT FOUND
- Item sell refund ratio: 0.5 (`scripts/balance/item_stats.gd`)
- AI resource cheats/multipliers: NOT FOUND

### AI gather ratios

| Setting | Value | Source |
|---------|------:|--------|
| STARTING_GOLD_WORKERS | 4 | `scripts/systems/enemy_gather_manager.gd` |
| EARLY_GAME_GOLD_RATIO | 0.7 | `scripts/systems/enemy_gather_manager.gd` |
| MID_GAME_GOLD_RATIO | 0.6 | `scripts/systems/enemy_gather_manager.gd` |
| LATE_GAME_GOLD_RATIO | 0.55 | `scripts/systems/enemy_gather_manager.gd` |
| BUILDING_PRESSURE_GOLD_RATIO | 0.45 | `scripts/systems/enemy_gather_manager.gd` |
| MIN_WOOD_WORKERS_WHEN_TREES_EXIST | 1 | `scripts/systems/enemy_gather_manager.gd` |

# 3. Buildings (11)

**Sources:** `scripts/balance/building_stats.gd`, `scripts/systems/enemy_build_placement.gd`

| ID | Name | Gold | Wood | HP | Food | Footprint | Tier | Notes |
|----|------|-----:|-----:|---:|-----:|-----------|-----:|-------|
| `farm` | Farm | 80 | 20 | 250 | 8 | 2.0×1.4 | 1 | — |
| `barracks` | Barracks | 150 | 100 | 300 | — | 3.5×2.5 | 1 | trains: spearman, swordsman, archer |
| `blacksmith` | Blacksmith | 100 | 150 | 700 | — | 2.2×1.8 | 1 | upgrades: swordsman/archer BS lines |
| `stable` | Stable | 175 | 125 | 700 | — | 3.0×2.2 | 2 | AI stable HP override 320 (CONFLICT vs player 700); trains: light_cavalry, cavalry_archer, heavy_cavalry; upgrades: cavalry attack/defense |
| `artillery_depot` | Artillery Depot | 225 | 175 | 750 | — | 3.2×2.4 | 3 | trains: cannon |
| `academy` | Academy | 200 | 150 | 720 | — | 3.0×2.2 | 3 | upgrades: academy one-shots |
| `shop` | Shop | 80 | 120 | 600 | — | 2.0×1.6 | 1 | — |
| `tower` | Tower | 120 | 80 | 350 | — | 2.0×2.0 | 1 | atk 12 rng 10.0 cd 1.5 |
| `wall_segment` | Wall | 0 | 40 | 500 | — | 1.0×1.0 | 1 | gate conversion wood 100 |
| `hero_altar` | Hero Altar | 180 | 110 | 350 | — | 3.0×3.0 | 1 | trains: heroes |
| `command_center` | Command Center | 200 | 400 | 500 | — | 3.5×3.5 | 1 | T2 (800, 500, 60.0); T3 (2000, 1200, 120.0); trains: worker |

### Construction durations (player)

| Kind | 1 worker | 2 workers | 3+ workers |
|------|---------:|----------:|-----------:|
| Default | 4.0s | 2.5s | 2.0s |
| Shop | 3.5s | 2.2s | 1.8s |
| Wall | 8.0s | 5.0s | 4.0s |
| AI flat construction | 4.0s | — | — |

| Field | Value |
|-------|------:|
| Building armor | NOT FOUND |
| Building armor type | BUILDING (matrix) |
| Building regen | NOT FOUND |
| Sight range | NOT FOUND |
| Production queue limits | barracks enemy max queue 3 (ENEMY); player NOT FOUND as single const |
| Sell/refund buildings | NOT FOUND |

- [CALC] Tower DPS = 12 / 1.5 = 8.00

# 4. Normal units (8)

**Source:** `scripts/balance/unit_stats.gd`

| ID | HP | MS | Dmg | Rng | CD | Armor | Gold | Food | Train | DPS [CALC] | HP/g [CALC] | DPS/g [CALC] | Food eff DPS/food [CALC] |
|----|---:|---:|----:|----:|---:|------:|-----:|-----:|------:|-----------:|------------:|-------------:|-------------------------:|
| `worker` | 70 | 5 | — | — | — | 0 | 50 | 1 | 3s | — | 1.4 | — | — |
| `spearman` | 70 | 4.25 | 6 | 2.4 | 1 | 0 | 65 | 1 | 5s | 6 | 1.077 | 0.0923 | 6 |
| `swordsman` | 100 | 5 | 10 | 2 | 1 | 0 | 100 | 1 | 4s | 10 | 1 | 0.1 | 10 |
| `archer` | 100 | 5 | 7 | 8 | 1.2 | 0 | 100 | 1 | 4s | 5.83 | 1 | 0.0583 | 5.83 |
| `light_cavalry` | 80 | 9 | 8 | 2 | 0.9 | 0 | 85 | 1 | 3.5s | 8.89 | 0.941 | 0.1046 | 8.89 |
| `cavalry_archer` | 90 | 7.5 | 6 | 7.5 | 1.1 | 0 | 130 | 1 | 5.5s | 5.45 | 0.692 | 0.042 | 5.45 |
| `heavy_cavalry` | 150 | 7 | 14 | 2.2 | 1.1 | 2 | 150 | 2 | 7s | 12.73 | 1 | 0.0848 | 6.36 |
| `cannon` | 120 | 6 | 45 | 14 | 5.5 | 0 | 275 | 2 | 14s | 8.18 | 0.436 | 0.0298 | 4.09 |

- `swordsman` upgrades: +2 dmg/bs level; armor=bs armor level
**CONFLICT — Archer:** Barracks runtime train cost/time for archer uses SWORDSMAN_* consts (scripts/buildings/barracks.gd TRAIN_GOLD_COST / TRAIN_SECONDS fallback); UnitStats also defines ARCHER_GOLD_COST=100 / ARCHER_TRAIN_SECONDS=4.0 (same numeric values today).

- `archer` upgrades: +2 dmg; -5%cd/level; +8 range/level; incoming armor bypass
- `archer` projectile speed 20.0
- `cannon` splash radius 3.5, min ratio 0.5; projectile speed 14.0

| Field (all units unless noted) | Value |
|-------------------------------|------:|
| HP regen (army) | 0.25 /s (`UnitStats.ARMY_PASSIVE_REGEN_PER_SECOND`) |
| Mana | NOT FOUND (non-heroes) |
| Damage type | physical (pipeline default) |
| Armor type | MEDIUM default (unit base); HERO for heroes |
| Acceleration / rotation / collision / vision / acquisition | NOT FOUND |
| Wood cost | 0 / NOT FOUND as separate field (gold-only train) |

# 5. Heroes — level 1–30 tables

**Shared:** max 30; XP to next = 100×level; AP levels 2–18; R unlocks (6, 11, 16); inventory 6; regen 0.5 HP/s; mana regen 5.0; armor 0 (no growth); armor type HERO; MS +0.05 after 18; train 200g/2f/6.0s; max CDR/MCR 0.4.

| Field | Value |
|-------|------:|
| Respawn time by level | NOT FOUND |
| Vision | NOT FOUND |

## Paladin (`paladin`)

**Source:** `scripts/balance/hero_stats.gd`

Base L1: HP 200+25/lvl, mana 100+10, dmg 18+2, CD 0.85, rng 2.0, MS 5.5.

| Lv | HP | Mana | AD | Armor | MS | XP→next | Cum XP to reach | DPS [CALC] |
|---:|---:|-----:|---:|------:|---:|--------:|----------------:|-----------:|
| 1 | 200 | 100 | 18 | 0 | 5.5 | 100 | 0 | 21.18 |
| 2 | 225 | 110 | 20 | 0 | 5.5 | 200 | 100 | 23.53 |
| 3 | 250 | 120 | 22 | 0 | 5.5 | 300 | 300 | 25.88 |
| 4 | 275 | 130 | 24 | 0 | 5.5 | 400 | 600 | 28.24 |
| 5 | 300 | 140 | 26 | 0 | 5.5 | 500 | 1000 | 30.59 |
| 6 | 325 | 150 | 28 | 0 | 5.5 | 600 | 1500 | 32.94 |
| 7 | 350 | 160 | 30 | 0 | 5.5 | 700 | 2100 | 35.29 |
| 8 | 375 | 170 | 32 | 0 | 5.5 | 800 | 2800 | 37.65 |
| 9 | 400 | 180 | 34 | 0 | 5.5 | 900 | 3600 | 40 |
| 10 | 425 | 190 | 36 | 0 | 5.5 | 1000 | 4500 | 42.35 |
| 11 | 450 | 200 | 38 | 0 | 5.5 | 1100 | 5500 | 44.71 |
| 12 | 475 | 210 | 40 | 0 | 5.5 | 1200 | 6600 | 47.06 |
| 13 | 500 | 220 | 42 | 0 | 5.5 | 1300 | 7800 | 49.41 |
| 14 | 525 | 230 | 44 | 0 | 5.5 | 1400 | 9100 | 51.76 |
| 15 | 550 | 240 | 46 | 0 | 5.5 | 1500 | 10500 | 54.12 |
| 16 | 575 | 250 | 48 | 0 | 5.5 | 1600 | 12000 | 56.47 |
| 17 | 600 | 260 | 50 | 0 | 5.5 | 1700 | 13600 | 58.82 |
| 18 | 625 | 270 | 52 | 0 | 5.5 | 1800 | 15300 | 61.18 |
| 19 | 650 | 280 | 54 | 0 | 5.55 | 1900 | 17100 | 63.53 |
| 20 | 675 | 290 | 56 | 0 | 5.6 | 2000 | 19000 | 65.88 |
| 21 | 700 | 300 | 58 | 0 | 5.65 | 2100 | 21000 | 68.24 |
| 22 | 725 | 310 | 60 | 0 | 5.7 | 2200 | 23100 | 70.59 |
| 23 | 750 | 320 | 62 | 0 | 5.75 | 2300 | 25300 | 72.94 |
| 24 | 775 | 330 | 64 | 0 | 5.8 | 2400 | 27600 | 75.29 |
| 25 | 800 | 340 | 66 | 0 | 5.85 | 2500 | 30000 | 77.65 |
| 26 | 825 | 350 | 68 | 0 | 5.9 | 2600 | 32500 | 80 |
| 27 | 850 | 360 | 70 | 0 | 5.95 | 2700 | 35100 | 82.35 |
| 28 | 875 | 370 | 72 | 0 | 6 | 2800 | 37800 | 84.71 |
| 29 | 900 | 380 | 74 | 0 | 6.05 | 2900 | 40600 | 87.06 |
| 30 | 925 | 390 | 76 | 0 | 6.1 | 0 | 43500 | 89.41 |

## Shadow Assassin (`shadow_assassin`)

**Source:** `scripts/balance/shadow_assassin_stats.gd`

Base L1: HP 180+22/lvl, mana 100+10, dmg 20+2, CD 0.75, rng 2.0, MS 6.0.

| Lv | HP | Mana | AD | Armor | MS | XP→next | Cum XP to reach | DPS [CALC] |
|---:|---:|-----:|---:|------:|---:|--------:|----------------:|-----------:|
| 1 | 180 | 100 | 20 | 0 | 6 | 100 | 0 | 26.67 |
| 2 | 202 | 110 | 22 | 0 | 6 | 200 | 100 | 29.33 |
| 3 | 224 | 120 | 24 | 0 | 6 | 300 | 300 | 32 |
| 4 | 246 | 130 | 26 | 0 | 6 | 400 | 600 | 34.67 |
| 5 | 268 | 140 | 28 | 0 | 6 | 500 | 1000 | 37.33 |
| 6 | 290 | 150 | 30 | 0 | 6 | 600 | 1500 | 40 |
| 7 | 312 | 160 | 32 | 0 | 6 | 700 | 2100 | 42.67 |
| 8 | 334 | 170 | 34 | 0 | 6 | 800 | 2800 | 45.33 |
| 9 | 356 | 180 | 36 | 0 | 6 | 900 | 3600 | 48 |
| 10 | 378 | 190 | 38 | 0 | 6 | 1000 | 4500 | 50.67 |
| 11 | 400 | 200 | 40 | 0 | 6 | 1100 | 5500 | 53.33 |
| 12 | 422 | 210 | 42 | 0 | 6 | 1200 | 6600 | 56 |
| 13 | 444 | 220 | 44 | 0 | 6 | 1300 | 7800 | 58.67 |
| 14 | 466 | 230 | 46 | 0 | 6 | 1400 | 9100 | 61.33 |
| 15 | 488 | 240 | 48 | 0 | 6 | 1500 | 10500 | 64 |
| 16 | 510 | 250 | 50 | 0 | 6 | 1600 | 12000 | 66.67 |
| 17 | 532 | 260 | 52 | 0 | 6 | 1700 | 13600 | 69.33 |
| 18 | 554 | 270 | 54 | 0 | 6 | 1800 | 15300 | 72 |
| 19 | 576 | 280 | 56 | 0 | 6.05 | 1900 | 17100 | 74.67 |
| 20 | 598 | 290 | 58 | 0 | 6.1 | 2000 | 19000 | 77.33 |
| 21 | 620 | 300 | 60 | 0 | 6.15 | 2100 | 21000 | 80 |
| 22 | 642 | 310 | 62 | 0 | 6.2 | 2200 | 23100 | 82.67 |
| 23 | 664 | 320 | 64 | 0 | 6.25 | 2300 | 25300 | 85.33 |
| 24 | 686 | 330 | 66 | 0 | 6.3 | 2400 | 27600 | 88 |
| 25 | 708 | 340 | 68 | 0 | 6.35 | 2500 | 30000 | 90.67 |
| 26 | 730 | 350 | 70 | 0 | 6.4 | 2600 | 32500 | 93.33 |
| 27 | 752 | 360 | 72 | 0 | 6.45 | 2700 | 35100 | 96 |
| 28 | 774 | 370 | 74 | 0 | 6.5 | 2800 | 37800 | 98.67 |
| 29 | 796 | 380 | 76 | 0 | 6.55 | 2900 | 40600 | 101.33 |
| 30 | 818 | 390 | 78 | 0 | 6.6 | 0 | 43500 | 104 |

## Ranger (`ranger`)

**Source:** `scripts/balance/ranger_stats.gd`

Base L1: HP 160+18/lvl, mana 100+10, dmg 22+3, CD 0.9, rng 8.0, MS 5.8.

| Lv | HP | Mana | AD | Armor | MS | XP→next | Cum XP to reach | DPS [CALC] |
|---:|---:|-----:|---:|------:|---:|--------:|----------------:|-----------:|
| 1 | 160 | 100 | 22 | 0 | 5.8 | 100 | 0 | 24.44 |
| 2 | 178 | 110 | 25 | 0 | 5.8 | 200 | 100 | 27.78 |
| 3 | 196 | 120 | 28 | 0 | 5.8 | 300 | 300 | 31.11 |
| 4 | 214 | 130 | 31 | 0 | 5.8 | 400 | 600 | 34.44 |
| 5 | 232 | 140 | 34 | 0 | 5.8 | 500 | 1000 | 37.78 |
| 6 | 250 | 150 | 37 | 0 | 5.8 | 600 | 1500 | 41.11 |
| 7 | 268 | 160 | 40 | 0 | 5.8 | 700 | 2100 | 44.44 |
| 8 | 286 | 170 | 43 | 0 | 5.8 | 800 | 2800 | 47.78 |
| 9 | 304 | 180 | 46 | 0 | 5.8 | 900 | 3600 | 51.11 |
| 10 | 322 | 190 | 49 | 0 | 5.8 | 1000 | 4500 | 54.44 |
| 11 | 340 | 200 | 52 | 0 | 5.8 | 1100 | 5500 | 57.78 |
| 12 | 358 | 210 | 55 | 0 | 5.8 | 1200 | 6600 | 61.11 |
| 13 | 376 | 220 | 58 | 0 | 5.8 | 1300 | 7800 | 64.44 |
| 14 | 394 | 230 | 61 | 0 | 5.8 | 1400 | 9100 | 67.78 |
| 15 | 412 | 240 | 64 | 0 | 5.8 | 1500 | 10500 | 71.11 |
| 16 | 430 | 250 | 67 | 0 | 5.8 | 1600 | 12000 | 74.44 |
| 17 | 448 | 260 | 70 | 0 | 5.8 | 1700 | 13600 | 77.78 |
| 18 | 466 | 270 | 73 | 0 | 5.8 | 1800 | 15300 | 81.11 |
| 19 | 484 | 280 | 76 | 0 | 5.85 | 1900 | 17100 | 84.44 |
| 20 | 502 | 290 | 79 | 0 | 5.9 | 2000 | 19000 | 87.78 |
| 21 | 520 | 300 | 82 | 0 | 5.95 | 2100 | 21000 | 91.11 |
| 22 | 538 | 310 | 85 | 0 | 6 | 2200 | 23100 | 94.44 |
| 23 | 556 | 320 | 88 | 0 | 6.05 | 2300 | 25300 | 97.78 |
| 24 | 574 | 330 | 91 | 0 | 6.1 | 2400 | 27600 | 101.11 |
| 25 | 592 | 340 | 94 | 0 | 6.15 | 2500 | 30000 | 104.44 |
| 26 | 610 | 350 | 97 | 0 | 6.2 | 2600 | 32500 | 107.78 |
| 27 | 628 | 360 | 100 | 0 | 6.25 | 2700 | 35100 | 111.11 |
| 28 | 646 | 370 | 103 | 0 | 6.3 | 2800 | 37800 | 114.44 |
| 29 | 664 | 380 | 106 | 0 | 6.35 | 2900 | 40600 | 117.78 |
| 30 | 682 | 390 | 109 | 0 | 6.4 | 0 | 43500 | 121.11 |

# 6. Hero passives and abilities (all ranks)

### Rank multipliers (`HeroAbilityStats`)

| Curve | Values |
|-------|--------|
| BASIC damage | [1.0, 1.2, 1.4, 1.6, 1.8] |
| BASIC splash | [1.0, 1.1, 1.2, 1.3, 1.4] |
| BASIC cooldown | [1.0, 0.95, 0.9, 0.85, 0.8] |
| BASIC mana | [1.0, 1.1, 1.2, 1.3, 1.4] |
| BASIC effect | [1.0, 1.2, 1.4, 1.6, 1.8] |
| BASIC range | [1.0, 1.05, 1.1, 1.15, 1.2] |
| ULT damage/effect | [1.0, 1.2, 1.4] / [1.0, 1.2, 1.4] |
| ULT cooldown | [1.0, 0.9, 0.8] |
| ULT mana | [1.0, 1.2, 1.4] |

Scaling: int = `max(1, round(base×mult))`; float = `base×mult`.
Ranger R duration uses explicit values (not ult effect curve).
Assassin R range uses BASIC_RANGE_MULT even for ultimate.

## Paladin

### Passive — Holy Recovery

- **ooc_s:** 5.0
- **regen_pct:** 0.02
- **src:** scripts/balance/hero_passive_stats.gd

### Q — Ground Slam

Base (rank 1 before mult):
- dmg: `35`
- splash: `3.5`
- cd: `9.0`
- mana: `40`

| Rank | Dmg | Splash/R | CD | Mana |
|---:|---:|---:|---:|---:|
| 1 | 35 | 3.5 | 9 | 40 |
| 2 | 42 | 3.85 | 8.55 | 44 |
| 3 | 49 | 4.2 | 8.1 | 48 |
| 4 | 56 | 4.55 | 7.65 | 52 |
| 5 | 63 | 4.9 | 7.2 | 56 |

### W — Divine Protection

Base (rank 1 before mult):
- effect: `4.0`
- cd: `20.0`
- mana: `30`
- notes: `invulnerability duration`

| Rank | Effect | CD | Mana |
|---:|---:|---:|---:|
| 1 | 4 | 20 | 30 |
| 2 | 4.8 | 19 | 33 |
| 3 | 5.6 | 18 | 36 |
| 4 | 6.4 | 17 | 39 |
| 5 | 7.2 | 16 | 42 |

### E — Power Strike

Base (rank 1 before mult):
- dmg: `45`
- cd: `10.0`
- mana: `25`

| Rank | Dmg | CD | Mana |
|---:|---:|---:|---:|
| 1 | 45 | 10 | 25 |
| 2 | 54 | 9.5 | 28 |
| 3 | 63 | 9 | 30 |
| 4 | 72 | 8.5 | 32 |
| 5 | 81 | 8 | 35 |

### R — Execute

Base (rank 1 before mult):
- effect: `0.4`
- cd: `45.0`
- mana: `50`
- notes: `HP threshold fraction; clamp 0.75`

| Rank | Effect | CD | Mana |
|---:|---:|---:|---:|
| 1 | 0.4 | 45 | 50 |
| 2 | 0.48 | 40.5 | 60 |
| 3 | 0.56 | 36 | 70 |

## Shadow Assassin

### Passive — Assassin

- **bonus:** 8
- **ad_ratio:** 0.25
- **notes:** bonus on consecutive basics vs same target after first
- **src:** scripts/balance/shadow_assassin_stats.gd

### Q — Axe Mark

Base (rank 1 before mult):
- dmg: `28`
- bonus_dmg: `40`
- effect: `5.0`
- range: `8.0`
- proj: `16.0`
- cd: `10.0`
- mana: `35`
- mana_refund: `0.5`

| Rank | Dmg | Bonus | Effect | Range | CD | Mana |
|---:|---:|---:|---:|---:|---:|---:|
| 1 | 28 | 40 | 5 | 8 | 10 | 35 |
| 2 | 34 | 48 | 6 | 8.4 | 9.5 | 38 |
| 3 | 39 | 56 | 7 | 8.8 | 9 | 42 |
| 4 | 45 | 64 | 8 | 9.2 | 8.5 | 46 |
| 5 | 50 | 72 | 9 | 9.6 | 8 | 49 |

### W — Smoke

Base (rank 1 before mult):
- effect: `6.0`
- splash: `4.0`
- range: `7.0`
- ms_bonus: `1.5`
- reveal: `1.25`
- cd: `18.0`
- mana: `35`

| Rank | Splash/R | Effect | Range | CD | Mana |
|---:|---:|---:|---:|---:|---:|
| 1 | 4 | 6 | 7 | 18 | 35 |
| 2 | 4.4 | 7.2 | 7.35 | 17.1 | 38 |
| 3 | 4.8 | 8.4 | 7.7 | 16.2 | 42 |
| 4 | 5.2 | 9.6 | 8.05 | 15.3 | 46 |
| 5 | 5.6 | 10.8 | 8.4 | 14.4 | 49 |

### E — Slash

Base (rank 1 before mult):
- dmg: `38`
- splash: `2.8`
- cd: `8.0`
- mana: `30`

| Rank | Dmg | Splash/R | CD | Mana |
|---:|---:|---:|---:|---:|
| 1 | 38 | 2.8 | 8 | 30 |
| 2 | 46 | 3.08 | 7.6 | 33 |
| 3 | 53 | 3.36 | 7.2 | 36 |
| 4 | 61 | 3.64 | 6.8 | 39 |
| 5 | 68 | 3.92 | 6.4 | 42 |

### R — Dash

Base (rank 1 before mult):
- dmg: `55`
- range: `7.0`
- cd: `20.0`
- mana: `40`
- arrival: `1.15`

| Rank | Dmg | Range | CD | Mana |
|---:|---:|---:|---:|---:|
| 1 | 55 | 7 | 20 | 40 |
| 2 | 66 | 7.35 | 18 | 48 |
| 3 | 77 | 7.7 | 16 | 56 |

## Ranger

### Passive — Hunter's Precision

- **every_nth:** 3
- **max_hp_ratio:** 0.1
- **exclude_buildings:** True
- **cap:** NOT FOUND
- **src:** scripts/balance/ranger_stats.gd

### Q — Combat Roll

Base (rank 1 before mult):
- range: `5.0`
- cd: `10.0`
- mana: `25`
- ms_mult: `2.8`
- max_dur: `0.55`

| Rank | Range | CD | Mana |
|---:|---:|---:|---:|
| 1 | 5 | 10 | 25 |
| 2 | 5.25 | 9.5 | 28 |
| 3 | 5.5 | 9 | 30 |
| 4 | 5.75 | 8.5 | 32 |
| 5 | 6 | 8 | 35 |

### W — Bear Trap

Base (rank 1 before mult):
- charges: `3`
- recharge: `14.0`
- dmg: `18`
- effect: `2.0`
- lifetime: `45.0`
- trigger_r: `0.85`
- mana: `20`
- range: `6.0`
- cd: `1.0`

| Rank | Dmg | Effect | Range | CD | Mana |
|---:|---:|---:|---:|---:|---:|
| 1 | 18 | 2 | 6 | 1 | 20 |
| 2 | 22 | 2.4 | 6.3 | 0.95 | 22 |
| 3 | 25 | 2.8 | 6.6 | 0.9 | 24 |
| 4 | 29 | 3.2 | 6.9 | 0.85 | 26 |
| 5 | 32 | 3.6 | 7.2 | 0.8 | 28 |

### E — Crossbow Bolt

Base (rank 1 before mult):
- dmg: `48`
- range: `12.0`
- cd: `12.0`
- mana: `40`
- proj: `22.0`
- hit_r: `0.55`
- pierce_mult: `0.7`
- max_pierce: `6`

| Rank | Dmg | Range | CD | Mana |
|---:|---:|---:|---:|---:|
| 1 | 48 | 12 | 12 | 40 |
| 2 | 58 | 12.6 | 11.4 | 44 |
| 3 | 67 | 13.2 | 10.8 | 48 |
| 4 | 77 | 13.8 | 10.2 | 52 |
| 5 | 86 | 14.4 | 9.6 | 56 |

### R — Camouflage

Base (rank 1 before mult):
- durations: `(10.0, 14.0, 18.0)`
- hunt: `(0.1, 0.15, 0.2)`
- hunt_radius: `16.0`
- align: `0.2`
- retarget: `0.35`
- min_ms: `0.35`
- cd: `40.0`
- mana: `50`
- roll_extend: `3.0`

| Rank | Effect | Hunt MS | CD | Mana |
|---:|---:|---:|---:|---:|
| 1 | 10 | 0.1 | 40 | 50 |
| 2 | 14 | 0.15 | 36 | 60 |
| 3 | 18 | 0.2 | 32 | 70 |

# 7. Combat formulas

**Sources:** `scripts/systems/damage_service.gd`, `scripts/balance/damage_armor_matrix.gd`, unit `_compute_incoming_damage` hooks

| Topic | Runtime rule |
|-------|--------------|
| Pipeline | `DamageService.apply` |
| Armor type matrix | all multipliers **1.0** (identity) |
| Armored units | `maxi(1, int(amount) - armor)` via `compute_armored_damage` |
| Buildings | `maxi(0, int(amount))` |
| True damage | bypasses armor |
| Archer incoming | `_compute_incoming_damage` → `int(amount)` (armor bypass) |
| Hero armor type | HERO |
| Critical / lifesteal / spell vamp | hooks present; live defaults identity / unused unless options set |
| Splash | cannon radius 3.5, min ratio 0.5 |
| Friendly fire | NOT FOUND as global toggle documented here |
| CDR / MCR caps (heroes) | 0.4 / 0.4 |

# 8. Upgrades

**Source:** `scripts/balance/upgrade_stats.gd` / `UpgradeManager`

## Blacksmith (max 5)

| Next level index | Gold | Wood | Time |
|-----------------:|-----:|-----:|-----:|
| 0 → 1 | 100 | 100 | 5.0s |
| 1 → 2 | 150 | 150 | 5.0s |
| 2 → 3 | 225 | 225 | 5.0s |
| 3 → 4 | 325 | 325 | 5.0s |
| 4 → 5 | 450 | 450 | 5.0s |

| Upgrade ID | Per-level effect | Affects |
|------------|------------------|---------|
| swordsman_attack | +2 damage | Swordsman |
| swordsman_armor | armor = level | Swordsman |
| archer_attack | +2 damage | Archer |
| archer_attack_speed | −5% cooldown multiplier / level | Archer |
| archer_range | +8 range / level | Archer |

- [CALC] Archer range at BS5 = 8 + 5×8 = 48.0

## Stable cavalry

Cost formula: gold = 150 + level×100; wood = 75 + level×50; time 5.0s.
Effects: +3 damage / +1 armor per level (attack/defense lines).

| Level purchasing | Gold | Wood |
|-----------------:|-----:|-----:|
| from 0 | 150 | 75 |
| from 1 | 250 | 125 |
| from 2 | 350 | 175 |
| from 3 | 450 | 225 |
| from 4 | 550 | 275 |

## Academy (max level 1 each)

| ID | Gold | Wood | Time | Effect |
|----|-----:|-----:|-----:|--------|
| `faster_gathering` | 1000 | 700 | 60.0s | gather speed ×1.25 |
| `faster_unit_training` | 1200 | 900 | 75.0s | train speed ×1.2 |
| `improved_tools` | 900 | 700 | 60.0s | construction speed ×1.2 |
| `engineering` | 1500 | 1200 | 90.0s | building max HP ×1.2 |
| `ballistics` | 1800 | 1200 | 90.0s | tower/siege damage ×1.2 |

Player and AI share UpgradeStats numbers (parity).

# 9. Creeps and camps (7)

**Sources:** `scenes/world/neutral_creep_camps.tscn`, `scripts/systems/hero_xp_rewards.gd`, `scripts/balance/economy_stats.gd`, `scripts/balance/unit_stats.gd`

Shared creep: HP 80, MS 3.5. Respawn 180.0s.
XP/gold tiers by creep `attack_damage`: ≤8 → 25/5; ≤12 → 50/10; else → 100/20.

| Camp | Type | Creeps | Dmg | CD | DPS/creep [CALC] | XP/creep | Gold/creep | Camp XP [CALC] | Camp gold [CALC] | Camp HP [CALC] |
|------|------|-------:|----:|---:|-----------------:|---------:|-----------:|---------------:|-----------------:|---------------:|
| `StrongCampExpansionUpperRight` | strong | 5 | 16 | 0.95 | 16.84 | 100 | 20 | 500 | 100 | 400 |
| `StrongCampExpansionLowerLeft` | strong | 5 | 16 | 0.95 | 16.84 | 100 | 20 | 500 | 100 | 400 |
| `StrongCampExpansionUpperMiddle` | strong | 5 | 16 | 0.95 | 16.84 | 100 | 20 | 500 | 100 | 400 |
| `StrongCampExpansionLowerMiddle` | strong | 5 | 16 | 0.95 | 16.84 | 100 | 20 | 500 | 100 | 400 |
| `MediumCampNorthCenter` | medium | 6 | 11 | 1.1 | 10 | 50 | 10 | 300 | 60 | 480 |
| `MediumCampSouthCenter` | medium | 6 | 11 | 1.1 | 10 | 50 | 10 | 300 | 60 | 480 |
| `MediumCampCentralCrossroads` | medium | 6 | 11 | 1.1 | 10 | 50 | 10 | 300 | 60 | 480 |

- [CALC] strong camp XP/gold = 500 / 100
- [CALC] medium camp XP/gold = 300 / 60
- [CALC] 1 strong camp XP 500 → hero levels: Paladin needs 100 to L2, 200 more to L3 (cum 300); one strong = 500 XP
- [CALC] 2 strong camps XP 1000; 3 camps mix depends on types
- Drops/runes: NOT FOUND

# 10. Shop and items (9)

**Source:** `scripts/balance/item_stats.gd` — sell ratio 0.5

Starter shop order: Long Sword, Ruby Crystal, Boots, Wizard Orb only.

| ID | Name | Cost | Sell [CALC] | Stats | Starter |
|----|------|-----:|------------:|-------|:-------:|
| `long_sword` | Long Sword | 350 | 175 | +10 AD | yes |
| `ruby_crystal` | Ruby Crystal | 400 | 200 | +100 HP, heal 100 | yes |
| `boots` | Boots | 300 | 150 | +10.0 MS | yes |
| `wizard_orb` | Wizard Orb | 450 | 225 | +75 mana, restore 75 mana | yes |
| `mage_ring` | Mage Ring | 400 | 200 | +20 AP | no |
| `mana_crystal` | Mana Crystal | 450 | 225 | +100 mana, +0.1 MCR | no |
| `sorcerer_staff` | Sorcerer Staff | 550 | 275 | +40 AP, +0.1 CDR | no |
| `arcane_boots` | Arcane Boots | 400 | 200 | +10.0 MS, +0.1 CDR | no |
| `archmage_orb` | Archmage Orb | 700 | 350 | +80 AP, +0.15 CDR | no |

Recipes/components: NOT FOUND (flat catalog items).

### [CALC] DPS gain from +10 AD (one Long Sword) at sample levels

| Hero | L1 DPS Δ | L6 DPS Δ | L11 DPS Δ | L16 DPS Δ |
|------|---------:|---------:|----------:|----------:|
| Paladin | 11.76 | 11.76 | 11.76 | 11.76 |
| Shadow Assassin | 13.33 | 13.33 | 13.33 | 13.33 |
| Ranger | 11.11 | 11.11 | 11.11 | 11.11 |

Flag: 5 non-starter items exist in catalog but are outside starter shop order.

# 11. Full inventory scaling tests

Assumptions: six inventory slots; stats stack additively; CDR/MCR clamped to 0.4; no attack-speed items in catalog.

## Paladin (level 1 baseline + items)

| Build | HP | AD | DPS [CALC] | MS | Armor | AP | CDR | MCR | Notes |
|-------|---:|---:|-----------:|---:|------:|---:|----:|----:|-------|
| six highest AD | 200 | 78 | 91.76 | 5.5 | 0 | 0 | 0 | 0 | — |
| six highest HP | 800 | 18 | 21.18 | 5.5 | 0 | 0 | 0 | 0 | — |
| six highest attack-speed | — | — | — | — | — | — | — | — | NOT FOUND — no AS items in catalog |
| balanced mixed | 300 | 38 | 44.71 | 15.5 | 0 | 80 | 0.15 | 0 | MS extreme vs Light Cavalry 9.0 |
| six highest AP | 200 | 18 | 21.18 | 5.5 | 0 | 480 | 0.4 | 0 | — |
| six Boots (MS stress) | 200 | 18 | 21.18 | 65.5 | 0 | 0 | 0 | 0 | Boots +10 MS each |

## Shadow Assassin (level 1 baseline + items)

| Build | HP | AD | DPS [CALC] | MS | Armor | AP | CDR | MCR | Notes |
|-------|---:|---:|-----------:|---:|------:|---:|----:|----:|-------|
| six highest AD | 180 | 80 | 106.67 | 6 | 0 | 0 | 0 | 0 | — |
| six highest HP | 780 | 20 | 26.67 | 6 | 0 | 0 | 0 | 0 | — |
| six highest attack-speed | — | — | — | — | — | — | — | — | NOT FOUND — no AS items in catalog |
| balanced mixed | 280 | 40 | 53.33 | 16 | 0 | 80 | 0.15 | 0 | MS extreme vs Light Cavalry 9.0 |
| six highest AP | 180 | 20 | 26.67 | 6 | 0 | 480 | 0.4 | 0 | — |
| six Boots (MS stress) | 180 | 20 | 26.67 | 66 | 0 | 0 | 0 | 0 | Boots +10 MS each |

## Ranger (level 1 baseline + items)

| Build | HP | AD | DPS [CALC] | MS | Armor | AP | CDR | MCR | Notes |
|-------|---:|---:|-----------:|---:|------:|---:|----:|----:|-------|
| six highest AD | 160 | 82 | 91.11 | 5.8 | 0 | 0 | 0 | 0 | every 3rd hit still 10% target max HP (buildings excluded) |
| six highest HP | 760 | 22 | 24.44 | 5.8 | 0 | 0 | 0 | 0 | — |
| six highest attack-speed | — | — | — | — | — | — | — | — | NOT FOUND — no AS items in catalog |
| balanced mixed | 260 | 42 | 46.67 | 15.8 | 0 | 80 | 0.15 | 0 | MS extreme vs Light Cavalry 9.0 |
| six highest AP | 160 | 22 | 24.44 | 5.8 | 0 | 480 | 0.4 | 0 | — |
| six Boots (MS stress) | 160 | 22 | 24.44 | 65.8 | 0 | 0 | 0 | 0 | Boots +10 MS each |

# 12. AI strategy timings (V2)

**Source:** `scripts/systems/military_ai_config.gd` (implemented consts). `USE_MILITARY_AI_V2 = True`.

| Constant | Value |
|----------|------:|
| `USE_MILITARY_AI_V2` | True |
| `V2_CREEP_READY_MILITARY_UNITS` | 5 |
| `V2_ATTACK_READY_MILITARY_UNITS` | 10 |
| `V2_ATTACK_READY_MILITARY_UNITS_PREFERRED` | 12 |
| `V2_ATTACK_LETHAL_MIN_MILITARY_UNITS` | 6 |
| `V2_CREEP_TARGET_HERO_LEVEL` | 3 |
| `V2_CREEP_PREFERRED_CAMPS_BEFORE_ATTACK` | 2 |
| `V2_CREEP_GREED_INTERRUPT_SCORE` | 45.0 |
| `V2_CREEP_STRENGTH_ADVANTAGE_INTERRUPT` | 1.45 |
| `V2_CREEP_HERO_HEALTHY_RATIO` | 0.55 |
| `V2_CREEP_CHAIN_NEAR_RADIUS` | 26.0 |
| `V2_CREEP_CHAIN_MEDIUM_RADIUS` | 38.0 |
| `V2_ASSEMBLE_SLOT_TOLERANCE` | 1.25 |
| `V2_ASSEMBLE_SETTLE_TOLERANCE` | 0.75 |
| `V2_ASSEMBLE_RALLY_MIN_RADIUS` | 8.0 |
| `V2_ASSEMBLE_RALLY_MAX_RADIUS` | 15.0 |
| `V2_DEFEND_LEASH_RADIUS` | 42.0 |
| `V2_DEFEND_THREAT_CLEAR_SECONDS` | 5.0 |
| `V2_ATTACK_COMMIT_STRENGTH_RATIO` | 1.25 |
| `V2_ATTACK_RETREAT_STRENGTH_RATIO` | 0.55 |
| `V2_ATTACK_HERO_DANGER_HP_RATIO` | 0.35 |
| `V2_ATTACK_ARMY_LOSS_RATIO` | 0.4 |
| `V2_ATTACK_LETHAL_SCORE_THRESHOLD` | 70.0 |
| `V2_RETREAT_STRENGTH_RATIO` | 0.55 |
| `V2_ATTACK_REENTRY_STRENGTH_RATIO` | 1.15 |
| `V2_RETREAT_HERO_HP_RATIO` | 0.35 |
| `V2_RECOVER_MIN_SECONDS` | 4.0 |
| `V2_RECOVER_MAX_SECONDS` | 18.0 |
| `V2_RECOVER_HERO_HP_RATIO` | 0.55 |
| `V2_RECOVER_HERO_MANA_RATIO` | 0.35 |
| `V2_RECOVER_MIN_MILITARY_UNITS` | 5 |
| `V2_WATCHDOG_STALL_SECONDS` | 7.0 |
| `V2_STATE_COMMIT_SECONDS` | 3.0 |
| `V2_POST_RETREAT_ATTACK_COOLDOWN_SECONDS` | 6.0 |

### Economy / build targets (non-military stack, still active under V2)

| Constant | Value | Source |
|----------|------:|--------|
| `TARGET_WORKERS_EARLY` | 14 | `scripts/systems/enemy_build_manager.gd` |
| `TARGET_WORKERS_MID` | 22 | `scripts/systems/enemy_build_manager.gd` |
| `TARGET_WORKERS_LATE` | 30 | `scripts/systems/enemy_build_manager.gd` |
| `TARGET_WORKERS_ENDGAME` | 36 | `scripts/systems/enemy_build_manager.gd` |
| `TARGET_WORKERS_ENDGAME_HIGH` | 45 | `scripts/systems/enemy_build_manager.gd` |
| `STARTING_GOLD_WORKERS` | 4 | `scripts/systems/enemy_gather_manager.gd` |
| `EARLY_GAME_GOLD_RATIO` | 0.7 | `scripts/systems/enemy_gather_manager.gd` |
| `MID_GAME_GOLD_RATIO` | 0.6 | `scripts/systems/enemy_gather_manager.gd` |
| `LATE_GAME_GOLD_RATIO` | 0.55 | `scripts/systems/enemy_gather_manager.gd` |
| `BUILDING_PRESSURE_GOLD_RATIO` | 0.45 | `scripts/systems/enemy_gather_manager.gd` |
| `MIN_WOOD_WORKERS_WHEN_TREES_EXIST` | 1 | `scripts/systems/enemy_gather_manager.gd` |
| Tower caps early/mid/late | 2/4/6 (hard 6) | `scripts/systems/enemy_attack_path_defense.gd` |
| `SHOP_STABLE_GOLD_BUFFER` | 350 | `enemy_build_manager.gd` |
| `SHOP_PURCHASE_COOLDOWN_TICKS` | 7 | `enemy_build_manager.gd` |
| `EXPANSION_SATURATION_WORKERS` | 16 | `enemy_strategic_director.gd` |
| AI hero pool weights | Equal (Paladin / Assassin / Ranger) | `ai_hero_mastery.gd` |

| Topic | Status |
|-------|--------|
| Hero selection | **Implemented** in `ai_hero_mastery.gd` (equal weights; not in MilitaryAIConfig) |
| Shop-buying | **Implemented** buffers on `enemy_build_manager.gd` (not in MilitaryAIConfig) |
| Expansion timing | Saturation workers **16** on strategic director; no single V2 military const |

Comments in `military_ai_config.gd` describing suspended legacy owners are documentation only; values above are the live V2 thresholds.

# 13. Match pacing estimates

All rows are **[CALC]** estimates under stated assumptions. Not measured playtests.

**Assumptions:** ideal gather (no travel), opening spends on farm+barracks+altar, spearman train 5s, hero train 6s, AI creep-ready at 5 military, attack-ready 10–12, T2 research 60s after paying 800/500, T3 120s after 2000/1200.

- [CALC] opening building gold (farm+barracks+altar) = 80+150+180 = 410 (from 500 start → 90 left before units)
- [CALC] fastest hero: altar construct (~4s AI / 2–4s player) + 6s train ≈ ~10–12s after altar starts, ignoring tech/pathing
- [CALC] first 5 military: e.g. 5×spearman train serial 5×5s=25s from one barracks (parallel buildings reduce wall-clock)
- [CALC] first creep timing (AI): when military≥5 and hero healthy — earliest after first few trains
- [CALC] hero level 3: cum XP 300; one strong camp gives 500 XP → typically 1 strong + partial second or medium mix
- [CALC] first attack (AI): military 10–12, often after ≥2 camps / hero L3
- [CALC] T2 timing: afford 800g/500w + 60s channel; economy-dependent (often several minutes)
- [CALC] T3 timing: afford 2000g/1200w + 120s channel after T2
- [CALC] expansion CC cost 200g/400w + construct
- [CALC] replace 20-unit army: depends on composition; e.g. 20 spears = 1300g + 100s serial train on one barracks
- [CALC] time to max population: food cap grows +8/farm; no absolute hard pop const — NOT FOUND hard max
- [CALC] example complete inventory (LS+Ruby+Boots+Wizard+Staff+Archmage) = 2750g

# 14. Current balance problems

Data-supported observations only. **No proposed new values.**

| # | Current value | Source | Why suspicious (internal comparison) |
|--|---------------|--------|--------------------------------------|
| 1 | Archer range BS5 = 48 | `UnitStats.ARCHER_ATTACK_RANGE_PER_UPGRADE_LEVEL=8` | Far exceeds tower range 10 and cannon 14 |
| 2 | Boots +10.0 move_speed | `ItemStats.BOOTS_BONUS_MOVE_SPEED` | Paladin base MS 5.5 → 15.5 with one Boots; Light Cavalry is 9.0 |
| 3 | Archer incoming armor bypass | `archer.gd _compute_incoming_damage` | Inconsistent with armored melee intake |
| 4 | Hero armor 0 with no growth | `HeroStats / kits` | Heroes rely on HP/abilities only vs armored units |
| 5 | Damage matrix all 1.0 | `scripts/balance/damage_armor_matrix.gd` | Armor types exist but provide no differentiation |
| 6 | AI Stable HP 320 vs player 700 | `scripts/balance/building_stats.gd` | Intentional AI override creates parity asymmetry |
| 7 | Barracks archer train uses SWORDSMAN_* consts | `scripts/buildings/barracks.gd` | CONFLICT wiring risk if UnitStats.ARCHER_* diverge |
| 8 | Cavalry Archer DPS/gold low vs Light Cavalry | `scripts/balance/unit_stats.gd` | [CALC] CA 0.0420 vs LC 0.1046 |
| 9 | Five catalog items outside starter shop | `scripts/balance/item_stats.gd` | Mage Ring, Mana Crystal, Sorcerer Staff, Arcane Boots, Archmage Orb not in starter order |
| 10 | Six Long Swords stack +60 AD | `inventory 6 × Long Sword` | Linear six-slot AD stacking with no diminishing returns |
| 11 | Ranger every-3rd 10% max HP | `scripts/balance/ranger_stats.gd` | Percent max-HP with cap NOT FOUND — scales with target size; buildings excluded |
| 12 | Divine Protection full invulnerability | `Paladin W` | Duration scales with ranks up to high uptime potential |
| 13 | Cannon train 14s / 275g | `scripts/balance/unit_stats.gd` | Lowest DPS/gold among military; splash compensates situationally |
| 14 | Start food: 10 free pop | `scripts/balance/economy_stats.gd` | Cap 15 with 5 workers already using food |

# 15. Machine-readable appendix + verification report

## Unit master table

| id | hp | ms | dmg | rng | cd | armor | gold | food | train |
|----|---:|---:|----:|----:|---:|------:|-----:|-----:|------:|
| worker | 70 | 5.0 | — | — | — | 0 | 50 | 1 | 3.0 |
| spearman | 70 | 4.25 | 6 | 2.4 | 1 | 0 | 65 | 1 | 5.0 |
| swordsman | 100 | 5.0 | 10 | 2 | 1 | 0 | 100 | 1 | 4.0 |
| archer | 100 | 5.0 | 7 | 8 | 1.2 | 0 | 100 | 1 | 4.0 |
| light_cavalry | 80 | 9.0 | 8 | 2 | 0.9 | 0 | 85 | 1 | 3.5 |
| cavalry_archer | 90 | 7.5 | 6 | 7.5 | 1.1 | 0 | 130 | 1 | 5.5 |
| heavy_cavalry | 150 | 7.0 | 14 | 2.2 | 1.1 | 2 | 150 | 2 | 7.0 |
| cannon | 120 | 6.0 | 45 | 14 | 5.5 | 0 | 275 | 2 | 14.0 |

## Hero level-1 / max-level

| hero | hp1 | mana1 | ad1 | ms1 | hp30 | mana30 | ad30 | ms30 |
|------|----:|------:|----:|----:|-----:|-------:|-----:|-----:|
| paladin | 200 | 100 | 18 | 5.5 | 925 | 390 | 76 | 6.1 |
| shadow_assassin | 180 | 100 | 20 | 6.0 | 818 | 390 | 78 | 6.6 |
| ranger | 160 | 100 | 22 | 5.8 | 682 | 390 | 109 | 6.4 |

## Ability master (rank 1 bases)

| hero | slot | name | key bases |
|------|------|------|-----------|
| paladin | Q | Ground Slam | `{'dmg': 35, 'splash': 3.5, 'cd': 9.0, 'mana': 40}` |
| paladin | W | Divine Protection | `{'effect': 4.0, 'cd': 20.0, 'mana': 30}` |
| paladin | E | Power Strike | `{'dmg': 45, 'cd': 10.0, 'mana': 25}` |
| paladin | R | Execute | `{'effect': 0.4, 'cd': 45.0, 'mana': 50}` |
| shadow_assassin | Q | Axe Mark | `{'dmg': 28, 'bonus_dmg': 40, 'effect': 5.0, 'range': 8.0, 'proj': 16.0, 'cd': 10.0, 'mana': 35, 'mana_refund': 0.5}` |
| shadow_assassin | W | Smoke | `{'effect': 6.0, 'splash': 4.0, 'range': 7.0, 'ms_bonus': 1.5, 'reveal': 1.25, 'cd': 18.0, 'mana': 35}` |
| shadow_assassin | E | Slash | `{'dmg': 38, 'splash': 2.8, 'cd': 8.0, 'mana': 30}` |
| shadow_assassin | R | Dash | `{'dmg': 55, 'range': 7.0, 'cd': 20.0, 'mana': 40, 'arrival': 1.15}` |
| ranger | Q | Combat Roll | `{'range': 5.0, 'cd': 10.0, 'mana': 25, 'ms_mult': 2.8, 'max_dur': 0.55}` |
| ranger | W | Bear Trap | `{'charges': 3, 'recharge': 14.0, 'dmg': 18, 'effect': 2.0, 'lifetime': 45.0, 'trigger_r': 0.85, 'mana': 20, 'range': 6.0, 'cd': 1.0}` |
| ranger | E | Crossbow Bolt | `{'dmg': 48, 'range': 12.0, 'cd': 12.0, 'mana': 40, 'proj': 22.0, 'hit_r': 0.55, 'pierce_mult': 0.7, 'max_pierce': 6}` |
| ranger | R | Camouflage | `{'durations': (10.0, 14.0, 18.0), 'hunt': (0.1, 0.15, 0.2), 'hunt_radius': 16.0, 'align': 0.2, 'retarget': 0.35, 'min_ms': 0.35, 'cd': 40.0, 'mana': 50, 'roll_extend': 3.0}` |

## Building table

| id | gold | wood | hp | footprint |
|----|-----:|-----:|---:|-----------|
| farm | 80 | 20 | 250 | 2.0x1.4 |
| barracks | 150 | 100 | 300 | 3.5x2.5 |
| blacksmith | 100 | 150 | 700 | 2.2x1.8 |
| stable | 175 | 125 | 700 | 3.0x2.2 |
| artillery_depot | 225 | 175 | 750 | 3.2x2.4 |
| academy | 200 | 150 | 720 | 3.0x2.2 |
| shop | 80 | 120 | 600 | 2.0x1.6 |
| tower | 120 | 80 | 350 | 2.0x2.0 |
| wall_segment | 0 | 40 | 500 | 1.0x1.0 |
| hero_altar | 180 | 110 | 350 | 3.0x3.0 |
| command_center | 200 | 400 | 500 | 3.5x3.5 |

## Upgrade table

| kind | detail |
|------|--------|
| blacksmith_costs | [100, 150, 225, 325, 450] both g/w, 5.0s |
| stable | base 150/75 +100/50/lvl, +3 dmg/+1 arm |
| academy:faster_gathering | 1000/700/60.0s — gather speed ×1.25 |
| academy:faster_unit_training | 1200/900/75.0s — train speed ×1.2 |
| academy:improved_tools | 900/700/60.0s — construction speed ×1.2 |
| academy:engineering | 1500/1200/90.0s — building max HP ×1.2 |
| academy:ballistics | 1800/1200/90.0s — tower/siege damage ×1.2 |

## Creep table

| camp | type | n | dmg | cd | xp | gold |
|------|------|--:|----:|---:|---:|-----:|
| StrongCampExpansionUpperRight | strong | 5 | 16 | 0.95 | 100 | 20 |
| StrongCampExpansionLowerLeft | strong | 5 | 16 | 0.95 | 100 | 20 |
| StrongCampExpansionUpperMiddle | strong | 5 | 16 | 0.95 | 100 | 20 |
| StrongCampExpansionLowerMiddle | strong | 5 | 16 | 0.95 | 100 | 20 |
| MediumCampNorthCenter | medium | 6 | 11 | 1.1 | 50 | 10 |
| MediumCampSouthCenter | medium | 6 | 11 | 1.1 | 50 | 10 |
| MediumCampCentralCrossroads | medium | 6 | 11 | 1.1 | 50 | 10 |

## Item table

| id | gold | sell | starter |
|----|-----:|-----:|:-------:|
| long_sword | 350 | 175 | True |
| ruby_crystal | 400 | 200 | True |
| boots | 300 | 150 | True |
| wizard_orb | 450 | 225 | True |
| mage_ring | 400 | 200 | False |
| mana_crystal | 450 | 225 | False |
| sorcerer_staff | 550 | 275 | False |
| arcane_boots | 400 | 200 | False |
| archmage_orb | 700 | 350 | False |

## Economy constants

| key | value |
|-----|------:|
| START_GOLD | 500 |
| START_WOOD | 500 |
| FOOD_MAX | 15 |
| START_WORKERS | 5 |
| GATHER_WAIT | 1.0 |
| CARRY | 10 |
| GOLD_CHUNK | 5 |
| WOOD_CHUNK | 2 |
| MINE_GOLD | 20000 |
| TREE_WOOD | 5000 |
| CAMP_RESPAWN | 180.0 |

## AI thresholds

| key | value |
|-----|------:|
| USE_MILITARY_AI_V2 | True |
| V2_CREEP_READY_MILITARY_UNITS | 5 |
| V2_ATTACK_READY_MILITARY_UNITS | 10 |
| V2_ATTACK_READY_MILITARY_UNITS_PREFERRED | 12 |
| V2_ATTACK_LETHAL_MIN_MILITARY_UNITS | 6 |
| V2_CREEP_TARGET_HERO_LEVEL | 3 |
| V2_CREEP_PREFERRED_CAMPS_BEFORE_ATTACK | 2 |
| V2_CREEP_GREED_INTERRUPT_SCORE | 45.0 |
| V2_CREEP_STRENGTH_ADVANTAGE_INTERRUPT | 1.45 |
| V2_CREEP_HERO_HEALTHY_RATIO | 0.55 |
| V2_CREEP_CHAIN_NEAR_RADIUS | 26.0 |
| V2_CREEP_CHAIN_MEDIUM_RADIUS | 38.0 |
| V2_ASSEMBLE_SLOT_TOLERANCE | 1.25 |
| V2_ASSEMBLE_SETTLE_TOLERANCE | 0.75 |
| V2_ASSEMBLE_RALLY_MIN_RADIUS | 8.0 |
| V2_ASSEMBLE_RALLY_MAX_RADIUS | 15.0 |
| V2_DEFEND_LEASH_RADIUS | 42.0 |
| V2_DEFEND_THREAT_CLEAR_SECONDS | 5.0 |
| V2_ATTACK_COMMIT_STRENGTH_RATIO | 1.25 |
| V2_ATTACK_RETREAT_STRENGTH_RATIO | 0.55 |
| V2_ATTACK_HERO_DANGER_HP_RATIO | 0.35 |
| V2_ATTACK_ARMY_LOSS_RATIO | 0.4 |
| V2_ATTACK_LETHAL_SCORE_THRESHOLD | 70.0 |
| V2_RETREAT_STRENGTH_RATIO | 0.55 |
| V2_ATTACK_REENTRY_STRENGTH_RATIO | 1.15 |
| V2_RETREAT_HERO_HP_RATIO | 0.35 |
| V2_RECOVER_MIN_SECONDS | 4.0 |
| V2_RECOVER_MAX_SECONDS | 18.0 |
| V2_RECOVER_HERO_HP_RATIO | 0.55 |
| V2_RECOVER_HERO_MANA_RATIO | 0.35 |
| V2_RECOVER_MIN_MILITARY_UNITS | 5 |
| V2_WATCHDOG_STALL_SECONDS | 7.0 |
| V2_STATE_COMMIT_SECONDS | 3.0 |
| V2_POST_RETREAT_ATTACK_COOLDOWN_SECONDS | 6.0 |

## Verification report

| Check | Result |
|-------|--------|
| Heroes documented (Paladin, Shadow Assassin, Ranger) | 3 / 3 |
| Units documented | 8 / 8 |
| Buildings documented | 11 / 11 |
| Items documented | 9 / 9 |
| Camps documented | 7 / 7 |
| Upgrade lines documented | BS5 + Stable6 + Academy5 = 16 |
| Hero level tables 1–30 complete | yes (3 × 30) |
| `[CALC]` labels emitted | 206 |
| `NOT FOUND` entries | 23 |
| `CONFLICT` entries | 4 |
| Gameplay files modified | **none** (docs only) |

### Conflicts found

- CONFLICT: Stable HP player 700 vs AI 320 (`BuildingStats.STABLE_MAX_HEALTH` vs `ENEMY_STABLE_MAX_HEALTH`)
- CONFLICT: Barracks runtime train cost/time for archer uses SWORDSMAN_* consts (`barracks.gd`); UnitStats also defines ARCHER_* (same numeric values today: 100g / 4.0s)
- CONFLICT (soft): Food cost aliases in `unit_food_supply.gd` — Spearman/Archer → `SWORDSMAN_FOOD_COST`; Cavalry Archer → `LIGHT_CAVALRY_FOOD_COST` (values equal own consts today)
- CONFLICT (ownership): Legacy AI thresholds remain in suspended `enemy_*` managers while V2 owns main army (`USE_MILITARY_AI_V2 = true`)

### Missing values (NOT FOUND)

- other win conditions
- hero respawn cost/time by level (flat retrain only)
- fixed deposit travel time constant
- repair cost/rate (not implemented)
- AI resource cheat multipliers (none found)
- building flat armor / regen / sight range
- unified production queue hard limit const
- sell completed buildings
- non-hero mana
- unit acceleration / rotation / collision / vision / acquisition (not in balance tables)
- unit wood train costs (gold-only)
- hero vision range
- creep item/rune drops (empty neutral item order)
- item recipes/components
- attack-speed items
- dedicated V2 expansion-timing const (saturation workers live on strategic director)

### Counts

- Document path: `docs/BALANCE_BIBLE_V2.md`
- Units: 8
- Heroes: 3
- Buildings: 11
- Items: 9
- Camps/creep groups: 7
- Upgrade entries: 16
- CALC labels: 206
- NOT FOUND: 23
- CONFLICTS: 4

*End of Balance Bible V2.*

