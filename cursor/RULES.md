# Endless Battle - AI Coding Rules

## General Rules

* Engine: Godot 4.x
* Language: GDScript
* Architecture first, features second.
* Never sacrifice architecture for speed.

## Coding Standards

* Maximum script length: 500 lines.
* Always use typed GDScript.
* Use signals instead of direct references whenever possible.
* Never duplicate code.
* Follow the Single Responsibility Principle.
* One class = one responsibility.
* No circular dependencies.
* Avoid singleton abuse.

## Data Rules

* Never hardcode gameplay values.
* Store gameplay values inside Resources (.tres).
* Managers read Resources.
* UI never changes gameplay directly.

## Modification Rules

* Never rewrite working systems.
* Only modify files related to the current task.
* Preserve backwards compatibility.
* If a future feature is required, leave a TODO comment instead of implementing it.

## Performance

* Avoid unnecessary processing every frame.
* Cache expensive lookups.
* Use object pooling later for projectiles and effects.

## File Organization

Scenes:
scenes/

Scripts:
scripts/

Resources:
resources/

Documentation:
docs/

## UI Rules

* For production queue UI, RMB cancel/dequeue must use `Control.accept_event()` — not `event.accept_event()` (causes crashes).
* Avoid creating parser-risk helper classes for UI tasks unless explicitly requested.
* Victory/defeat and other modal UI must not break input handling — defer if unstable.

## Cursor Workflow

* One small task at a time — no big refactors.
* Read only files needed for the task — do not scan the whole project.
* No new helper scripts unless the task explicitly requests them.
* Manual F5 test before commit; provide exact test steps after changes.
* See `AI_CONTEXT.md` and `/docs/ROADMAP.md` for current project state and priorities.

## AI Behavior

If something is unclear:

Do NOT guess.

Instead explain what information is missing.

Never invent game mechanics not described in the documentation.

Always explain:

* which files were created
* which files were modified
* why the changes were made
