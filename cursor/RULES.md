# Endless Battle — AI Coding Rules

These are short reminders. They do **not** replace `docs/GAME_CONSTITUTION.md`, `docs/ENGINE_RULES.md`, `docs/MOVEMENT_CONTRACT.md`, or `docs/WORKFLOW.md`.

**Source code is implementation truth.** `cursor/AI_CONTEXT.md` and `docs/CURRENT_STATE.md` are the live snapshot. Do not follow `docs/Architecture.md`, the 2026 technical audit, or `AUDIT_PROGRESS.md` as current architecture.

## Stack

- Godot 4.7, GDScript, 3D RTS
- Typed GDScript
- UI reads state and issues requests; UI is never gameplay-state authority
- Balance numbers belong in `scripts/balance/`

## Do

- One focused task
- Read current source for the system you touch
- Prefer `EntityHandle` / instance IDs + `NodeSafety`
- Latest player command wins (generations / tokens)
- After gameplay code: run existing parse / headless validation when appropriate
- Manual RTS play is the acceptance test for feel

## Do not

- Add MilitaryDirector, ArmyCommander, behavior trees, wave/mission/watchdog managers
- Restore NavigationAgent3D-per-unit travel or FormationManager
- Layer a second movement or AI brain
- Invent mechanics not in source or the current design docs
- Rewrite unrelated systems
- Commit gameplay changes unless the user asked (and usually after they playtested)
- Split a script only because it is over 500 lines — see `ENGINE_RULES.md`

## UI note

Production-queue RMB cancel must use `Control.accept_event()`, not `event.accept_event()`.
