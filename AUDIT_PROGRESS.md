# Endless Battle — Technical Audit Progress

Permanent tracker for [docs/Endless_Battle_Technical_Audit.md](docs/Endless_Battle_Technical_Audit.md).

## Current phase

**PHASE 1 — Project Stability**

## Current task

**PHASE 1 #2 (auto-selected next):** Build a deterministic match-reset test and eliminate leaked ObjectDB/RID/resources (audit #11). Do not start until CI gate from #1 is green on main.

## Completed tasks

### 2026-08-05 — Add headless import/parse CI (audit PHASE 1 #1, #10)

| Field | Detail |
|---|---|
| **Audit phase** | PHASE 1 — Project Stability |
| **Root cause** | No automated gate rejected parse/import failures on push; historical verify logs contained unresolved compile errors. |
| **Fix** | Added `.github/workflows/godot-import-check.yml` and `scripts/ci/validate_import.sh`: static autoload / scene reference checks, Godot 4.7-stable headless editor import, and main-menu startup (`--quit-after 3`). Workflow fails on non-zero exit or script/parse error patterns. |
| **Files changed** | `.github/workflows/godot-import-check.yml`, `scripts/ci/validate_import.sh`, `AUDIT_PROGRESS.md` |
| **Validation performed** | Workflow YAML reviewed; static checks runnable without Godot; CI uses official `Godot_v4.7-stable_linux.x86_64` (matches `project.godot` `4.7`). |
| **Remaining uncertainty** | CI does not run full verify harnesses, match gameplay, or leak/ObjectDB regression suites (PHASE 1 #2). Nav-mesh bake runtime warnings are not treated as failures. |

### 2026-08-05 — Fix AIHeroMastery parser / compile failures (audit #39, #10)

| Field | Detail |
|---|---|
| **Audit phase** | PHASE 1 — Project Stability |
| **Root cause** | `AIHeroMastery` (`scripts/systems/ai_hero_mastery.gd`) and dependent call sites used unsafe `bool(variant)` conversions on `Callable.call()` / `Dictionary.get()` results. Godot 4.7 strict typing rejected these patterns and blocked compilation of the autoload and downstream scripts (`match_session.gd`, `resource_manager.gd`, verify scenes). Historical `nav_verify_log.txt` also showed unresolved `UnitNavigation` / `Unit` errors; current tree registers `class_name UnitNavigation` and parses cleanly. |
| **Fix** | Introduced `VariantUtils.to_bool()` (`scripts/systems/variant_utils.gd`) and replaced invalid `bool(...)` conversions across AI hero mastery and related hot paths. |
| **Files changed** | `scripts/systems/ai_hero_mastery.gd`, `scripts/systems/variant_utils.gd` (+ `.uid`), `autoloads/control_group_manager.gd`, and related verify / systems / UI call sites (see commit `6d562aa`). |
| **Validation performed** | Godot 4.7 headless: `--import` (all autoloads + global classes, no parse errors); `scenes/ui/main_menu.tscn` startup; `scenes/main.tscn` 3s run; `scenes/debug/verify_unit_navigation.tscn` → `PASS unit_navigation`; `scenes/debug/verify_match_reset.tscn` → `PASS` (26 resetters); static checks: all 21 `project.godot` autoload paths exist; all `.tscn` `ext_resource` script paths resolve; `run/main_scene` = `res://scenes/ui/main_menu.tscn` matches `MatchSession.MAIN_MENU_SCENE`. |
| **Remaining uncertainty** | Runtime nav-mesh warnings during verify harness baking are performance warnings, not parse failures. Full leak / ObjectDB regression suite not re-run in this session. |

## Skipped or outdated audit findings

| Audit item | Status |
|---|---|
| **#10** Navigation verify log parse failures (`UnitNavigation`, `Unit`) | **Outdated** — `scripts/systems/unit_navigation.gd` has `class_name UnitNavigation`; headless verify passes in current tree. |
| **#39** AIHeroMastery parser errors | **Resolved** in `6d562aa` (validated 2026-08-05). |
| **#12** Stub autoloads (`GameSettings`, `FogOfWarManager`, `ProjectileManager`) | **Deferred** — stubs parse and boot; `GameSettings` is referenced by hero ability targeting. Removal is PHASE 1 #3, not a startup blocker. |
| **#63–64** Debug perf autoloads in production | **Deferred** — `PerfDebugOverlay` gates input on `OS.is_debug_build()`; not a parser/startup failure. |

## Validation history

| Date | Check | Result |
|---|---|---|
| 2026-08-05 | CI `godot-import-check` (static + headless import + main menu) | Added — gates push/PR on Godot 4.7-stable |
| 2026-08-05 | Headless `--import` | Clean — registered `SquadNavContext`, `VariantUtils`; no `SCRIPT ERROR` / `Parse Error` |
| 2026-08-05 | `main_menu.tscn` headless | Clean startup |
| 2026-08-05 | `main.tscn` headless (3 frames) | Boots; nav bake runtime warnings only |
| 2026-08-05 | `verify_unit_navigation.tscn` | `PASS unit_navigation` |
| 2026-08-05 | `verify_match_reset.tscn` | `PASS` — 26 match resetters, clean state |
| 2026-08-05 | Autoload / scene script path scan | All paths present |

## Known blockers

None for Phase 1 stability baseline.

## Next task

**PHASE 1 #2 (auto-selected):** Build a deterministic match-reset test and eliminate leaked ObjectDB/RID/resources (audit #11). CI import gate (#1) must stay green; do not expand scope into gameplay refactors.
