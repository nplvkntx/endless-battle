# Endless Battle - Technical Architecture

## Goal

Endless Battle must be built as small independent systems.

No single script should control the whole game.

Each system should have one job.

## Engine

* Godot 4.x
* GDScript
* 3D game
* Placeholder cube visuals first
* Real models later

## Core Rule

Gameplay code must be:

* modular
* testable
* signal-based
* resource-driven
* easy for AI to modify safely

## Folder Structure

/autoloads
Global managers only.

/scripts/base
Base classes like Unit, Building, Hero.

/scripts/systems
Reusable systems like SelectionManager, CombatSystem, BuildManager.

/scripts/units
Specific unit scripts like Worker, Soldier, Archer.

/scripts/buildings
Specific building scripts like CommandCenter, Farm, Forge.

/scripts/heroes
Hero scripts like Paladin, Archmage, Ranger.

/scripts/ui
UI logic only.

/scenes
Godot scene files.

/resources
Gameplay data resources.

/docs
Design and planning documents (including ROADMAP.md for milestone priorities).

## Autoload Managers

Autoload managers are global systems.

They should not directly control individual units unless necessary.

Planned autoloads:

* GameSettings
* ResourceManager
* TechTree
* UpgradeManager
* FormationManager
* InputManager
* FogOfWarManager
* ProjectileManager

## Non-Autoload Systems

These are scene-level or local systems.

* SelectionManager
* BuildManager
* CombatSystem
* CameraController
* PatrolSystem
* RallyPointSystem

## Base Classes

### Unit

All movable units inherit from Unit.

Responsibilities:

* health
* movement
* selection state
* team ownership
* death handling

### Building

All buildings inherit from Building.

Responsibilities:

* health
* construction progress
* team ownership
* building state
* destruction handling

### Hero

Hero extends Unit.

Responsibilities:

* XP
* leveling
* abilities
* inventory
* respawn

## Communication Rules

Use signals when systems need to talk.

Example:

ResourceManager emits:

* resources_changed
* food_changed
* resource_spent_failed

UI listens to those signals.

UI does not directly change resources.

## Data Rules

Gameplay numbers should come from Resource files.

Examples:

* unit_data.tres
* building_data.tres
* hero_data.tres
* item_data.tres
* upgrade_data.tres
* game_settings.tres

Do not hardcode unit stats inside scripts.

## AI Development Rule

Cursor should only work on one task at a time.

Every task must include:

* goal
* files allowed to modify
* files not allowed to modify
* acceptance checklist
* manual test steps

## Finished System Rule

When a system is marked complete, Cursor must not rewrite it unless explicitly asked.

## Script Size Rule

No script should exceed 500 lines.

If a script becomes too large, split it into components.

## First Implementation Order

1. Project architecture
2. GameSettings
3. Resource files
4. Base Unit
5. Base Building
6. Camera
7. Selection
8. Movement
9. Resources
10. Workers
11. Buildings
12. Combat
13. Heroes
14. AI
15. UI polish

See `/docs/ROADMAP.md` for current milestone status and active priorities beyond this initial order.

## Definition of Done

A task is done only when:

* code compiles
* Godot opens without errors
* feature works manually
* Cursor reviewed the code
* test checklist passed
* Git commit was created
