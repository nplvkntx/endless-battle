# Endless Battle AI Context

## Project

Endless Battle — an **existing Godot 4.x RTS project** in active development.

This is **not** a new project initialization. Core gameplay systems are already implemented and playable from the main scene (`scenes/main.tscn`).

## Engine

Godot 4.x

## Language

GDScript

## Art Style

Simple placeholder cubes.

No final art yet.

## Architecture

Signal-based.

Resource-driven (goal — many stats still exported/hardcoded in scripts).

Data-oriented.

Maximum script size: 500 lines.

Main scene: `scenes/main.tscn` (press F5 to run).

## Current Phase

Active gameplay development — economy, combat, heroes, and RTS UI are in place.

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

### Combat

* Melee combat (Swordsman, Hero, EnemyDummy retaliation)
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

### Selection & Commands

* Click and box selection
* Multi-selection (shared worker build commands, shared combat move/attack)
* Mixed selection hides conflicting commands
* Context-sensitive command panel (build, train, attack, hero abilities)
* RTS bottom command bar HUD (`CommandBar` — portrait/info left, details center, commands right)
* Resource bar at top

### Camera

* RTS camera controller (pan, zoom)

### Enemies & Dev Test Setup

* `EnemyDummy` — stationary placeholder enemies; fight back in melee range (no chase AI)
* Main scene includes strong Hero test dummies and a dev Hero spawner near Town Center for fast ability testing

## Not Yet Implemented

Do not assume these exist:

* Hero leveling / XP / respawn
* Full enemy AI (patrol, chase, waves)
* Fog of war (autoload stub only)
* Gameplay data Resources (`.tres`) for unit/building stats — mostly TODO on base classes
* Tech tree, upgrades, formations (autoload stubs only)

## Cursor Workflow Rules

Every task should follow these rules:

* **Small focused changes only** — one task at a time
* **Do not run tests** — no automated test commands
* **User tests manually with F5** — always provide exact F5 test steps after changes
* **Do not refactor unrelated systems**
* **Read only the files needed** for the current task
* **Do not modify completed systems** unless the task explicitly asks
* **Do not invent mechanics** not described in the task or `/docs`

## Important

The documentation inside `/docs` is the source of truth.

Never contradict it.

Never invent mechanics.

Never modify completed systems unless explicitly instructed.
