# Endless Battle — Player Movement Contract

**Status:** Target design for player movement.

The historical high-level player movement stack (continuous formation steering, corridor state machines, competing stuck layers, etc.) is considered failed / overcomplicated and must be replaced or fully bypassed for normal player Move / Attack-Move.

Current intended authority: autoload `PlayerRouteNavigation` (`scripts/systems/player_route_navigation.gd`) with `PlayerRoute` payloads. Do not preserve old behavior simply because it still exists elsewhere in the codebase.

---

## Target Principle (Warcraft III-like)

```
PLAYER CLICK
  → calculate valid route
  → follow valid route
  → local avoidance
  → reach destination
```

Movement should be boring, predictable, and trustworthy.

---

## Keep (Low-Level Infrastructure)

- physical collision
- building occupancy / custom RTS grid obstacles
- selection (`SelectionManager`)
- command queue
- attack-move command concept
- path debug visualization
- `PlayerRouteNavigation` custom RTS occupancy grid + route follow

NavigationAgent3D is **not** used for strategic unit travel.

---

## Remove / Bypass for Normal Player Movement

The rewrite must **not** preserve old behavior simply because it already exists.

Remove or bypass for normal player movement:

- moving formation anchors
- continuous formation steering
- continuous formation-slot updates
- squad cohesion steering
- per-unit moving corridor offsets
- corridor state machines
- follow-the-leader state machines
- repeated movement-target refresh
- multiple competing stuck recovery layers
- group ownership that survives a newer individual command

Do **not** stack replacements on top of these.

`FormationManager` may still exist for AI, UI prefs, or future arrival organization — it must not continuously steer player march orders or fight a newer player command.

---

## New Player Movement Authority

One player-issued command owns movement.

Each command stores:

- command generation
- command type
- original clicked destination
- validated route
- final destination information

A new command invalidates all old movement state immediately.

Latest player command always wins.

---

## Individual Command Override

If a unit belonged to a group and the player selects it alone and gives a new command:

the unit immediately detaches from previous group movement state.

Old:

- route
- group
- formation
- recovery
- callbacks

must never retake control.

---

## Validated Route

A route must:

- start on valid navigation
- end on valid navigation
- consist of navigable waypoints / segments
- respect building / obstacle clearance

A valid path is more important than perfect spacing.

---

## Group Principle

Multiple selected military units may share a strategic route.

The route is a **corridor**, not a moving formation.

Units may:

- compress
- trail
- temporarily queue

They do not need to preserve formation during travel.

---

## Workers

Workers use the same custom RTS strategic travel backend as military units.

Task systems decide **where** (mine / tree / drop-off / build approach points).
`PlayerRouteNavigation` / custom RTS decide **how** to get there.

Do not give workers a separate NavigationAgent pathfinder.

---

## Stuck Rule

There will be **one** stuck recovery system for player route travel.

A stuck unit:

- keeps current player command
- keeps original destination
- returns / repaths onto a valid current route
- continues

Do not:

- randomize destination
- regenerate formations
- reshuffle the whole group
- let recovery override newer player commands

---

## Known-Good Path Principle

If one unit successfully traversed a shared route segment, that segment can be treated as known-good evidence for other members.

A stuck member may re-enter that route.

Do not copy exact physical footsteps.

---

## Formations

Formations are **not** part of the baseline movement rewrite.

Add formations only after basic movement is proven stable.

Future formations should primarily affect **final arrival organization**, not continuously steer marching units.

---

## Movement Acceptance Tests

Baseline is not complete until:

1. 5 workers move around Town Center without one getting stuck.
2. A stuck / group member selected alone immediately obeys a new command.
3. 20 military units route around buildings.
4. 40 units traverse a moderate chokepoint.
5. Rapid A → B → C commands leave only C authoritative.
6. Unit death during movement causes no freed-instance crash.

Manual playtesting is the primary acceptance method for feel (see `docs/WORKFLOW.md`).
