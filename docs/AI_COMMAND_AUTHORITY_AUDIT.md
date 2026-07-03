# Enemy AI Command Authority Audit

**Date:** 2026-07-03  
**Scope:** Enemy/AI-controlled units only (player input systems excluded)  
**Purpose:** Map which scripts issue orders to AI units so command conflicts can be fixed safely.  
**Status:** Read-only audit — no gameplay code was changed.

---

## Executive Summary

Enemy AI is a **layered tick-based system** with no single army state machine or command queue. Strategic managers (`EnemyWaveManager`, `EnemyCreepManager`, `EnemyBuildManager`, `EnemyGatherManager`) issue orders on independent timers. Combat orders flow through the shared static helper `EnemyArmyCommand`, which calls unit APIs (`command_attack_move`, `set_movement_target`). Unit scripts add **local micro-AI** (auto-attack, retaliation, chase) that can override strategic intent once units are idle.

The highest-risk design issue is **uncoordinated multi-writer control** of `enemy_combat_units`: wave assault, creep clearing, hero micro, spawn rally, and idle auto-attack all compete for the same soldiers, archers, and hero.

---

## 1. AI Scripts and Managers Found

### Strategic managers (scene: `scenes/match/match_systems.tscn`)

| Script | Path | Tick interval |
|--------|------|---------------|
| **EnemyBuildManager** | `scripts/systems/enemy_build_manager.gd` | 4 s |
| **EnemyGatherManager** | `scripts/systems/enemy_gather_manager.gd` | 4 s |
| **EnemyWaveManager** | `scripts/systems/enemy_wave_manager.gd` | Wave 35 s; hero micro 1 s; regroup enforce 5 s |
| **EnemyCreepManager** | `scripts/systems/enemy_creep_manager.gd` | 8 s |

### Shared command infrastructure

| Script | Path | Role |
|--------|------|------|
| **EnemyArmyCommand** | `scripts/systems/enemy_army_command.gd` | Static order bus for combat units (`enemy_combat_units` group) |
| **GroupMoveSpacing** | `scripts/systems/group_move_spacing.gd` | Formation target positions (no direct unit orders) |
| **EnemyBuildPlacement** | `scripts/systems/enemy_build_placement.gd` | Building placement geometry only (no unit orders) |

### Building scripts that train or route units

| Script | Path |
|--------|------|
| **CommandCenter** | `scripts/buildings/command_center.gd` |
| **Barracks** | `scripts/buildings/barracks.gd` |
| **HeroAltar** | `scripts/buildings/hero_altar.gd` |
| **Blacksmith** | `scripts/buildings/blacksmith.gd` |
| **Shop** | `scripts/buildings/shop.gd` |
| **Tower** | `scripts/buildings/tower.gd` |

### Unit executors (receive orders + local micro-AI)

| Script | Path |
|--------|------|
| **Worker** | `scripts/units/worker.gd` |
| **Swordsman** | `scripts/units/swordsman.gd` |
| **Archer** | `scripts/units/archer.gd` |
| **Hero** | `scripts/units/hero.gd` |
| **Unit** (base) | `scripts/base/unit.gd` |

### Support systems (no direct unit orders)

| Script | Path | Role |
|--------|------|------|
| **EnemyResourceManager** | `autoloads/enemy_resource_manager.gd` | Economy gates for train/build spend |
| **WorkerGathering** | `scripts/systems/worker_gathering.gd` | Dropoff lookup, safe sources, deposit |
| **CreepCampSafety** | `scripts/systems/creep_camp_safety.gd` | Camp guard checks for gather/creep logic |
| **CombatTargetValidation** | `scripts/systems/combat_target_validation.gd` | Faction/target checks for unit micro |
| **UpgradeManager** | `autoloads/upgrade_manager.gd` | Passive upgrade application |

### Neutral (not enemy faction, included for creep interaction context)

| Script | Path |
|--------|------|
| **NeutralCreep** | `scripts/units/neutral_creep.gd` |
| **CreepCamp** | `scripts/systems/creep_camp.gd` |

---

## 2. What Each Script Controls

### EnemyBuildManager

Macro build order: worker economy growth, structure placement, military/hero production, blacksmith research, shop purchases, and worker→construction assignment.

Key behaviors:
- Places Farm, Barracks, Blacksmith, Shop, Hero Altar, expansion Command Center
- Trains workers via Command Center; swordsmen/archers via Barracks; hero via Hero Altar
- Assigns nearest available worker to unfinished buildings (`command_build`)
- Sends hero to shop when near rally and healthy (`set_movement_target`)
- Defers military production while hero altar is training

### EnemyGatherManager

Gold/wood worker assignment, gather pool rebalancing, idle-worker recovery near Command Center.

Key behaviors:
- Rebalances all gather-pool workers every 4 s
- Issues `command_gather_gold_mine` / `command_gather_tree` with `player_ordered=false`
- Triggered on worker spawn via `EnemyBuildManager.notify_enemy_worker_spawned`

### EnemyWaveManager

Timed attack waves against the player, army regroup while waiting, enemy hero micro (retreat, abilities).

Key behaviors:
- Launches attack waves every 35 s when army is regrouped at rally
- Delays first offensive wave until hero level 2, 2 cleared camps, or 420 s elapsed
- Enforces regroup every 5 s while in creep-delay or post-wave rebuild phase
- Hero behavior every 1 s: retreat when low HP / far from army / small army; ability usage

### EnemyCreepManager

Sends regrouped army to clear neutral creep camps on the enemy side of the map.

Key behaviors:
- Every 8 s, evaluates creep army and issues attack-move to best camp
- Retreats creep army when base threatened or army under attack by player military
- Skips new orders when army is already engaging a camp

### EnemyArmyCommand

Central combat order bus. Registers units in `enemy_combat_units` on spawn.

Commands issued:
- `command_attack_move` — formation-spaced attack-move
- `command_regroup_at_rally` — all living combat units hold at rally
- `command_hold_at_rally` — spaced move to rally (non-attack-move)
- `command_retreat_hero` — hero hold at rally/army center
- `command_retreat_to` — spaced move without attack-move flag
- `command_defend_position` — alias for attack-move to position

Also provides army queries: `build_creep_army`, `is_enemy_base_threatened`, `is_enemy_army_under_attack`, rally resolution.

### Building scripts

| Building | Controls |
|----------|----------|
| **CommandCenter** | Enemy worker training queue; tags worker `enemy_workers`; notifies build manager on spawn |
| **Barracks** | Military training; on enemy spawn: `register_combat_unit` + `set_movement_target` to barracks offset. Optional `enable_enemy_auto_production` (default `false`) duplicates build manager training if enabled |
| **HeroAltar** | Hero training; on enemy spawn: `register_combat_unit` + `command_hold_at_rally` |
| **Blacksmith** | Research upgrades (invoked by EnemyBuildManager; no unit orders) |
| **Shop** | Hero item purchases (invoked by EnemyBuildManager; no move orders) |
| **Tower** | Autonomous turret: finds and fires at enemies in range (`_physics_process`) |

### Unit scripts (execution + local AI)

| Unit | Receives from managers | Local autonomous behavior |
|------|------------------------|---------------------------|
| **Worker** | `command_gather_*`, `command_build`, `set_movement_target` | Internal trip navigation; idle gather reassignment requests |
| **Swordsman** | `command_attack_move`, `set_movement_target`, `command_attack` | Auto-attack when idle; attack-move engagement; chase; **retaliate on damage** |
| **Archer** | Same as Swordsman | Same pattern (ranged) |
| **Hero** | Same as Swordsman + ability methods from wave manager | Auto-attack when idle; attack-move engagement; chase; **no damage retaliation**; `set_movement_target` cancels attack-move and abilities |

---

## 3. Unit Types Commanded by Each Script

| Script | Workers | Soldiers (melee) | Archers (ranged) | Hero | Buildings |
|--------|:-------:|:----------------:|:----------------:|:----:|:---------:|
| EnemyBuildManager | assign build, train | train (via Barracks) | train (via Barracks) | train, move to shop | place, start construction |
| EnemyGatherManager | gather gold/wood | — | — | — | — |
| EnemyWaveManager | — | attack-move, regroup | attack-move, regroup | retreat, hold, abilities, attack-move | — |
| EnemyCreepManager | — | attack-move, hold | attack-move, hold | attack-move, hold | — |
| EnemyArmyCommand | — (excluded from formation) | all combat commands | all combat commands | all combat commands | — |
| CommandCenter | train | — | — | — | self (training) |
| Barracks | — | train, spawn rally | train, spawn rally | — | self (training) |
| HeroAltar | — | — | — | train, spawn hold | self (training) |
| Blacksmith | — | — | — | — | research |
| Shop | — | — | — | purchase items | self |
| Tower | — | — | — | — | auto-attack |
| Worker (local) | self-nav for tasks | — | — | — | — |
| Swordsman/Archer/Hero (local) | — | self micro | self micro | self micro | — |

---

## 4. Scripts That Issue Movement Orders

| Script | Mechanism | Units affected |
|--------|-----------|----------------|
| **EnemyArmyCommand** | `command_attack_move`, `command_hold_at_rally`, `command_retreat_to`, `command_retreat_hero` | Soldiers, archers, hero |
| **EnemyWaveManager** | Via EnemyArmyCommand (regroup, hold, attack-move) | Soldiers, archers, hero |
| **EnemyCreepManager** | Via EnemyArmyCommand (attack-move, hold) | Soldiers, archers, hero |
| **EnemyBuildManager** | `hero.set_movement_target` (shop routing) | Hero |
| **Barracks** | `unit.set_movement_target` on spawn | Soldiers, archers |
| **HeroAltar** | `command_hold_at_rally` on spawn | Hero |
| **EnemyGatherManager** | Indirect via `command_gather_*` (worker trip navigation) | Workers |
| **Worker** | Internal `set_movement_target` for gather/build/dropoff trips | Workers |
| **Swordsman / Archer / Hero** | Chase during combat; `set_movement_target` cancels attack-move | Self |

---

## 5. Scripts That Issue Attack Orders

| Script | Mechanism | Units affected |
|--------|-----------|----------------|
| **EnemyArmyCommand** | `command_attack_move`, `command_defend_position` | Soldiers, archers, hero |
| **EnemyWaveManager** | `command_attack_move` to player base/units | Wave army |
| **EnemyCreepManager** | `command_attack_move` to creep camps | Creep army |
| **Tower** | `_fire_projectile` at closest enemy in range | Building (not a unit) |
| **Swordsman / Archer** | `command_attack` via auto-attack, retaliation, attack-move engagement | Self |
| **Hero** | `command_attack` via auto-attack, attack-move engagement | Self |
| **EnemyWaveManager** | Hero abilities (`try_divine_protection`, `try_execute`, etc.) | Hero |

---

## 6. Scripts That Issue Gather / Build Orders

### Gather

| Script | API | Units |
|--------|-----|-------|
| **EnemyGatherManager** | `worker.command_gather_gold_mine`, `worker.command_gather_tree` | Workers |
| **Worker** (local) | `_try_reassign_gather_source` when idle | Workers |

### Build

| Script | API | Units |
|--------|-----|-------|
| **EnemyBuildManager** | `worker.command_build(building)` via `_assign_nearest_builder` | Workers |
| **EnemyBuildManager** | Places buildings, sets `STATE_UNDER_CONSTRUCTION` | Buildings (placement) |
| **Worker** (local) | Internal build trip state machine | Workers |

### Train

| Script | API | Produces |
|--------|-----|----------|
| **EnemyBuildManager** | `command_center.try_train_enemy_worker`, `barracks.try_train_enemy_*`, `hero_altar.try_train_enemy_hero` | Workers, soldiers, archers, hero |
| **CommandCenter** | `try_train_enemy_worker` | Workers |
| **Barracks** | `try_train_enemy_swordsman/archer` (+ optional auto-production) | Soldiers, archers |
| **HeroAltar** | `try_train_enemy_hero` | Hero |

---

## 7. Potential Conflicts

### 7.1 Creeping vs attacking (CRITICAL)

**Writers:** `EnemyCreepManager` (8 s tick) and `EnemyWaveManager` (35 s wave timer).

Both call `EnemyArmyCommand.command_attack_move` on overlapping unit sets from `enemy_combat_units`. Creep manager targets neutral camps; wave manager targets the player. There is **no mutex or priority** — whichever manager fires last wins, so armies can ping-pong between camps and the player base.

Partial mitigation exists: wave manager delays offensive waves while uncleared camps remain (`_should_delay_offensive_wave`, lines 231–246) and holds army during creep phase (`_hold_army_for_creep_phase`). Creep manager skips when army is on offensive push toward player (`_is_army_on_offensive_push`). These are **coordination hints**, not exclusive command ownership.

### 7.2 Regrouping vs attacking (CRITICAL)

**Writers:** `EnemyWaveManager` regroup enforcement (every 5 s while waiting/rebuilding) vs creep/wave `command_attack_move`.

While wave manager calls `command_regroup_at_rally` (lines 201, 324, 339), creep manager may simultaneously `command_attack_move` the same units (line 81). During post-wave rebuild, regroup and creep push can alternate every few seconds.

### 7.3 Hold/regroup vs local auto-attack (HIGH)

**Writers:** `EnemyArmyCommand.command_hold_at_rally` uses `set_movement_target`, which cancels attack-move. Once units arrive and `has_move_target == false`, `_try_auto_attack()` runs every physics frame in Swordsman/Archer/Hero.

Units at rally **will engage nearby player units**, breaking hold/regroup intent. This undermines both wave-manager creep-phase holds and creep-manager retreats.

### 7.4 Hero following army vs hero creeping / shop / wave (HIGH)

**Writers:**
- `EnemyWaveManager._update_hero_army_behavior` (1 s): retreat/hold based on HP, army size, distance
- `EnemyCreepManager`: includes hero in creep army `command_attack_move`
- `EnemyWaveManager`: includes hero in wave `command_attack_move`
- `EnemyBuildManager._command_hero_to_shop`: `set_movement_target` (cancels attack-move and abilities on hero)

The hero receives independent orders from up to three managers with no arbitration.

### 7.5 Defense response vs attack wave (MEDIUM)

**Writers:** `EnemyCreepManager` retreats when `is_enemy_base_threatened` or `is_enemy_army_under_attack` (lines 39–40, 54–55). `EnemyWaveManager` does not check base threat before launching waves.

A wave can launch toward the player while creep manager is trying to pull the army back to rally. Creep retreat uses `command_hold_at_rally` on creep army subset only; wave attack-move may have already been issued on a broader set.

### 7.6 Workers gathering vs building (MEDIUM)

**Writers:** `EnemyGatherManager` (reassign every 4 s) vs `EnemyBuildManager` (assign builders every 4 s).

Build manager can interrupt gatherers for `STATE_UNDER_CONSTRUCTION` buildings via `allow_gather_interrupt=true` (`_assign_nearest_builder`, lines 807–817). Active gather trips are cancelled when `command_build` is issued. Both tick on the same 4 s interval, so orders can race.

### 7.7 Spawn rally vs army managers (MEDIUM)

New soldiers/archers get `set_movement_target` to barracks offset on spawn (Barracks line 147). New hero gets `command_hold_at_rally` (HeroAltar lines 257–260). Wave/creep managers re-command them on their own timers before they reach rally.

### 7.8 Duplicate military training (LOW, latent)

`Barracks.enable_enemy_auto_production` defaults to `false` but, if enabled in a scene, duplicates `EnemyBuildManager._try_sustain_military_production` on an independent 8 s tick.

### 7.9 Unit retaliation vs strategic retreat (MEDIUM)

Swordsman and Archer `take_damage` calls `command_attack(attacker)` for enemy faction units (Swordsman lines 307–312). During creep retreat or regroup, units taking chip damage from player scouts will break formation to chase.

---

## 8. Order Authority Diagram

```
                    ┌─────────────────────────────────────────┐
                    │           enemy_combat_units            │
                    │   (Swordsman, Archer, Hero)             │
                    └─────────────────────────────────────────┘
                           ▲           ▲           ▲
                           │           │           │
              ┌────────────┘           │           └────────────┐
              │                        │                        │
    EnemyWaveManager          EnemyCreepManager          EnemyBuildManager
    (wave, regroup,           (creep attack-move,          (hero → shop)
     hero micro)               retreat/hold)
              │                        │
              └──────────┬─────────────┘
                         │
                 EnemyArmyCommand
                 (attack-move, hold, regroup, retreat)
                         │
              ┌──────────┴──────────┐
              │                     │
         Barracks/HeroAltar    Unit local micro
         (spawn rally)         (auto-attack, retaliate, chase)


                    ┌─────────────────────────────────────────┐
                    │            enemy_workers                │
                    └─────────────────────────────────────────┘
                           ▲                    ▲
                           │                    │
                 EnemyGatherManager      EnemyBuildManager
                 (gather gold/wood)       (command_build)
                           │
                      Worker local
                      (trip navigation, idle rebalance)
```

---

## 9. Recommended First Fix

### Fix: Establish exclusive army-mode ownership between `EnemyWaveManager` and `EnemyCreepManager`

**Why this is the safest first conflict to fix:**

1. **Highest visible impact.** Creep vs wave ping-pong is the most obvious broken behavior — the army alternates between neutral camps and the player base because two managers write `command_attack_move` on the same `enemy_combat_units` with no shared state.

2. **Contained scope.** Both managers already share `EnemyArmyCommand` and partially coordinate (wave delay for uncleared camps, creep skip during offensive push). A single army-mode enum or coordinator node between these two files does not require refactoring worker economy or unit micro.

3. **Low regression risk for economy.** Worker gather/build conflicts are real but more predictable (4 s ticks, explicit interrupt flag). Combat multi-writer issues cause erratic army behavior that is harder to debug.

4. **Does not require unit-script changes initially.** Fixing authority at the manager layer (e.g. `ArmyMode.CREEPING | ATTACKING | REGROUPING | IDLE`) avoids touching Swordsman/Archer/Hero micro until hold-vs-auto-attack is addressed as a second phase.

**Suggested approach (for a future refactor, not implemented here):**

- Add a small `EnemyArmyCoordinator` (or state on `EnemyArmyCommand`) that records the current army mode and last issuer.
- `EnemyCreepManager` may only `command_attack_move` when mode is `CREEPING` or `IDLE`.
- `EnemyWaveManager` may only launch waves when mode is `ATTACKING` or transitions from `REGROUPING`.
- Regroup/hold from either manager sets mode to `REGROUPING` and blocks the other from attack-move until mode clears.

**Defer to phase 2:** Hold/regroup vs local `_try_auto_attack()` — fixing manager authority alone will not stop units at rally from engaging nearby player units; that requires a unit-level "strategic hold" flag.

---

## Appendix: Key Code References

| Behavior | File | Lines |
|----------|------|-------|
| Wave attack-move | `enemy_wave_manager.gd` | 224 |
| Wave regroup | `enemy_wave_manager.gd` | 201, 324, 339 |
| Creep attack-move | `enemy_creep_manager.gd` | 81 |
| Creep retreat | `enemy_creep_manager.gd` | 39–40, 54–55, 90 |
| Army command bus | `enemy_army_command.gd` | 156–161, 355–378 |
| Gather rebalance | `enemy_gather_manager.gd` | 94+ |
| Build worker assign | `enemy_build_manager.gd` | 807–817 |
| Hero shop move | `enemy_build_manager.gd` | 352–355 |
| Spawn rally (barracks) | `barracks.gd` | 147 |
| Spawn hold (hero) | `hero_altar.gd` | 257–260 |
| Auto-attack (swordsman) | `swordsman.gd` | 121–122, 144–147 |
| Retaliation (swordsman) | `swordsman.gd` | 307–312 |
| Manager scene wiring | `match_systems.tscn` | 35–51 |
