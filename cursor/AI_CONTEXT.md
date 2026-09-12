# Endless Battle — AI Context

Read this first. Then `docs/CURRENT_STATE.md`, `docs/GAME_CONSTITUTION.md`, `docs/ENGINE_RULES.md`, `docs/MOVEMENT_CONTRACT.md`, and `docs/WORKFLOW.md`.

**Source code is the source of truth.** If this file disagrees with scripts, scenes, or `project.godot`, the source wins and this file is stale.

Do not treat `docs/Architecture.md`, `docs/Endless_Battle_Technical_Audit.md`, `AUDIT_PROGRESS.md`, or the Balance Bibles as current architecture.

---

## ENDLESS BATTLE

### Project Summary

Endless Battle is a **classic 3D RTS** inspired by Warcraft III, Age of Empires, Stronghold, and Cossacks. It is **its own game**, not a Warcraft clone and not a MOBA.

**Engine:** Godot 4.7, GDScript, Jolt Physics.  
**Current target:** single-player **1v1 vs AI**.

**Canonical scenes:**

- App entry / F5: `scenes/ui/main_menu.tscn` (`project.godot` `run/main_scene`)
- Match: `scenes/main.tscn` only via `MatchSession.start_match()` / rematch
- Debug harnesses: `scenes/debug/` — not release entry points

**Main loop (implemented):**

main menu → economy → build → Hero → army → creep → tech → expansion → fight → destroy enemy Command Center → victory/defeat → restart/menu

**Starting match (both sides):** 5 Workers, 500 gold, 500 wood, food used 5 / cap 15.

**Win / loss:** destroy the enemy main Command Center → Victory. Player main Command Center destroyed → Defeat. `MatchManager` then returns to the main menu with the result. Debug-only: F8 / F9 destroy those CCs.

---

## NON-NEGOTIABLE AI ARCHITECTURE

Enemy strategic AI is **`EnemyAI`** (`scripts/systems/enemy_ai.gd`).

It is a **simple ordered condition tree** on a **0.5s strategic tick**.

Each tick:

1. Read live world facts into `_w`
2. Always run **macro** (workers, food, buildings, hero train, tech, expansion, upgrades, production, light hero micro)
3. Evaluate **military IF conditions in order**
4. First true condition acts
5. Return
6. Next tick reads reality again

**CONDITIONS ARE THE STATE.** There is no mission manager, no strategic state machine, no wave director.

### Do NOT introduce

- `MilitaryDirector` / `MilitaryDirectorV2`
- `ArmyCommander` / `ArmyCommanderV2`
- behavior trees
- strategic state machines
- mission / wave / watchdog / recovery / squad-strategic managers

`EnemyBuildManager` and `EnemyGatherManager` execute placements and gather jobs. They do **not** decide strategy.

`PlayerRouteNavigation` executes **how** the enemy army marches. It is not a second strategic brain.

### Current military condition order (source)

Verified in `EnemyAI._tick_military()`:

1. **DEFEND** — player army inside base defense radius
2. **HERO MISSING** — no living hero → army goes home (`HOME_NO_HERO`)
3. **ARMY TOO SMALL** — T1: fewer than 5 Spearmen; later: fewer than 6 combat units → home
4. **HERO STUCK** — hero physically blocked → local unstuck only (not a regroup mission)
5. **EARLY CREEP** — hero below level 3 and a useful camp exists
6. **EXTRA CREEP (expansion access)** — T2+, no expansion CC, workers ≥ 18, and no expansion mine found
7. **ATTACK PLAYER** — living army and ~1.25× player power (or ≥ 6 soldiers if player army is empty)
8. **EXTRA CREEP** — any remaining useful camp
9. **HOME / WAIT**

`_army_is_together()` is **march/debug observation**, not a strategic mission. Do not reintroduce REGROUP / assembly-as-strategy.

Hero is part of the army. If the hero is missing, the army waits at home. Do not send the AI hero as an independent suicide unit.

---

## MOVEMENT ARCHITECTURE

**Active authority:** autoload `PlayerRouteNavigation` + `PlayerRtsOccupancyGrid` + `UnitSpatialHash`.

Used by player `SelectionManager`, production rally, worker travel, and enemy army march.

### How it works

- One **shared strategic grid route** per group command (one A* for the group)
- **Automatic formation slots** assigned **once** per command (line ≤5, rectangle ≤15, square 16+)
- Hero prefers a front-center slot
- Each unit follows the shared corridor to its slot (local execution)
- Buildings / walls / world blockers on the BUILDINGS layer are **hard occupancy obstacles**
- **Mobile units are not grid blockers** — soft separation via `UnitSeparation` (max 6 neighbors)
- Attack-move uses the same route bind, then `MilitaryUnit` / combat scripts engage locally
- Command generation invalidates old routes. Latest command wins
- NavigationAgent3D is **not** used for strategic travel

### Enemy march vs player group

- **Player:** shared route + slots; each unit uses its own move speed
- **Enemy:** same grid, plus cohesive **checkpoint march** (gather ~75% / 4s, then next 16m segment)

### Trees

`GatherableResource` (trees, mines) is **explicitly excluded** from the occupancy scan. Living trees still have physical collision. Strategic routes can walk through forest on the grid, then units hit tree collision. This is a current known issue.

### Do NOT

- return to NavigationAgent3D-per-unit strategic movement
- create a `FormationManager` (autoload removed; leftover `formation_*.gd` files are not the live path)
- pathfind independently for every army unit every frame
- treat formation as rigid physics
- layer corridor / follow-leader / stuck-stack / REGROUP managers

Formation is **guidance**. World/buildings are **hard**. Mobile traffic is **soft**.

Stuck recovery must keep the current command and destination. Do not randomize destinations or reshuffle the whole group.

---

## PERFORMANCE RULES

Dense unit overlap has historically caused severe FPS drops. Do not “solve” that by shrinking layout army sizes.

Rules:

- Avoid O(N²) crowd logic
- Neighbor processing is bounded (`UnitSeparation.MAX_NEIGHBORS = 6`)
- Use the spatial hash / occupancy grid, not per-frame full-group scans
- Rate-limit / cache target acquisition
- Stagger / rate-limit expensive stuck checks
- One shared strategic route, not per-unit global A* every frame
- Profile before adding architecture

**F3** (`PerfDebugOverlay` + `PerfCounters`, debug builds) currently shows:

- FPS / avg / low / frame ms, physics ms, script ms
- unit counts (total, moving, player/enemy military, workers, creeps)
- neighbor queries / neighbors processed / separation updates per sec
- repaths / strategic routes / orders / target searches per sec
- stuck checks / recoveries per sec
- query / slide / target-search / collision-pair timings
- unit / military / RTS-move / stuck / steer ms
- difficulty name

Do not document removed counters. The overlay is performance-only. Enemy reasoning is the **P-key brain panel** (debug builds; see hotkey conflict below).

---

## GAMEPLAY AUTHORITY

| Concern | Owner |
|---------|--------|
| Enemy strategy | `EnemyAI` only |
| Enemy build / gather execution | `EnemyBuildManager` / `EnemyGatherManager` |
| Player / shared strategic movement | `PlayerRouteNavigation` |
| Combat orders | `MilitaryUnit` (and forked combat scripts — see Known Issues) |
| Building placement | `BuildManager` |
| Selection / inspect | `SelectionManager` |
| Match wiring | `MatchCompositionRoot` (`MatchSystems`) |
| Match win/loss | `MatchManager` → `MatchSession` |
| Resources | `ResourceManager` / `EnemyResourceManager` |
| Tech gates | `TechTree` (CC tier + Blacksmith presence) |
| Upgrades | `UpgradeManager` (Blacksmith / Stable / Academy) |
| Control groups / F1 / idle worker | `ControlGroupManager` |
| UI | `scripts/ui/` — reads state, issues requests, never owns gameplay state |

`InputManager` only arms Attack-Move / Patrol. It must not become a second command brain.

**Known duplicated authority (problem, not design):** Heavy Cavalry, Cavalry Archer, and Cannon copy combat on `Unit` instead of `MilitaryUnit`. Light Cavalry already uses `MilitaryUnit`. Hold / Patrol on the forked units are empty `Unit` stubs.

Leftover unused code (do not revive): `autoloads/fog_of_war_manager.gd` (not autoloaded), old `formation_layout.gd` / `formation_group.gd` helpers, historical V2 director/commander names.

---

## CURRENT MAJOR KNOWN ISSUES

Only issues still true in current source. Not a bug tracker.

**ISSUE:** Dense army overlap can still spike FPS  
**IMPACT:** Late-game battles become unplayable  
**OWNER:** `UnitSeparation`, `UnitSpatialHash`, `PerfCounters` / F3

**ISSUE:** Trees / gatherables are not strategic-grid obstacles  
**IMPACT:** Armies route through forests, then stick on tree collision  
**OWNER:** `PlayerRouteNavigation` occupancy scan

**ISSUE:** Player group has no shared travel-speed cap  
**IMPACT:** Cavalry / faster units pull ahead of Spearmen on the same order  
**OWNER:** `PlayerRouteNavigation` player group path (enemy march already checkpoints)

**ISSUE:** Building-corner / occupancy pinches  
**IMPACT:** Units stall on inflated building cells; inflate was tightened, still a playability risk  
**OWNER:** `PlayerRtsOccupancyGrid`, unit stuck watch

**ISSUE:** Heavy Cavalry / Cavalry Archer / Cannon combat-order fork  
**IMPACT:** Hold / Patrol no-ops; attack-move / resume can diverge from infantry  
**OWNER:** those unit scripts vs `MilitaryUnit`

**ISSUE:** Hotkey collisions  
**IMPACT:** Debug **P** opens AI brain and blocks Patrol; worker **H/W/R** steal Hold / hero W / hero R  
**OWNER:** `InputManager`, `BuildManager._input`, `BuildCommands`

**ISSUE:** Mixed / placeholder art  
**IMPACT:** Cavalry, cannon, heroes, creeps, and many buildings are hard to read  
**OWNER:** scenes / art (Worker and Spearman already have original GLB art)

**ISSUE:** Fog of war is a leftover stub, not wired  
**IMPACT:** Full map always visible  
**OWNER:** not an active system — do not “finish the stub” unless asked

---

## CURRENT DEVELOPMENT RULES

- Fix existing systems before adding features.
- Do not add managers / states / watchdogs to solve local bugs.
- Prove the root cause before adding a mechanism.
- Prefer deleting conflicting leftover code over layering another implementation.
- Tests / headless `verify_*.tscn` do not replace manual RTS play.
- Performance changes need before/after F3 (or equivalent) numbers.
- Commit only after the user asks, and after the implementation/test workflow in `WORKFLOW.md`.
- Avoid architecture churn unless measured evidence demands it.
- UI never becomes gameplay-state authority.
- Latest player command always wins (command generations).
- Prefer `EntityHandle` / instance IDs + `NodeSafety` over raw stale Node refs.

Balance numbers live in `scripts/balance/`. Do not rebalance in random scripts.

---

## IMPLEMENTED (do not document as missing)

- Gold / wood / food, farms, expansions, worker gather cycles
- Full building roster including walls/gates, Shop, Blacksmith, Stable, Academy, Artillery Depot
- Full unit roster: Worker, Spearman, Swordsman, Archer, Light/Heavy Cavalry, Cavalry Archer, Cannon
- Three Heroes (Paladin, Shadow Assassin, Ranger) with XP, levels, QWER ranks, items, passives
- Neutral camps (medium + strong on the current map), camp respawn, kill XP/gold
- Command Center T1/T2/T3 gates and Blacksmith / Stable / Academy upgrades
- Victory / defeat → main menu
- Easy / Normal / Hard (same brain; Hard 1.5× enemy income and train speed; Easy fewer military buildings / towers)
- Custom RTS movement, automatic formations, F3 overlay, enemy inspect HUD
- Control groups 1–9, F1 hero, Space hero-follow, idle-worker `.`

See `docs/GAME_DESIGN.md` for design meaning and `docs/ROADMAP.md` for priority.
