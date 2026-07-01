# Endless Battle AI Context

## Project

Endless Battle — an **existing Godot 4.x RTS project** in active development.

This is **not** a new project initialization. Core gameplay systems are already implemented and playable from the main scene (`scenes/main.tscn`).

**Milestone 1 goal:** playable **1v1 RTS** (player vs AI opponent). See `/docs/ROADMAP.md` for current priorities.

## Engine

Godot 4.x

## Language

GDScript

## Art Style

Simple placeholder cubes.

No final art yet. Enemy buildings/units are hard to identify visually because they are mostly cubes — art differentiation is a known gap.

## Architecture

Signal-based.

Resource-driven (goal — many stats still exported/hardcoded in scripts).

Data-oriented.

Maximum script size: 500 lines.

Main scene: `scenes/main.tscn` (press F5 to run).

## Current Phase

Active **1v1 RTS** development — economy, combat, heroes, HUD, and **enemy AI** are in place. Current work focuses on AI stability, economy balance, and HUD polish — not new core systems.

## Implemented Systems

### Economy

* Gold, wood, and food via `ResourceManager` autoload
* Food cap from Farms
* Population/food checks block training when cap is full
* Resource bar HUD and feedback messages

### Buildings

* Town Center (Command Center) — trains Workers
* Barracks — trains Swordsmen and Archers
* Hero Altar — trains one Hero at a time
* Farm, Tower
* Worker-driven building placement (BuildManager)
* Construction progress on buildings

### Workers

* Gold mine and tree gathering
* Gather → carry → return to Town Center → deposit → auto-repeat cycle
* Build assignment for new structures

### Units

* Worker, Swordsman, Archer, Hero
* Training queues with rally points (Barracks, Hero Altar, Town Center)
* **Ctrl-click repeat training** — hold Ctrl and click a train button to queue repeated production

### Combat

* Melee combat (Swordsman, Hero, enemy unit retaliation)
* Ranged combat with arrow projectiles (Archer, Tower)
* Attack cooldowns, auto-attack when idle, attack-move
* Shared `CombatTargetValidation` helper
* `HealthComponent`, dynamic health bars, floating damage numbers
* Melee hit sound placeholder

### Hero

* One Hero per player; trainable from Hero Altar
* Mana (`max_mana`, `current_mana`, mana costs, mana regeneration)
* Abilities with cooldowns and placeholder VFX:
  * **Q** — Ground Slam (AoE)
  * **W** — Divine Protection (temporary damage immunity)
  * **E** — Power Strike (single-target empowered melee)
  * **R** — Execute (instant kill below health threshold)
* Hero shown in selection info panel with mana display

### HUD & UI

* **Compact MOBA/RTS-style HUD layout**
* Resource bar at top
* RTS bottom command bar (`CommandBar` — portrait/info left, details center, commands right)
* **Bottom selected-unit HUD hides when nothing is selected**
* **Minimap placeholder** — shows unit/building dots; orientation is good enough for now but needs polish later
* **Building production HUD** — displays queue/progress when available
* **RMB production cancel/dequeue** — right-click a queued production slot to cancel; uses `Control.accept_event()`, not `event.accept_event()` (crash fix applied)
* Context-sensitive command panel (build, train, attack, hero abilities)

### Selection & Commands

* Click and box selection
* Multi-selection (shared worker build commands, shared combat move/attack)
* Mixed selection hides conflicting commands

### Camera

* RTS camera controller (pan, zoom)

### Enemy AI

* AI opponent builds structures (including Hero Altar and additional army production buildings)
* AI trains units and **scales army production** over time
* AI can **train and respawn hero** from Hero Altar
* Enemy hero integration exists but **still needs smarter behavior** (ability use, positioning, etc.)
* `EnemyDummy` may still exist for dev/test setups — do not assume all enemies are dummies

## Known Issues & Next Priorities

Do not assume these are fixed. Current focus order is in `/docs/ROADMAP.md`.

1. **AI worker gathering pathfinding** — still needs improvement; enemy workers can cluster at one tree and get stuck
2. **AI economy balance** — too rigid; e.g. too many wood workers and too few gold workers
3. **AI construction/placement** — sometimes places buildings in poor positions; sometimes leaves buildings unfinished
4. **Enemy selection HUD** — player should be able to select enemy units/buildings and see HUD info (not yet implemented)
5. **AI hero behavior** — hero exists and respawns but needs smarter decision-making
6. **Visual identification** — enemy buildings/units hard to tell apart (placeholder cubes)
7. **Victory/Defeat UI** — attempted but skipped because input handling became unstable; defer until input/UI is stable
8. **Minimap polish** — functional enough for now; orientation/details can improve later

## Not Yet Implemented

Do not assume these exist:

* Player selection of enemy units/buildings with full HUD info
* Victory/Defeat screen (deferred — input instability)
* Hero leveling / XP (player hero)
* Full enemy AI polish (smart hero, adaptive economy, reliable pathfinding/placement)
* Fog of war (autoload stub only)
* Gameplay data Resources (`.tres`) for unit/building stats — mostly TODO on base classes
* Tech tree, upgrades, formations (autoload stubs only)
* Distinct enemy visual identity (still placeholder cubes)

## Cursor Workflow Rules

Every task should follow these rules:

* **One small task at a time** — small focused changes only
* **Do not scan the whole project** — read only the files needed for the current task
* **Do not run tests** — no automated test commands
* **Manual F5 test before commit** — user tests manually; always provide exact F5 test steps after changes
* **Do not refactor unrelated systems** or rewrite working systems
* **Do not modify completed systems** unless the task explicitly asks
* **No new helper scripts** unless the task explicitly requests them
* **No big refactors**
* **For UI tasks** — avoid creating parser-risk helper classes
* **For production UI** — RMB cancel must use `Control.accept_event()`, not `event.accept_event()`
* **Do not invent mechanics** not described in the task or `/docs`

## Important

The documentation inside `/docs` is the source of truth.

Never contradict it.

Never invent mechanics.

Never modify completed systems unless explicitly instructed.
