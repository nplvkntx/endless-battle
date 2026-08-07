# Endless Battle — Engine Rules

Concrete engineering constraints. Class/system names below are confirmed against current source.

---

## Ownership

Every important state must have **one** authoritative owner.

| Concern | Owner | Notes |
|---------|--------|--------|
| Player selection | `SelectionManager` | Scene system (`scripts/systems/selection_manager.gd`). No `class_name`; node/script name is the authority. Stores selection identity via `EntityHandle`. |
| Enemy military strategy | `MilitaryDirectorV2` | Sole strategic state / mission publisher when V2 is enabled. |
| Enemy military executable orders | `ArmyCommanderV2` | **Only** enemy main-army order issuer under V2. Director never issues unit orders. |
| Match-owned AI state | `AIPlayerState` | Owned by match via `MatchCompositionRoot`. |
| Match composition / lifecycle | `MatchCompositionRoot` | Match-scoped wiring; declares military command authority. |
| Player movement commands | `PlayerRouteNavigation` | Autoload. Intended sole player Move / Attack-Move route authority (see `MOVEMENT_CONTRACT.md`). |
| UI | UI scripts under `scripts/ui/` | Reads gameplay state and issues requests. **Must not** become gameplay-state authority. |

Supporting infrastructure (not alternative owners):

- `NodeSafety` — alive/freed Node validation helpers
- `EntityHandle` — identity-only safe entity references
- `EnemyArmyCommand` — low-level army order bus / helpers; not an independent mission owner under V2
- `FormationManager` — formation registry/UI/AI helpers; must not override newer player movement commands

See also `docs/MILITARY_AI_V2.md` for the V2 stack detail.

---

## Raw Node Lifetime Rule

Cross-system long-lived references should prefer:

- entity IDs
- instance IDs
- `EntityHandle` (or equivalent safe handles)

Avoid long-lived raw `Node` references where the referenced Node can be freed independently.

Especially avoid raw references in:

- AI targets
- movement groups
- delayed callbacks
- selection caches
- worker drop-offs
- building UI tracking
- attack targets
- construction tracking

For possibly stale Object Variants, validate **before**:

- typed assignment
- cast
- `is` check when unsafe on freed Variant
- property access
- method call
- signal access
- `get_instance_id()`

Use existing `NodeSafety` / `EntityHandle` infrastructure where available.

---

## Delayed Work Rule

Timers, deferred calls, async callbacks, and queued commands should use:

- immutable instance / entity ID
- command generation / token

—not captured raw `Unit` / `Building` references.

On execution:

**resolve → validate → verify generation → execute**

---

## Command Generation

Any system where old asynchronous work can compete with a newer command must use generations / tokens.

A stale callback may **never** override newer player input.

`PlayerRouteNavigation` already uses command generation for player routes; preserve and extend that pattern, do not bypass it.

---

## Parser Safety

Never do giant mechanical project-wide syntax changes without explicit need.

After every code task:

- run existing parse / headless validation (e.g. Godot headless import, `scripts/ci/validate_import.sh`, relevant `scenes/debug/verify_*.tscn` harnesses when appropriate)
- resolve all changed public API call sites
- do not commit parser errors

Do not create compatibility stubs just to make parsing succeed unless they represent the correct architecture.

---

## Giant Script Rule

Large scripts are **not** automatically bugs.

Do not refactor solely for aesthetics.

Extract code only when it materially improves:

- runtime safety
- performance
- ownership clarity
- bug isolation
- future feature development

(This intentionally overrides older “max 500 lines” guidance in `cursor/RULES.md` / `docs/Architecture.md` when those conflict.)

---

## Performance

Do not optimize theoretical issues.

Measure:

- FPS / frame ms
- orders/sec
- repaths/sec
- target searches/sec
- expensive AI / system update times

Prefer event-driven work over per-frame scans.

Never intentionally create per-unit strategic path calculation every frame.
