# Endless Battle — Development Workflow

How to change this repository without losing prior design decisions.

---

## Source of Truth

- **Current source code** is the implementation truth.
- **Constitution / engine / movement / workflow docs** are design and engineering constraints.

If source and docs disagree:

1. determine whether source is an intentional newer decision
2. update docs when architecture intentionally changes
3. never silently violate the constitution / rules

Related but non-equivalent context (do not treat as superseding this set):

- `cursor/AI_CONTEXT.md` — project snapshot / implemented systems
- `cursor/RULES.md` — older coding conventions (some superseded; see `ENGINE_RULES.md` giant-script rule)
- `docs/ROADMAP.md` — milestone task order
- `docs/MILITARY_AI_V2.md` — military V2 detail
- `docs/Architecture.md` — older architecture sketch

---

## Cursor Task Rule

Every implementation task should be focused.

Before modifying:

1. inspect relevant current code
2. inspect git diff / current working tree
3. read relevant constitution / rules:
   - `docs/GAME_CONSTITUTION.md`
   - `docs/ENGINE_RULES.md`
   - `docs/MOVEMENT_CONTRACT.md`
   - `docs/WORKFLOW.md`
4. identify root cause
5. change the smallest coherent area

Do not blindly implement assumptions from old prompts.

---

## Manual Gameplay Is Primary

For gameplay feel, **manual game testing is the main acceptance method**.

Examples:

- movement feel
- AI behavior
- combat
- pacing
- responsiveness

Automated / synthetic verification is useful mainly for:

- parser / runtime regressions
- deterministic lifecycle failures
- freed-instance regressions
- reset behavior
- narrow reproducible invariants

Do not build huge synthetic verification frameworks for subjective gameplay.

Existing headless harnesses under `scenes/debug/` and `scripts/ci/validate_import.sh` are preferred over inventing new frameworks.

---

## One Fix → Play → Commit

Preferred workflow:

1. one focused fix
2. parser / import check
3. user manually tests the real game
4. if correct: commit + push (only when the user asks, or when they explicitly accept the fix for commit)
5. next issue

Do **not** automatically commit a gameplay fix before manual acceptance unless explicitly instructed.

---

## No Prompt Stacking

If a previous Cursor prompt has already been implemented on the current project snapshot:

do not repeat it.

Inspect the result and continue from current state.

---

## New Zip / Snapshot Rule

When working from a new project snapshot:

- treat that snapshot as current implementation truth
- account for prompts already applied after that snapshot
- do not recommend superseded fixes

---

## Commit Discipline

One coherent gameplay change per commit.

Avoid mixing:

- navigation + AI
- UI + architecture
- crash fixes + new features

unless they are inseparable parts of one root cause.

Never create commits with parser errors.

Do not commit unless the user asks (or explicitly accepts a gameplay fix for commit after manual test).
