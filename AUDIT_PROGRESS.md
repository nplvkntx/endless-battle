# Endless Battle — Technical Audit Progress

Permanent tracker for [docs/Endless_Battle_Technical_Audit.md](docs/Endless_Battle_Technical_Audit.md).

## Current phase

**PHASE 1 — Project Stability**

## Current task

**PHASE 1 #2 (blocked on green CI):** Build a deterministic match-reset test and eliminate leaked ObjectDB/RID/resources (audit #11). Do not start until CI gate from #1 is green on main.

## Completed tasks

### 2026-08-05 — Remove obsolete Quaternius modular worker/ranger candidates (audit PHASE 1 #1)

| Field | Detail |
|---|---|
| **Audit phase** | PHASE 1 — Project Stability |
| **Dead asset root cause** | Unused legacy Quaternius candidate packs shipped FBX/glTF materials that reference missing textures never present in the repo. Primary CI failure: `modular_worker_ranger_candidates` FBXs → `T_Regular_Male_Dark_BaseColor.png` / `T_Regular_Male_Normal.png` (and female/roughness siblings). After that removal, CI/fresh import next exposed unused `props/` (`Anvil`/`Barrel`/`Coin` → missing `T_Trim_Metal_*` / `T_Trim_Furniture_*`) and unused `characters/worker_peasant/` (same missing `T_Regular_Male_*` base textures). No active gameplay scene, unit, worker, ranger, preload, or exported property depended on any of these folders — live units use `ranger_warrior_candidates/Warrior.gltf` and `Ranger.gltf`. |
| **Files removed or repaired** | Deleted unused folders: `characters/modular_worker_ranger_candidates/` (64 files), `props/` (9 files), `characters/worker_peasant/` (18 files). Removed 46 obsolete lines from `assets/art/quaternius/MANIFEST.txt`. Stripped accidental UTF-8 BOM from `scenes/debug/verify_match_reset.tscn` (caused Godot `Parse Error: Expected '['` on fresh import). No scene/material/script replacements required for units. |
| **Validation result** | Repo-wide Quaternius texture URI/FBX scan: zero missing textures. Fresh `.godot` Godot 4.7.stable headless `--import`: zero `Can't open` / `ERROR` / `Parse Error` lines. `scripts/ci/validate_import.sh` → `VALIDATION PASS`. GitHub Actions confirmation pending. |
| **Next audit task** | PHASE 1 #2 — deterministic match-reset / ObjectDB leak elimination (audit #11), only after CI is green. |

### 2026-08-05 — Add headless import/parse CI (audit PHASE 1 #1, #10)

| Field | Detail |
|---|---|
| **Audit phase** | PHASE 1 — Project Stability |
| **Root cause** | No automated gate rejected parse/import failures on push; historical verify logs contained unresolved compile errors. |
| **Fix** | Added `.github/workflows/godot-import-check.yml` and `scripts/ci/validate_import.sh`: static autoload / scene reference checks, Godot 4.7-stable headless import, and a headless-safe smoke scene (`res://scenes/debug/verify_match_reset.tscn`). Workflow fails on non-zero exit or script/parse error patterns. |
| **Files changed** | `.github/workflows/godot-import-check.yml`, `scripts/ci/validate_import.sh`, `AUDIT_PROGRESS.md` |
| **Validation performed** | Workflow YAML reviewed; bash syntax OK; local Windows Godot 4.7 run of `scripts/ci/validate_import.sh` passes; CI uses official `Godot_v4.7-stable_linux.x86_64` (matches `project.godot` `4.7`). |
| **Remaining uncertainty** | CI does not run full verify harnesses, match gameplay, or leak/ObjectDB regression suites (PHASE 1 #2). Nav-mesh bake runtime warnings are not treated as failures. |

### 2026-08-05 — Fix Godot import CI failure (audit PHASE 1 #1)

| Field | Detail |
|---|---|
| **Audit phase** | PHASE 1 — Project Stability |
| **Exact CI failure** | GitHub Actions runs `Add automated Godot parser validation #1` (`bedb4fe`), `Fix Godot import CI failure #2` (`6136bbc`), `#3` (`28b3a01`), and `#4` (`b7d030c` / `7dbf0f3`) all failed in step `Validate import, references, and startup`. Final public annotation exposed the actual import error: `Godot import/parse reported script or resource errors. ERROR: Can't open file from path 'res://assets/art/quaternius/characters/modular_worker_ranger_candidates/T_Regular_Male_Dark_BaseColor.png' ... ERROR: Can't open file from path 'res://assets/art/quaternius/characters/modular_worker_ranger_candidates/T_Regular_Male_Normal.png' ...`. |
| **Root cause** | The workflow shell/download setup was not the final blocker. After repairing the import command and switching to a headless-safe smoke scene, the validator still failed because Godot 4.7 headless import is correctly surfacing real missing texture resources in the Quaternius modular worker/ranger asset set. Those missing files are outside the allowed workflow-only scope for this task. |
| **Fix** | Repaired the CI harness itself to use `--headless --import`, replaced the runtime probe with `res://scenes/debug/verify_match_reset.tscn`, and added GitHub Actions error annotations so the exact failing import/resource line is visible without private log access. The workflow now fails for a concrete repo asset problem rather than a hidden CI-script issue. |
| **Files changed** | `.github/workflows/godot-import-check.yml`, `scripts/ci/validate_import.sh`, `AUDIT_PROGRESS.md` |
| **Validation performed** | Public Actions metadata inspection; bash syntax validation; local run with official Windows `Godot_v4.7-stable_win64_console.exe`; full git diff review. |
| **Remaining uncertainty** | GitHub log archive itself was not publicly downloadable without repo-admin auth, but the public annotations are now sufficient to expose the failing resource path. Returning CI to green now requires fixing the missing asset references or restoring the missing texture files, which is outside this workflow-only task. |

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
| 2026-08-05 | CI `godot-import-check` (static + headless import + smoke scene) | Added — gates push/PR on Godot 4.7-stable |
| 2026-08-05 | Headless `--import` | Clean — registered `SquadNavContext`, `VariantUtils`; no `SCRIPT ERROR` / `Parse Error` |
| 2026-08-05 | `main_menu.tscn` headless | Clean startup |
| 2026-08-05 | `main.tscn` headless (3 frames) | Boots; nav bake runtime warnings only |
| 2026-08-05 | `verify_unit_navigation.tscn` | `PASS unit_navigation` |
| 2026-08-05 | `verify_match_reset.tscn` | `PASS` — 26 match resetters, clean state |
| 2026-08-05 | Autoload / scene script path scan | All paths present |
| 2026-08-05 | Remove unused `modular_worker_ranger_candidates` | Local import + `validate_import.sh` PASS |
| 2026-08-05 | Search for `T_Regular_Male_*` missing textures | Only historical AUDIT note remains |

## Known blockers

CI green confirmation for the obsolete Quaternius cleanup is required before PHASE 1 #2.

## Next task

**PHASE 1 #2 (blocked until CI green):** Build a deterministic match-reset test and eliminate leaked ObjectDB/RID/resources (audit #11). Do not begin until `godot-import-check` is green on main.
