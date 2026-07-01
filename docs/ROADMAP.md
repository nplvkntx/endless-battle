# Endless Battle - Roadmap

## Milestone 1: Playable 1v1 RTS

**Goal:** A single-player match where the human player faces an AI opponent with economy, army production, heroes, and basic combat — win/lose conditions optional until UI is stable.

**Status:** In progress. Core loop works; AI and HUD need stability and polish.

## Current Focus (priority order)

1. **AI worker/resource pathfinding stability** — workers cluster at trees, get stuck; gathering routes unreliable
2. **AI construction/placement reliability** — poor building positions, unfinished buildings left behind
3. **Adaptive AI economy** — balance worker allocation (gold vs wood); reduce rigid over-commitment to wood
4. **Enemy selection HUD info** — player can select enemy units/buildings and see relevant HUD details
5. **AI hero smarter behavior** — hero trains and respawns but needs better ability/combat decisions
6. **Victory/defeat UI** — later, after input/UI handling is stable (previous attempt skipped due to input instability)

## Deferred / Lower Priority

* Minimap polish (orientation and presentation — good enough for now)
* Enemy visual differentiation (placeholder cubes — readability issue but not blocking milestone)
* Hero leveling / XP for player hero
* Fog of war
* Tech tree, upgrades, formations
* Gameplay data Resources (`.tres`) migration from hardcoded stats

## Done Recently (context for AI)

* Compact MOBA/RTS-style HUD layout
* Bottom selected-unit HUD hides when nothing is selected
* Minimap placeholder with unit/building dots
* Building production HUD with queue/progress display
* Ctrl-click repeat training
* RMB production cancel/dequeue (with `Control.accept_event()` fix)
* Enemy AI: Hero Altar build, hero train/respawn
* Enemy AI: additional army production buildings and scaled production

## Definition of Done (Milestone 1)

* Player can play a full match vs AI without soft-locks or crash loops
* AI gathers, builds, trains, and attacks with reasonable economy balance
* AI hero participates meaningfully in combat
* HUD supports player and (target) enemy selection feedback
* Manual F5 test checklist passes for the changed feature
* No regressions in production cancel or selection input
