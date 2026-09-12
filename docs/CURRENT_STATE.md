# Endless Battle — Current State

Fast start for a new coding session. Details: `cursor/AI_CONTEXT.md`, `docs/GAME_DESIGN.md`, `docs/ROADMAP.md`.

Source wins if this disagrees with code.

---

## CURRENT BUILD STATUS

Playable Godot 4.7 1v1 vs AI. Core loop works: menu, gather, build, Hero, creep, tech, expand, fight, destroy the enemy Town Center, return to menu.

---

## WORKING

- Economy (gold / wood / food) and worker gather / build
- Full current building and unit roster, including cavalry, Cannon, walls/gates
- Three Heroes with XP, QWER, items, passives
- Neutral camps (medium + strong), kill rewards
- Town Center T1–T3, Blacksmith / Stable / Academy upgrades
- Victory / defeat
- Easy / Normal / Hard knobs (same AI brain)
- `EnemyAI` 0.5s condition tree (defend → no hero → army small → stuck hero → early creep → expansion creep → attack if ahead → extra creep → home)
- `PlayerRouteNavigation` shared-route movement + automatic formations
- Enemy checkpoint march
- F3 performance overlay (debug)
- Enemy inspect HUD, control groups, Space hero-follow

---

## KNOWN PROBLEMS

- Dense-army FPS still a risk
- Trees not on the strategic occupancy grid
- Player group has no shared travel speed
- Building-corner stalls still possible
- Heavy Cavalry / Cavalry Archer / Cannon do not share the `MilitaryUnit` command contract (Hold / Patrol empty)
- Hotkeys collide (debug P vs Patrol; worker H/W/R vs Hold / Hero)
- Many units / heroes still placeholder art

---

## NEXT 5

1. Keep intended army sizes playable (measure F3 before/after).
2. Put living trees on the strategic occupancy grid without breaking gather.
3. Sync player group travel so fast units do not abandon slow ones.
4. Move Heavy Cavalry / Cavalry Archer / Cannon onto the same combat-order contract as infantry.
5. Untangle Patrol / Hold / Hero / build hotkeys (start with debug P vs Patrol).

---

## DO NOT CHANGE WITHOUT EVIDENCE

- Do not add MilitaryDirector, ArmyCommander, behavior trees, wave/mission/watchdog managers
- Do not restore NavigationAgent3D-per-unit travel or FormationManager
- Do not invent a second strategic AI
- Do not shrink designed army sizes to hide FPS
- Do not treat leftover `formation_*.gd` / fog stub as live systems
- Do not rewrite working economy / tech / Hero XP / win-loss
