# Endless Battle — Roadmap

Priority order for the **current** repository. Status values: **DONE**, **IN PROGRESS**, **NEXT**, **LATER**, **NOT PLANNED**.

Constitution and movement contract outrank this file. Source outranks all three if they disagree.

---

## Milestone

Playable 1v1 vs AI on one map: economy, Hero, army, creep, tech, expand, fight, win/lose, restart.

Core loop is **DONE**. Remaining work is reliability, command consistency, and readability — not missing victory, XP, tech, or upgrades.

---

## PHASE 1 — PERFORMANCE + MOVEMENT RELIABILITY

**Status: IN PROGRESS / NEXT**

| Item | Status |
|------|--------|
| Custom RTS grid + shared group route (no NavigationAgent3D travel) | DONE |
| Automatic line / rectangle / square slots in `PlayerRouteNavigation` | DONE |
| Bounded soft separation + spatial hash | DONE |
| F3 performance counters (live overlay) | DONE |
| Enemy cohesive checkpoint march | DONE |
| Dense-army FPS at intended sizes | IN PROGRESS |
| Trees / forests on the strategic occupancy grid | NEXT |
| Player group travel-speed sync (faster units wait for slower) | NEXT |
| Building-corner / choke stall | IN PROGRESS |
| Formation as guidance that compresses off buildings | DONE (keep improving if playtests fail) |

**Definition of done:** a normal mid/late army stays playable and reaches valid destinations without a second movement architecture.

---

## PHASE 2 — MILITARY COMMAND CONSISTENCY

**Status: NEXT** (after or beside Phase 1 only when a command bug is the proven cause)

| Item | Status |
|------|--------|
| Spearman / Swordsman / Archer / Light Cavalry / Heroes on `MilitaryUnit` | DONE |
| Move / Attack-Move / Stop on those units | DONE |
| Hold / Patrol on `MilitaryUnit` | DONE |
| Heavy Cavalry / Cavalry Archer / Cannon inherit the same contract | NEXT |
| Focus fire (RMB enemy) | DONE |
| Local combat resume after attack-move kills | IN PROGRESS (forked units diverge) |

Do not add a new command bus. Move the forked units onto `MilitaryUnit` (or delete the duplicate layer).

---

## PHASE 3 — PLAYER INPUT / UI RELIABILITY

**Status: IN PROGRESS**

| Item | Status |
|------|--------|
| HUD command bar, production queue, RMB cancel | DONE |
| Enemy / resource inspect HUD | DONE |
| Build ghost skips HUD clicks (Farm click must not drop Barracks) | DONE (keep a regression watch) |
| Debug P vs Patrol | NEXT |
| Worker H / W / R vs Hold and Hero QWER | NEXT |
| Attack-move cursor / mode clarity | LATER |
| Debug F3 / F8 / F9 / movement-lab stay debug-only | DONE enough |

---

## PHASE 4 — MATCH / COMBAT POLISH

**Status: LATER** (basics exist)

| Item | Status |
|------|--------|
| Win / loss → menu with rematch | DONE |
| Combat damage numbers / health bars | DONE |
| Alerts / missing-base / under-attack readability | LATER |
| Attack timing / role readability | LATER |

---

## PHASE 5 — AI OUTCOME POLISH

**Status: LATER**

Keep the 0.5s IF-condition brain. No new AI framework.

| Item | Status |
|------|--------|
| Condition-tick `EnemyAI` | DONE |
| Macro independent of military | DONE |
| Easy / Normal / Hard capacity knobs | DONE |
| Hero stays with army (home if missing) | DONE |
| Placement / gather edge cases | IN PROGRESS |
| Hard feels smarter, Easy softer, without a second brain | LATER |

---

## PHASE 6 — MAP + CREEP GAMEPLAY

**Status: LATER**

| Item | Status |
|------|--------|
| Neutral camps + respawn + XP/gold | DONE |
| Medium + strong camps on the live map | DONE |
| Weak camps as a first-night ladder | LATER |
| Chokes / expansion geography | LATER |

---

## PHASE 7 — VISUAL READABILITY

**Status: IN PROGRESS**

| Item | Status |
|------|--------|
| Original Worker art | DONE |
| Original Spearman art | DONE |
| Quaternius stand-ins (Swordsman, Archer, some buildings, trees) | IN PROGRESS |
| Cavalry, Cannon, Heroes, creeps still placeholder / cube-like | NEXT after Phase 1–2 |
| New roster units | NOT PLANNED until existing roster is readable |

---

## PHASE 8 — AUDIO / FEEDBACK

**Status: LATER**

Placeholder melee hit and some VFX exist. Full audio pass is after core feel is stable.

---

## PHASE 9 — DEMO FEATURES

**Status: LATER**

Fog of war, richer minimap, extra maps — only once movement, FPS, and commands are trustworthy.

| Item | Status |
|------|--------|
| Fog of war | LATER (stub file exists, not wired, not autoloaded) |
| Minimap dots | DONE as placeholder |
| Campaign / multiplayer / extra races / replays | NOT PLANNED |

---

## Removed from “future work” (already in source)

Do not put these back on the todo list as if they were missing:

- Victory / defeat
- Hero XP / levels / ability ranks
- Tech tiers and upgrades
- Shop items
- Walls / gates
- Cavalry and Cannon as trainable units
- Three Hero kits
- Condition-tick enemy AI
- Custom RTS movement and automatic formations
