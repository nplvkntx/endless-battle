# Endless Battle — Game Design

This document describes **what the game is**. Implementation lives in source. Numbers live in `scripts/balance/`.

---

## Vision

Classic PC RTS with:

- Warcraft III-inspired **Hero importance** and **creeping**
- Age of Empires-style **economy, farms, and expansion**
- Stronghold / Cossacks inspiration for **readable mass battles** (larger than WC3, not Cossacks-scale)
- Original Endless Battle units, balance, visuals, maps, and identity

It is **not** a Warcraft clone, not a MOBA, and not a campaign/multiplayer product in the current target.

Current product: **one map, one faction, 1v1 vs AI**.

---

## Match Structure

**Mode:** Player vs AI.

**Win:** destroy the enemy main Command Center.  
**Loss:** the player main Command Center is destroyed.

No score, timer, or last-unit-standing modes.

**Start (both sides):**

- 5 Workers
- 500 gold, 500 wood
- Food 5 / 15
- One Command Center, nearby gold mine and trees

**Typical progression:**

- **EARLY:** workers, Barracks, Spearmen, Farm, Hero Altar, first Hero, nearby creep
- **MID:** Blacksmith, Swordsmen / Archers, Town Center Tier 2, Stable / cavalry, expansion Command Center
- **LATE:** Tier 3, Academy, Artillery Depot / Cannon, upgrades, decisive attack on the enemy Town Center

After the match, the main menu shows Victory / Defeat. The player can change difficulty and start again.

---

## Economy

**Gold** — mined from Gold Mines. Workers gather in chunks, carry up to 10, return to a completed Command Center, repeat.

**Wood** — chopped from trees. Same carry / return cycle. Trees are finite.

**Food** — population cap only. Starts at 15. Each completed Farm adds +8. Training is blocked when `food used + cost > food max`.

No passive income. Kill gold is a secondary trickle.

**Workers** gather, build, and can fight poorly. The player assigns them; the AI keeps a gold-heavy split and always tries to have at least one wood worker when trees exist.

**Expansion:** a second Command Center at another mine. It is a drop-off and a second Town Center. Core military buildings stay gated by the **highest** completed Town Center tier plus Blacksmith.

---

## Buildings

| Building | Tier | Purpose | Unlocks |
|----------|------|---------|---------|
| Command Center (Town Center) | 1 | Trains Workers, drop-off, tier research | Economy; T2 / T3 research |
| Farm | 1 | Food cap | +8 food |
| Barracks | 1 | Infantry | Spearman always; Swordsman / Archer need Blacksmith |
| Hero Altar | 1 | One living Hero per faction | Paladin / Shadow Assassin / Ranger; retrain restores snapshot |
| Shop | 1 | Hero items | Permanent shop items for a nearby friendly Hero |
| Tower | 1 | Static defense | Ranged attacks |
| Wall / Gate | 1 | Block movement; gate can open | Passage control |
| Blacksmith | 2 (needs CC T2) | Infantry upgrades; tech keystone | Swordsman / Archer; further T2/T3 buildings |
| Stable | 2 (CC T2 + Blacksmith) | Cavalry | Light Cavalry, Cavalry Archer, Heavy Cavalry + cavalry upgrades |
| Academy | 3 (CC T3 + Blacksmith) | Economy / structure research | Faster gather/train/build, building HP, ballistics |
| Artillery Depot | 3 (CC T3 + Blacksmith) | Siege | Cannon |

There is no separate “research lab” tech tree. **Town Center tier + completed Blacksmith** are the gates. Upgrades are purchased on Blacksmith, Stable, and Academy.

---

## Units

| Unit | From | Gameplay role |
|------|------|----------------|
| Worker | Command Center | Economy / construction. Weak in combat |
| Spearman | Barracks | Frontline pike. Bonus vs cavalry |
| Swordsman | Barracks (Blacksmith) | Frontline melee |
| Archer | Barracks (Blacksmith) | Ranged anti-unit |
| Light Cavalry | Stable | Mobility / raid melee |
| Cavalry Archer | Stable | Mobile ranged |
| Heavy Cavalry | Stable | Heavy melee shock |
| Cannon | Artillery Depot | Siege / splash. Slow fire |

`EnemyDummy` exists for tests, not as a playable roster unit.

---

## Heroes

One living Hero per faction. Trained at the Hero Altar. Kit is locked for the match. Retrain costs the same as first train and restores level / XP / abilities / items.

Heroes gain XP from creeps (if in range) and from army kills. Max level 30. Ability points from levels 2–18. Ultimate ranks at 6 / 11 / 16. Shift+Q/W/E/R spends a point. Q/W/E/R casts.

**The Hero is part of the army.** The game should not encourage an AI Hero that hunts alone.

### Human Paladin

- **Role:** durable melee frontliner
- **Passive:** Holy Recovery — out-of-combat regen
- **Q** Ground Slam — self AoE
- **W** Divine Protection — brief immunity
- **E** Power Strike — single-target melee
- **R** Execute — kill / finish below a health threshold
- **With army:** stands in the line and slams clumps
- **Weakness:** less mobility than Assassin / Ranger

### Shadow Assassin

- **Role:** mobile melee assassin
- **Passive:** consecutive hits on the same target deal bonus damage
- **Q** Axe Mark
- **W** Smoke
- **E** Slash
- **R** Dash
- **With army:** should still travel with the army, then dive marked targets
- **Weakness:** fragile if isolated

### Ranger

- **Role:** fragile ranged marksman
- **Passive:** Hunter’s Precision — every 3rd hit vs the same non-building target deals % max-HP bonus
- **Q** Combat Roll
- **W** Bear Trap
- **E** Crossbow Bolt
- **R** Camouflage
- **With army:** rear / flank of the same march, not a lone hunter
- **Weakness:** dies quickly if caught

Enemy first Hero kit is a random pick among the three, then locked.

---

## Creeping

Neutral camps exist so Heroes can **level**, pick up **gold**, and so the map has early objectives besides rushing.

**CURRENT**

- Medium camps (6 creeps) and Strong camps (5 creeps) are placed on the map
- Reward tier is derived from creep attack damage (≤8 weak, ≤12 medium, else strong)
- Camp clear → respawn after 180s if the area is safe
- Hero must be in share range for creep XP unless they last-hit
- Early AI creeps until Hero level 3

**PLANNED (not fully authored on the current map)**

- Distinct weak camps as a first-night tutorial objective
- Stronger camp identity / geography (chokes, expansion guards) beyond renamed nodes
- Neutral item drops (`NEUTRAL_ITEM_ORDER` is empty)

---

## Tech Progression

Not a graph of named techs. Direct building / upgrade gates.

**T1:** CC, Farm, Barracks, Altar, Shop, Tower, Wall. Spearman + Hero.

**T2:** CC upgrade (800g / 500w / 60s). Blacksmith, then Stable and advanced Barracks units.

**T3:** CC upgrade (2000g / 1200w / 120s). Academy, Artillery Depot, Cannon.

**Blacksmith upgrades (levels):** Swordsman attack/armor; Archer attack / attack speed / range.

**Stable upgrades (levels):** attack/defense per cavalry type.

**Academy (one-shots):** Faster Gathering, Faster Unit Training, Improved Tools, Engineering, Ballistics.

---

## Army Movement

The player selects units and right-clicks (Move) or presses A then clicks (Attack-Move). The army should travel as **one group** on **one route**, with automatic line / rectangle / square spacing. The Hero travels in that group.

Units may compress through chokes and buildings, then reform. Local combat can break spacing. Faster units should not abandon slower ones — that last part is **desired feel**; player groups do not yet share a travel-speed cap.

No manual formation UI. No formation buttons.

Stop (S) cancels. Hold (H) means stay and fight in range without chasing — on units that actually implement it. Patrol (P) is click-to-patrol when the hotkey is not stolen.

---

## Combat

Should feel readable and deterministic: clear windup / cooldown, roles that matter, predictable chase / leash, Hero abilities that change fights, Attack-Move that continues after a kill, no constant target thrashing.

Towers and Cannons hit structures and clumps. Spearmen punish cavalry. Shop items and upgrades persist for the match.

---

## AI

The AI should feel like another RTS player, not a wave spawner.

It builds an economy, makes workers, lays out a base, trains a Hero, creeps early, techs, expands, researches upgrades, keeps **one primary army**, defends when the base is threatened, attacks when it has a power advantage, and otherwise creeps or waits at home while production continues.

---

## Difficulty

### CURRENT IMPLEMENTATION

Same strategic brain on Easy / Normal / Hard.

| | Easy | Normal | Hard |
|---|------|--------|------|
| Max Barracks / Stable / Depot | 1 | 3 | 3 |
| Desired towers | 2 | 3 | 4 |
| Enemy resource / train speed | 1× | 1× | 1.5× |

Worker targets scale with tier / expansion (13 / 20 / 28 / 33), not by difficulty.

### DESIRED FINAL BEHAVIOR

Hard should also feel sharper (better army use, less idle), Easy more forgiving (slower pressure), without a second AI framework.

---

## Controls

Bindings below are **actual current behavior**, mostly hardcoded (only Space is in the Input Map as `focus_hero`).

| Input | Current behavior |
|-------|------------------|
| LMB | Select / box select / place building / confirm ability / inspect enemy |
| RMB | Move, attack enemy, gather, cancel placement, cancel production slot |
| Shift | Queue move / extra patrol points; Shift+QWER learns abilities |
| Ctrl | Repeat train click; Ctrl+1–9 assign control group |
| A | Arm Attack-Move |
| S | Stop |
| H | Hold — **or** Hero Altar placement if Workers can use build hotkeys |
| P | Patrol — **or**, in debug matches, toggle AI brain panel |
| B / R / T / W / C | Farm / Barracks / Tower / Wall / extra CC (when worker build hotkeys apply) |
| Q W E R | Hero cast; also Blacksmith / Academy upgrade keys when those buildings are selected |
| T | Archer range / Ballistics upgrade when those panels are up; also Tower placement |
| 1–9 | Recall control group; double-tap focuses |
| F1 | Select Hero |
| Space (hold) | Camera follows living player Hero |
| . | Cycle idle Worker + camera |
| Mouse wheel / arrows / edge | Camera zoom / pan |
| Esc | Cancel placement |
| F3 | Performance overlay (debug) |
| F8 / F9 | Destroy enemy / player CC (debug) |

**KNOWN ISSUE:** several gameplay keys share owners. Debug P vs Patrol is the worst. Worker H/W/R vs Hold and Hero abilities are next.

---

## ENDLESS BATTLE MVP

A stranger must be able to:

- start a match
- gather, build, train
- use a Hero and creep
- tech and expand if they want
- command a reliable army
- fight the AI
- win or lose
- return to the menu and restart

with:

- no game-breaking movement
- no major FPS collapse at normal army size
- no frequent runtime errors
- understandable controls / UI

---

## Post-MVP

High value later, **not** current MVP:

- Fog of war
- Stronger map / chokes / camp progression
- Minimap and alert polish
- Original art for remaining units / heroes
- Audio / combat feedback
- Richer Hero / item loop
- Difficulty that changes behavior, not only multipliers

**Not planned for this milestone:** campaign, multiplayer, extra races, replays, many maps.
