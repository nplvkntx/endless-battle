# Endless Battle — Technical Audit Progress

Permanent tracker for [docs/Endless_Battle_Technical_Audit.md](docs/Endless_Battle_Technical_Audit.md).

## Current phase

**PHASE 2 — Architecture**

## Current task

**PHASE 2 first scoped EnemyArmyCommand extraction complete** (`EnemyArmyCommandTelemetry`). Next Phase 2 milestone: second scoped extraction (order-agnostic military math/scoring helpers) — do not begin a second extraction in the same pass; do not start broad god-object splits.

## Completed tasks

### 2026-08-05 — EnemyArmyCommand telemetry extraction (first scoped helper)

| Field | Detail |
|---|---|
| **Audit phase** | PHASE 2 — Architecture |
| **Responsibility extracted** | Non-authoritative order-issue / perf / debug bookkeeping (F3, AI PERF prints, verify seeds). Never mission selection or order execution. |
| **New type** | `EnemyArmyCommandTelemetry` (`scripts/systems/enemy_army_command_telemetry.gd`) — `RefCounted` + static methods; **not** an autoload. |
| **Functions / variables moved** | Vars: `debug_enabled_override`, `perf_diag_timer`, `orders_issued_since_diag`, `perf_overlay_status_timer`, `last_issued_order_*`. Const: `PERF_DIAG_INTERVAL_SECONDS` (+ overlay interval). Methods: `reset_match_state`, `seed_for_verify` / `snapshot_for_verify`, `set_debug_override` / `is_debug_override_enabled`, `record_order_issued` / `take_orders_issued_since_diag`, `tick_overlay_timer` / `tick_perf_diag_timer`, `note_issued_order` / `clear_issued_order`, `get_seconds_since_last_order`, `get_last_issued_order_label` / `destination`, `_log_issued_order`. |
| **Coupling removed** | EAC no longer owns diagnostic bags; F3 readers (`MilitaryDirectorV2`) call telemetry directly; verify seeds/snapshots hit the helper. EAC still orchestrates `tick_perf_diagnostics` (mission watchdog + overlay push that reads army SoT). |
| **Remaining EnemyArmyCommand responsibilities** | Match binding; `_rt()` accessors into `AIPlayerState`; frame-local unit caches; command/order APIs; mission watchdog orchestration; formation/scoring/army helpers; overlay status push into `PerfCounters`. |
| **Authority unchanged** | `AIPlayerState` SoT; `MilitaryDirectorV2` selects missions; `ArmyCommanderV2` sole executable authority; intent providers issue no orders. |
| **Next extraction safe?** | **Yes**, for another narrow seam (order-agnostic math/scoring). Do **not** extract command execution, mission transitions, order queues, or state ownership next. |
| **Files changed** | `enemy_army_command_telemetry.gd` (new), `enemy_army_command.gd`, `military_director_v2.gd`, `verify_match_composition_root.gd`, `docs/MILITARY_AI_V2.md`, `AUDIT_PROGRESS.md` |
| **Validation result** | Godot 4.7 `--import` clean. `validate_import.sh` → `VALIDATION PASS`. `verify_match_composition_root` → `PASS` (telemetry isolation, no autoload, reset clears bags). `verify_match_reset` → `PASS`. `verify_freed_instance_regression` → `PASS`. |
| **Next audit task** | Second scoped EAC helper extraction (pure military math/scoring) or leave facade intact until a clean seam appears. |

### 2026-08-05 — EnemyArmyCommand final static-state ownership cleanup

| Field | Detail |
|---|---|
| **Audit phase** | PHASE 2 — Architecture |
| **Related issues** | Classify + resolve remaining EAC statics: creep-contest cooldowns, objective stuck/eval timers, debug/telemetry. Prove no second SoT and no stale mission reactivation via leftover timers. |
| **Final static-state classification** | See table below. |
| **Migrated → `AIPlayerState`** | `creep_contest_cooldowns` (match-owned). `objective_reissue_timer`, `objective_stuck_timer`, `objective_last_building_health`, `objective_eval_timer`, `objective_stuck_check_timer` (mission/wave-owned). EAC names are `_rt()` accessors — no dual authoritative copy. `_reset_objective_tracking` now clears **all** objective timers (incl. eval/stuck-check) so they cannot survive wave cancel. |
| **Retained on EAC (non-authoritative)** | Frame-local: `_main_army_cache`, `_combat_units_cache_frame`, `_cached_offensive_wave_units*`, `_last_combat_eval_msec`. Telemetry: `_debug_enabled_override`, `_perf_diag_timer`, `_orders_issued_since_diag`, `_perf_overlay_status_timer`, `_last_issued_order_*`. Binding: `_bound_player_state`, `_declared_command_authority`, `_unbound_runtime`. |
| **Telemetry isolation** | Last-issued / perf / debug-override never enqueue orders, invent contest cooldowns, or change `army_mode` / `exec_mission`. F3 / watchdog labels only. |
| **Singular authority proof** | Composition verify asserts SoT identity for creep contest + objective timers, cancel clears timers, reset clears match bags, telemetry seed leaves mission/queue untouched, providers still issue no orders under V2. |
| **EnemyArmyCommand ready for scoped extraction?** | **Yes.** All authoritative military runtime is on `AIPlayerState`. First extraction may isolate telemetry or pure helpers — do **not** begin broad god-object splits in the same pass. |
| **Files changed** | `ai_player_state.gd`, `enemy_army_command.gd`, `verify_match_composition_root.gd`, `docs/MILITARY_AI_V2.md`, `AUDIT_PROGRESS.md` |
| **Validation result** | Godot 4.7 `--import` clean. `validate_import.sh` → `VALIDATION PASS`. `verify_match_composition_root` → `PASS` (creep contest SoT, objective cancel/reset, telemetry isolation, no static military SoT outside AIPlayerState). `verify_match_reset` → `PASS` (registry=27). `verify_freed_instance_regression` → `PASS`. |
| **Next audit task** | First scoped `EnemyArmyCommand` helper extraction (telemetry or order-agnostic math). Do not start broad splits. |

#### Final EnemyArmyCommand static classification (2026-08-05)

| Group (exact vars) | Class | Influences orders? | Final owner |
|---|---|---|---|
| Identity/exec/combat/wave/formation/finishing via `_rt()` | Match-owned durable | Yes | `AIPlayerState` |
| `pending_group_orders`, `issuing_group_order_batch` | Command queue | Yes | `AIPlayerState` |
| `reinforcement_pool` | Match-owned durable | Yes | `AIPlayerState` |
| `defense_threat_cache*`, `emergency_threat_cache*` | TTL scratch | Scoring only | `AIPlayerState` |
| `exec_*` watchdog / scratch | Mission-owned transient | Watchdog refresh only | `AIPlayerState` |
| `_creep_contest_cooldowns` → `creep_contest_cooldowns` | Match-owned durable | Yes (blocks contest) | `AIPlayerState` |
| `_objective_*` timers → `objective_*` | Mission-owned transient | Yes (reissue/unstick) | `AIPlayerState` |
| `_main_army_cache`, combat/wave frame caches, `_last_combat_eval_msec` | Frame-local cache | Discovery only | EAC static |
| `_debug_enabled_override`, `_perf_*`, `_orders_issued_since_diag`, `_last_issued_order_*` | Telemetry | No | EAC static |
| `_bound_player_state`, `_declared_command_authority`, `_unbound_runtime` | Binding / offline host | Wiring only | EAC static |

### 2026-08-05 — EnemyArmyCommand runtime state migration (threat / reinforcement / queue / watchdog)

| Field | Detail |
|---|---|
| **Audit phase** | PHASE 2 — Architecture |
| **Related issues** | (1) Classify remaining EAC static bags. (2) Migrate highest-risk bags: threat TTL caches, reinforcement pool, pending group orders, exec watchdog/scratch. (3) Prove frame-local caches stay frame-local. |
| **Classification of remaining EAC static state (post-migration)** | See table below. |
| **State migrated → `AIPlayerState`** | `pending_group_orders`, `issuing_group_order_batch`, `reinforcement_pool`, `defense_threat_cache` (+ msec), `emergency_threat_cache` (+ msec), `exec_objective_node`, `exec_last_progress_msec`, `exec_last_distance`, `exec_squad_ids`, `exec_watchdog_timer`, `exec_watchdog_refreshed`, `exec_last_report`. EAC names are `_rt()` accessors — no dual authoritative copy. |
| **Frame-local (kept on EAC static; cleared on reset; never SoT)** | `_main_army_cache`, `_combat_units_cache_frame`, `_cached_offensive_wave_units` (+ frame), `_last_combat_eval_msec`. Seeded + asserted empty after `prepare_new_match`. |
| **Command queue owner** | Match-owned `AIPlayerState.pending_group_orders`. Drained by `ArmyCommanderV2` via `EnemyArmyCommand.tick_group_order_batch`. |
| **Remaining compatibility mirrors** | None for migrated bags (accessors only). `_sync_player_state_identity` remains a documented no-op. |
| **Remaining EAC static (not migrated this slice)** | `_creep_contest_cooldowns` (match-durable), objective stuck/eval timers (mission-transient), `_debug_enabled_override` + perf/order-issue diagnostics (telemetry). |
| **EnemyArmyCommand ready for scoped extraction?** | **Not yet.** High-risk runtime bags are match-owned, but creep-contest + objective timers + the ~7k-line facade remain. First extraction only after leftovers are non-authoritative / classified. |
| **Files changed** | `ai_player_state.gd`, `enemy_army_command.gd`, `verify_match_composition_root.gd`, `docs/MILITARY_AI_V2.md`, `AUDIT_PROGRESS.md` |
| **Validation result** | Godot 4.7 `--import` clean. `validate_import.sh` → `VALIDATION PASS`. `verify_match_composition_root` → `PASS` (queue/reset, reinforcement owner, watchdog non-reactivation, frame caches, providers no orders). `verify_match_reset` → `PASS` (registry=27). `verify_freed_instance_regression` → `PASS`. |
| **Next audit task** | Remaining low-risk EAC statics, then first scoped helper extraction — do not start broad god-object splits. |

#### Remaining EnemyArmyCommand static classification (2026-08-05)

| Group (exact vars) | Class | Survives strategic tick? | Survives match reset? | Issues / influences orders? |
|---|---|---|---|---|
| Identity/exec/combat/wave/formation/finishing via `_rt()` | **Match-owned durable** (AIPlayerState) | Yes | No (reset clears) | Yes (mission/mode) |
| `pending_group_orders`, `issuing_group_order_batch` | **Command queue** (AIPlayerState) | Yes until drained | No | Yes (enqueued unit orders) |
| `reinforcement_pool` | **Match-owned durable** (AIPlayerState) | Yes | No | Yes (hold/rally eligibility) |
| `defense_threat_cache*`, `emergency_threat_cache*` | **TTL scratch on AIPlayerState** (not SoT) | Brief TTL (~0.35s) | No | Influences defense scoring only; recomputed from world |
| `exec_objective_node`, `exec_last_*`, `exec_squad_ids`, `exec_watchdog_*`, `exec_last_report` | **Mission-owned transient** (AIPlayerState) | Yes while mission live | No | Watchdog can refresh/fallback active mission only |
| `_main_army_cache`, `_combat_units_cache_frame`, `_cached_offensive_wave_units*` | **Frame-local cache** (EAC static) | No (frame key) | No (explicit clear) | Read-only discovery; not authoritative |
| `_creep_contest_cooldowns` | Match-owned durable (**still EAC static**) | Yes | No (reset clears) | Yes (blocks contest) — next slice |
| `_objective_*_timer`, `_objective_last_building_health`, `_objective_eval_*` | Mission-owned transient (**still EAC static**) | Yes while wave objective | No | Influences reissue/unstick |
| `_last_issued_order_*`, `_perf_*`, `_orders_issued_since_diag`, `_debug_enabled_override` | **Debug/telemetry** | Yes | Cleared / session | Diagnostics only |
| `_bound_player_state`, `_declared_command_authority`, `_unbound_runtime` | Binding / offline host | Session | Unbind resets host | Wiring only |

### 2026-08-05 — Wave/formation/finishing SoT + aggression intents + arbitration TTL (PHASE 2 #2/#4)

| Field | Detail |
|---|---|
| **Audit phase** | PHASE 2 — Architecture |
| **Related issues** | (1) Classify remaining EAC static bags. (2) Migrate highest-risk bags: threat TTL caches, reinforcement pool, pending group orders, exec watchdog/scratch. (3) Prove frame-local caches stay frame-local. |
| **Classification of remaining EAC static state (post-migration)** | See table below. |
| **State migrated → `AIPlayerState`** | `pending_group_orders`, `issuing_group_order_batch`, `reinforcement_pool`, `defense_threat_cache` (+ msec), `emergency_threat_cache` (+ msec), `exec_objective_node`, `exec_last_progress_msec`, `exec_last_distance`, `exec_squad_ids`, `exec_watchdog_timer`, `exec_watchdog_refreshed`, `exec_last_report`. EAC names are `_rt()` accessors — no dual authoritative copy. |
| **Frame-local (kept on EAC static; cleared on reset; never SoT)** | `_main_army_cache`, `_combat_units_cache_frame`, `_cached_offensive_wave_units` (+ frame), `_last_combat_eval_msec`. Seeded + asserted empty after `prepare_new_match`. |
| **Command queue owner** | Match-owned `AIPlayerState.pending_group_orders`. Drained by `ArmyCommanderV2` via `EnemyArmyCommand.tick_group_order_batch`. |
| **Remaining compatibility mirrors** | None for migrated bags (accessors only). `_sync_player_state_identity` remains a documented no-op. |
| **Remaining EAC static (not migrated this slice)** | `_creep_contest_cooldowns` (match-durable), objective stuck/eval timers (mission-transient), `_debug_enabled_override` + perf/order-issue diagnostics (telemetry). |
| **EnemyArmyCommand ready for scoped extraction?** | **Not yet.** High-risk runtime bags are match-owned, but creep-contest + objective timers + the ~7k-line facade remain. First extraction only after leftovers are non-authoritative / classified. |
| **Files changed** | `ai_player_state.gd`, `enemy_army_command.gd`, `verify_match_composition_root.gd`, `docs/MILITARY_AI_V2.md`, `AUDIT_PROGRESS.md` |
| **Validation result** | Godot 4.7 `--import` clean. `validate_import.sh` → `VALIDATION PASS`. `verify_match_composition_root` → `PASS` (queue/reset, reinforcement owner, watchdog non-reactivation, frame caches, providers no orders). `verify_match_reset` → `PASS` (registry=27). `verify_freed_instance_regression` → `PASS`. |
| **Next audit task** | Remaining low-risk EAC statics, then first scoped helper extraction — do not start broad god-object splits. |

#### Remaining EnemyArmyCommand static classification (2026-08-05)

| Group (exact vars) | Class | Survives strategic tick? | Survives match reset? | Issues / influences orders? |
|---|---|---|---|---|
| Identity/exec/combat/wave/formation/finishing via `_rt()` | **Match-owned durable** (AIPlayerState) | Yes | No (reset clears) | Yes (mission/mode) |
| `pending_group_orders`, `issuing_group_order_batch` | **Command queue** (AIPlayerState) | Yes until drained | No | Yes (enqueued unit orders) |
| `reinforcement_pool` | **Match-owned durable** (AIPlayerState) | Yes | No | Yes (hold/rally eligibility) |
| `defense_threat_cache*`, `emergency_threat_cache*` | **TTL scratch on AIPlayerState** (not SoT) | Brief TTL (~0.35s) | No | Influences defense scoring only; recomputed from world |
| `exec_objective_node`, `exec_last_*`, `exec_squad_ids`, `exec_watchdog_*`, `exec_last_report` | **Mission-owned transient** (AIPlayerState) | Yes while mission live | No | Watchdog can refresh/fallback active mission only |
| `_main_army_cache`, `_combat_units_cache_frame`, `_cached_offensive_wave_units*` | **Frame-local cache** (EAC static) | No (frame key) | No (explicit clear) | Read-only discovery; not authoritative |
| `_creep_contest_cooldowns` | Match-owned durable (**still EAC static**) | Yes | No (reset clears) | Yes (blocks contest) — next slice |
| `_objective_*_timer`, `_objective_last_building_health`, `_objective_eval_*` | Mission-owned transient (**still EAC static**) | Yes while wave objective | No | Influences reissue/unstick |
| `_last_issued_order_*`, `_perf_*`, `_orders_issued_since_diag`, `_debug_enabled_override` | **Debug/telemetry** | Yes | Cleared / session | Diagnostics only |
| `_bound_player_state`, `_declared_command_authority`, `_unbound_runtime` | Binding / offline host | Session | Unbind resets host | Wiring only |

### 2026-08-05 — Wave/formation/finishing SoT + aggression intents + arbitration TTL (PHASE 2 #2/#4)

| Field | Detail |
|---|---|
| **Audit phase** | PHASE 2 — Architecture |
| **State migrated** | Attack-wave bag, formation/group-order cache, finishing/endgame, plus prior identity/exec/combat/assembly — all owned by match `AIPlayerState`. `EnemyArmyCommand` static names are property accessors into `_rt()` (bound state, or private unbound host offline). |
| **Old authority** | Dual-write sync removed for migrated bags (`_sync_player_state_identity` is a documented no-op). No second live authoritative copy while bound. |
| **Remaining static EnemyArmyCommand state** | Ephemeral/frame caches: `_main_army_cache`, combat/wave unit frame caches, `_pending_group_orders`, objective stuck timers, threat caches, `_creep_contest_cooldowns`, `_reinforcement_pool`, exec watchdog/squad-id/objective-node scratch, order-issue diagnostics, `_issuing_group_order_batch`. |
| **Intent providers completed** | Defense / creep / wave (prior) + **EnemyAggression** as first-class publisher (`ATTACK` / `FINISH` / `SUSPEND_CREEP`). Wave no longer duplicates aggression scoring intents. |
| **Arbitration behavior** | Intents carry explicit priority, TTL (`DEFAULT_TTL_MSEC`), cancel flag, and `mission_owner=ArmyCommanderV2`. Bus purges expired/cancelled. Director filters non-actionable / wrong owner, accepts ownership for DEFEND/offense interrupts, clears accepted intent on leave-DEFEND / expiry. Providers still issue no unit orders under V2. |
| **Files changed** | `ai_player_state.gd`, `military_intent.gd`, `enemy_army_command.gd`, `enemy_aggression.gd`, `enemy_wave_manager.gd`, `military_director_v2.gd`, `verify_match_composition_root.gd`, `AUDIT_PROGRESS.md` |
| **Validation result** | Godot 4.7 `--import` clean. `validate_import.sh` → `VALIDATION PASS`. `verify_match_composition_root` → `PASS` (SoT reset + TTL/cancel + authority). `verify_match_reset` → `PASS` (registry=27). `verify_freed_instance_regression` → `PASS`. |
| **Next audit task** | Remaining EAC static ephemerals → AIPlayerState, or first scoped god-object split after ownership is complete. |

### 2026-08-05 — Exec/combat AIPlayerState mirrors + MilitaryIntent providers (audit PHASE 2 #2 / #4)

| Field | Detail |
|---|---|
| **Audit phase** | PHASE 2 — Architecture |
| **Related issues covered** | (1) Continue replacing EnemyArmyCommand static match state with match-owned `AIPlayerState` mirrors — executable mission + combat runtime (assembly / retreat / fight / rebuilding / player army memory / hostile engagement). (2) Convert wave/creep/defense into intent-only providers under V2 (roadmap #4). (3) Director consumes intents for DEFEND / offense interrupt / early-creep arbitration. |
| **Exact change** | Expanded `AIPlayerState` with exec + combat mirrors and a `MilitaryIntent` bus (`publish` / `consume` / peek). `EnemyArmyCommand` dual-writes the new fields via `_sync_player_state_identity`. New `MilitaryIntent` DTO. Under V2, `EnemyDefenseManager` / `EnemyCreepManager` / `EnemyWaveManager` publish intents instead of early-returning idle. `MilitaryDirectorV2` drains the bus each strategic tick. Composition verify covers exec/combat sync + intent bus. |
| **Not done (intentional)** | Attack-wave / formation / finishing / threat-cache statics still on `EnemyArmyCommand`. Aggression remains a static scorer (wave provider wraps its scores). Providers do not yet own camp/target selection end-to-end — director still selects camps/objectives. |
| **Files changed** | `scripts/systems/military_intent.gd`, `scripts/systems/ai_player_state.gd`, `scripts/systems/enemy_army_command.gd`, `scripts/systems/enemy_defense_manager.gd`, `scripts/systems/enemy_creep_manager.gd`, `scripts/systems/enemy_wave_manager.gd`, `scripts/systems/military_director_v2.gd`, `scripts/systems/match_composition_root.gd`, `scripts/debug/verify_match_composition_root.gd`, `docs/MILITARY_AI_V2.md`, `AUDIT_PROGRESS.md` |
| **Validation result** | Godot 4.7 headless `--import`: registered `MilitaryIntent` + updated classes. `verify_match_composition_root.tscn` → `PASS`. `verify_match_reset.tscn` → `PASS` (registry=27). `verify_freed_instance_regression.tscn` → `PASS`. |
| **Next audit task** | PHASE 2 continued — migrate wave/formation/finishing static caches; optionally make EnemyAggression a direct intent publisher; defer god-object file splits. |

### 2026-08-05 — Match composition root + AIPlayerState + command authority (audit PHASE 2 #1–#3)

| Field | Detail |
|---|---|
| **Audit phase** | PHASE 2 — Architecture |
| **Related issues covered** | (1) Match-owned composition root on `MatchSystems`. (2) Instantiated `AIPlayerState` for army/strategic identity (replaces pure-static lifetime for those fields). (3) Declared sole military command authority (`ArmyCommanderV2` under V2). |
| **Exact change** | `MatchCompositionRoot` resolves match systems, owns/binds `AIPlayerState`, declares authority, and binds `EnemyArmyCommand`. Identity writers sync into the match-owned state; scene exit unbinds. Director/commander/strategic director prefer composition lookup. CI runs `verify_match_composition_root.tscn`. |
| **Not done (intentional)** | Remaining ~90 EnemyArmyCommand static caches (waves, formation caches, etc.) still static — next migration slices. Legacy managers still exist for helpers / V2-off switch; they remain gated from issuing main-army orders under V2. |
| **Files changed** | `scripts/systems/match_composition_root.gd`, `scripts/systems/ai_player_state.gd`, `scenes/match/match_systems.tscn`, `scripts/systems/enemy_army_command.gd`, `scripts/systems/army_commander_v2.gd`, `scripts/systems/military_director_v2.gd`, `scripts/systems/enemy_strategic_director.gd`, `scripts/systems/match_bootstrap.gd`, `scripts/debug/verify_match_composition_root.gd`, `scenes/debug/verify_match_composition_root.tscn`, `scripts/ci/validate_import.sh`, `docs/MILITARY_AI_V2.md`, `AUDIT_PROGRESS.md` |
| **Validation result** | Godot 4.7 headless: `verify_match_composition_root.tscn` → `PASS`; `verify_match_reset.tscn` → `PASS` (registry=27); `verify_freed_instance_regression.tscn` → `PASS`. Import registered new global classes. |
| **Next audit task** | PHASE 2 #2 continued — migrate more EnemyArmyCommand static match state into AIPlayerState; then #4 intent providers. |

### 2026-08-05 — Crash/freed-instance regression suite (audit PHASE 1 #5 / #22 related)

| Field | Detail |
|---|---|
| **Audit phase** | PHASE 1 — Project Stability |
| **Related issues covered** | (1) Orders with freed attack/queue targets. (2) Construction: destroy + raw `queue_free` must release workers/slots. (3) Hero casting / targeting / move-to-cast with freed targets + match restart clearing stale refs. |
| **Bugs found and fixed** | `Building._exit_tree` did not release construction slots or notify builders on raw free. `HeroAbilityTargetingController._process` left armed definition after hero free because `is_targeting()` went false before cancel. Hero kit casts used `target is Node3D` on freed Variants (throws in Godot 4.7) — fixed in paladin E/R, assassin Q/R, ranger bolt aim, splash position resolve. Worker `face_work_target` no longer `look_at` coincident positions. |
| **Exact change** | Added `verify_freed_instance_regression.tscn` (8 scenarios). `ConstructionReservations.has_build_slot_owners_for_id` diagnostic. CI `validate_import.sh` runs the suite after match-reset smoke and requires `PASS freed_instance_regression`. |
| **Files changed** | `scripts/debug/verify_freed_instance_regression.gd`, `scenes/debug/verify_freed_instance_regression.tscn`, `scripts/base/building.gd`, `scripts/systems/construction_reservations.gd`, `autoloads/hero_ability_targeting_controller.gd`, `scripts/units/hero.gd`, `scripts/units/shadow_assassin.gd`, `scripts/units/ranger.gd`, `scripts/systems/splash_damage.gd`, `scripts/units/worker.gd`, `scripts/ci/validate_import.sh`, `AUDIT_PROGRESS.md` |
| **Validation result** | Godot 4.7 headless: `verify_freed_instance_regression.tscn` → `PASS`; `verify_match_reset.tscn` → `PASS` (registry=27). Import clean. |
| **Remaining uncertainty** | Occasional engine `Lambda capture … was freed` on process exit with no GDScript backtrace (not treated as fail). Full `main.tscn` rematch scene-change path still not exercised by this harness. |
| **Next audit task** | PHASE 2 — Create a match-owned composition root (roadmap). Phase 1 leftovers: `GameSettings` Resource TODO; optional separate debug test project (#50). |

### 2026-08-05 — Canonical main scene + clean stale verify artifacts (audit PHASE 1 #4 / #50 / #51)

| Field | Detail |
|---|---|
| **Audit phase** | PHASE 1 — Project Stability |
| **Canonical scene evidence** | `project.godot` `run/main_scene` already = `res://scenes/ui/main_menu.tscn`, matching `MatchSession.MAIN_MENU_SCENE`. Match load is only `MatchSession.MATCH_SCENE` → `res://scenes/main.tscn` via `start_match()` / rematch. Outdated `cursor/AI_CONTEXT.md` incorrectly said F5 runs `main.tscn` — corrected. |
| **Root cause of artifact noise** | Historical headless verify outputs were committed at repo root (audit #51). Three harnesses still wrote `REPORT_FALLBACK` under `res://`, and `verify_terrain_decoration.gd` wrote its report to `res://`, recreating source-tree pollution. Debug scenes were included in `export_filter=all_resources` with empty exclude (audit #50 partial). |
| **Exact change** | Deleted 23 stale root verify/log `.txt` files. `.gitignore` ignores verify output patterns + `.tmp/`. Removed `res://` report fallbacks from `verify_ai_aggression`, `verify_ai_hostile_mission`, `verify_military_ai_v2`; terrain decoration reports to `user://` only. `export_presets.cfg` excludes `scenes/debug/*`, `scripts/debug/*`, `scenes/combat_test.tscn`, and verify log globs. CI `validate_import.sh` asserts menu/match scene constants stay aligned and fails if root verify logs reappear. `MatchSession` documents the two canonical scenes. |
| **Not done (blocker scope)** | Full move of debug harnesses into a separate Godot test project/addon (audit #50 remainder) would be a major packaging rewrite — deferred; export exclusion is the stability-phase fix. |
| **Files changed** | `.gitignore`, `export_presets.cfg`, `scripts/ci/validate_import.sh`, `autoloads/match_session.gd`, `cursor/AI_CONTEXT.md`, 4 verify scripts, 23 deleted root logs, `AUDIT_PROGRESS.md` |
| **Validation result** | Godot 4.7 headless `--import`: clean. `scripts/ci/validate_import.sh`: `VALIDATION PASS` (canonical scene + no-root-logs checks). `verify_match_reset.tscn`: `PASS` (2 lifecycle cycles, registry=27). |
| **Next audit task** | PHASE 1 #5 — Add crash/freed-instance regression tests around orders, construction, hero casting and match restart. |

### 2026-08-05 — Remove obsolete ProjectileManager stub autoload (audit PHASE 1 #3 / #12)

| Field | Detail |
|---|---|
| **Audit phase** | PHASE 1 — Project Stability |
| **Evidence it was safe** | Fresh repo search: `ProjectileManager` / `projectile_manager.gd` appear only in docs, `AUDIT_PROGRESS.md`, and the former `project.godot` line — **zero** `.gd`/`.tscn`/`.tres`/`.yml`/`.sh` callers. Stub is `_ready() → pass` with unused signals; no match state, no `MatchSession` resetter, no preload/NodePath/exported dependency. Live projectiles spawn via unit/scene `PackedScene.instantiate()` (e.g. `ranger.gd` → `ranger_basic_arrow.tscn` / `crossbow_bolt.tscn`); trails/impacts go through `ImpactEffects`. |
| **Exact change** | Removed `ProjectileManager="*res://autoloads/projectile_manager.gd"` from `project.godot`. Kept `autoloads/projectile_manager.gd` as documentation-only placeholder (notes ImpactEffects ownership). No gameplay/projectile scripts touched. |
| **Validation** | Godot 4.7 headless `--import`: clean. `scripts/ci/validate_import.sh`: `VALIDATION PASS`. `verify_match_reset.tscn`: `PASS` (2 lifecycle cycles, registry=27). Post-change search: `ProjectileManager` only in docs/progress (not in `project.godot`). |
| **Remaining partial autoloads** | `GameSettings` — cast-mode API used by `HeroAbilityTargetingController` + `verify_hero_ability_targeting.gd`; settings Resource load still TODO. Not a removable stub. |
| **Next audit task** | PHASE 1 #4 — Establish one canonical main scene and clean test artifacts (audit roadmap item 4). |

### 2026-08-05 — Remove obsolete FogOfWarManager stub autoload (audit PHASE 1 #3 / #12)

| Field | Detail |
|---|---|
| **Audit phase** | PHASE 1 — Project Stability |
| **Complete autoload classification** | See table below (20 registered autoloads after this change). |
| **Exact stub removed** | `FogOfWarManager` registration removed from `project.godot`. Source `autoloads/fog_of_war_manager.gd` kept as documentation-only placeholder (signals + TODO; no runtime registration). |
| **Evidence it was safe** | Repo-wide search of `.gd`/`.tscn`/`.yml`/`.sh`: **zero** callers of `FogOfWarManager` / `fog_of_war_manager` outside docs + former `project.godot` line. Script is `_ready() → pass` only; no match state, no reset registration, no scene dependency. |
| **Root cause** | Production autoload advertised a commercial fog/visibility system that was never implemented, misleading architecture maps and inviting false assumptions. |
| **Files changed** | `project.godot`, `AUDIT_PROGRESS.md` |
| **Validation result** | Godot 4.7 headless `--import`: clean. `scripts/ci/validate_import.sh`: `VALIDATION PASS`. `verify_match_reset.tscn`: `PASS` (2 lifecycle cycles, registry=27). Post-change search: `FogOfWarManager` only in docs/`AUDIT_PROGRESS` (not in `project.godot`). |
| **Remaining stubs** | `ProjectileManager` — confirmed no-op, **0** code refs (next removable). `GameSettings` — partial: real `hero_ability_cast_mode` API used by `HeroAbilityTargetingController` + verify harness; settings Resource TODO still empty — **do not remove** without relocating cast-mode ownership. |
| **Next audit task** | Continue PHASE 1 #3 — unregister unused `ProjectileManager` stub (same evidence pattern). |

#### Autoload classification (verified 2026-08-05)

| Autoload | Classification | Notes |
|---|---|---|
| `GameSettings` | Partial / referenced | Cast-mode getters used; settings Resource load is TODO |
| `ResourceManager` | Active | Player economy; many callers |
| `EnemyResourceManager` | Active | Enemy economy |
| `TechTree` | Active | Unlock gates |
| `UpgradeManager` | Active | Upgrade application + reset |
| `FormationManager` | Active | Full formation authority (~800 lines); not a stub |
| `SharedSquadNavigation` | Active | Squad routing layer |
| `InputManager` | Active | Attack-move/patrol arming + match reset |
| `ControlGroupManager` | Active | Control groups |
| `CommandFeedback` | Active | Order markers/FX |
| `DeathEffects` | Active | Death FX pooling |
| `ImpactEffects` | Active | Impact/trail FX (owns projectile VFX path) |
| `FogOfWarManager` | **Removed (was stub)** | Unregistered; file kept for docs only |
| `ProjectileManager` | **Removed (was stub)** | Unregistered; file kept for docs only |
| `MatchSession` | Active | Match lifecycle + reset registry |
| `EntityRegistry` | Active | Entity indexing |
| `AIHeroMastery` | Active | Hero AI mastery |
| `HeroAbilityTargetingController` | Active | Ability targeting UX |
| `TooltipManager` | Active | Tooltip UI |
| `PerfCounters` | Active (debug) | Perf counters written from hot paths |
| `PerfDebugOverlay` | Active (debug) | Self-owned F3 overlay; gated to debug builds |

### 2026-08-05 — Deterministic match-reset verification + AttackPathDefense reset leak (audit PHASE 1 #2 / #11)

| Field | Detail |
|---|---|
| **Audit phase** | PHASE 1 — Project Stability |
| **Exact leak / stale-state defect** | `EnemyAttackPathDefense` match-scoped static state (`_lane_threat`, `_failed_sites`, `_destroyed_sites`, lane selection metadata) and `EnemyBuildPlacement.preferred_tower_lane` survived `MatchSession.prepare_new_match()`. Reset existed but was only invoked from scene-owned `EnemyStrategicDirector`, which is destroyed on menu/teardown and never runs on the next match bootstrap. |
| **Evidence before the fix** | Strengthened `verify_match_reset.tscn`: after dirtying via `notify_tower_destroyed` / `remember_failed_site` / `set_tower_lane_preference` and calling `prepare_new_match()`, lane threat stayed elevated (`left` 0.2→1.0→1.8 across two cycles) and `preferred_tower_lane` remained `"right"`. Other registered resetters (resources, upgrades, control groups, FX active counts, EntityRegistry) already cleaned. |
| **Root cause** | Match-scoped static defense memory had no `MatchSession` reset owner; scene teardown was incorrectly treated as sufficient. |
| **Fix** | Registered `EnemyAttackPathDefense.reset_match_state` with `MatchSession` (also clears tower lane preference). Extended debug `_verify_clean_match_state` to assert default lane threats + empty preferred lane. Strengthened `verify_match_reset.gd` to capture a pre-match baseline, run two in-process lifecycle cycles, and assert semantic registries / orphan+node monitors. |
| **Files changed** | `autoloads/match_session.gd`, `scripts/debug/verify_match_reset.gd`, `AUDIT_PROGRESS.md` |
| **Validation result** | Godot 4.7 headless `--import`: clean. `verify_match_reset.tscn` ×3 separate processes: each `PASS` with 2 lifecycle cycles (registry=27). `scripts/ci/validate_import.sh`: `VALIDATION PASS`. |
| **Remaining uncertainty** | Absolute `Performance.OBJECT_COUNT` still drifts (~+23/cycle) when CommandFeedback/Death/Impact FX are dirtied; node count and orphan count stay flat and resource monitor stable. Godot does not expose a reliable ObjectDB inventory for attributing those RefCounted/Tween graphs, so they are logged as notes rather than hard fails. Full `main.tscn` load → menu → rematch scene changes are not exercised (would destroy the harness); the harness validates the `prepare_new_match` contract MatchBootstrap uses. RID/navigation map ownership is not directly enumerable via safe public APIs here. |
| **Next audit task** | PHASE 1 #3 — Remove or disable stub autoloads (audit #12). |

### 2026-08-05 — Remove obsolete Quaternius modular worker/ranger candidates (audit PHASE 1 #1)

| Field | Detail |
|---|---|
| **Audit phase** | PHASE 1 — Project Stability |
| **Dead asset root cause** | Unused legacy Quaternius candidate packs shipped FBX/glTF materials that reference missing textures never present in the repo. Primary CI failure: `modular_worker_ranger_candidates` FBXs → `T_Regular_Male_Dark_BaseColor.png` / `T_Regular_Male_Normal.png` (and female/roughness siblings). After that removal, CI/fresh import next exposed unused `props/` (`Anvil`/`Barrel`/`Coin` → missing `T_Trim_Metal_*` / `T_Trim_Furniture_*`) and unused `characters/worker_peasant/` (same missing `T_Regular_Male_*` base textures). No active gameplay scene, unit, worker, ranger, preload, or exported property depended on any of these folders — live units use `ranger_warrior_candidates/Warrior.gltf` and `Ranger.gltf`. |
| **Files removed or repaired** | Deleted unused folders: `characters/modular_worker_ranger_candidates/` (64 files), `props/` (9 files), `characters/worker_peasant/` (18 files). Removed 46 obsolete lines from `assets/art/quaternius/MANIFEST.txt`. Stripped accidental UTF-8 BOM from `scenes/debug/verify_match_reset.tscn` (caused Godot `Parse Error: Expected '['` on fresh import). No scene/material/script replacements required for units. |
| **Validation result** | Repo-wide Quaternius texture URI/FBX scan: zero missing textures. Fresh `.godot` Godot 4.7.stable headless `--import`: zero `Can't open` / `ERROR` / `Parse Error` lines. `scripts/ci/validate_import.sh` → `VALIDATION PASS`. GitHub Actions `godot-import-check` on `c6c7e1f` → **success** ([run 30998409960](https://github.com/nplvkntx/endless-battle/actions/runs/30998409960)). |
| **Next audit task** | PHASE 1 #2 — deterministic match-reset / ObjectDB leak elimination (audit #11). CI gate is green; safe to begin. |

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
| **#10** Navigation verify log parse failures (`UnitNavigation`, `Unit`) | **Outdated** — `scripts/systems/unit_navigation.gd` has `class_name UnitNavigation`; headless verify passes in current tree. Historical `nav_verify_log.txt` removed from source tree 2026-08-05. |
| **#39** AIHeroMastery parser errors | **Resolved** in `6d562aa` (validated 2026-08-05). |
| **#12** Stub autoloads (`GameSettings`, `FogOfWarManager`, `ProjectileManager`) | **Mostly resolved** — `FogOfWarManager` and `ProjectileManager` unregistered 2026-08-05. `GameSettings` remains as partial/referenced (cast-mode API); not a pure stub. |
| **#50** Debug verification scripts in project | **Partially resolved** — release export now excludes `scenes/debug/*` and `scripts/debug/*`. Separate test project deferred (packaging rewrite). |
| **#51** Stored verification logs include stale failures | **Resolved** — root historical logs deleted; gitignore + CI gate + harnesses no longer write `res://` reports. |
| **#22** Excessive validity / weak lifetime ownership | **Partially mitigated** — EntityHandle/NodeSafety paths covered by entity-handle + freed-instance regression suites; full handle adoption still Phase 2. |
| **PHASE 1 #5** Crash/freed-instance regressions | **Resolved** — consolidated suite + CI gate; construction exit_tree + targeting cancel + freed `is` cast crashes fixed. |
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
| 2026-08-05 | Also remove unused `props/` + `worker_peasant/` | Fresh import clean; CI green on `c6c7e1f` |
| 2026-08-05 | GitHub Actions `godot-import-check` (`c6c7e1f`) | **success** |
| 2026-08-05 | Strengthened `verify_match_reset` (2 lifecycle cycles, baseline compare) | `PASS` ×3 processes; registry=27 |
| 2026-08-05 | Register `EnemyAttackPathDefense` match reset | Confirmed leak cleared (lane threat + preferred lane) |
| 2026-08-05 | `validate_import.sh` after PHASE 1 #2 | `VALIDATION PASS` |
| 2026-08-05 | Unregister `FogOfWarManager` stub | Import clean; `validate_import.sh` PASS; `verify_match_reset` PASS |
| 2026-08-05 | Search `FogOfWarManager` after removal | Only docs / progress tracker; not in `project.godot` |
| 2026-08-05 | Unregister `ProjectileManager` stub | Import clean; `validate_import.sh` PASS; `verify_match_reset` PASS |
| 2026-08-05 | Search `ProjectileManager` after removal | Only docs / progress tracker; not in `project.godot` |
| 2026-08-05 | Canonical scenes + remove 23 root verify logs | Import clean; `validate_import.sh` PASS (new gates); `verify_match_reset` PASS |
| 2026-08-05 | Freed-instance regression suite (orders/construction/cast/restart) | `PASS freed_instance_regression`; match reset still PASS |
| 2026-08-05 | Fix Building exit_tree + targeting cancel + freed `is` casts | Confirmed by regression suite (no SCRIPT ERROR) |
| 2026-08-05 | Match composition root + AIPlayerState + ArmyCommanderV2 authority | `PASS match_composition_root`; match reset + freed-instance still PASS |
| 2026-08-05 | Exec/combat mirrors + MilitaryIntent providers (defense/creep/wave) | `PASS match_composition_root` (extended); match reset + freed-instance still PASS |
| 2026-08-05 | Wave/formation/finishing SoT + aggression publisher + intent TTL/ownership | `VALIDATION PASS`; composition/reset/freed all PASS |
| 2026-08-05 | EAC runtime ephemerals (threat/reinforcement/queue/watchdog) + frame-cache proof | `VALIDATION PASS`; composition/reset/freed all PASS |
| 2026-08-05 | EAC final static ownership (creep contest + objective timers; telemetry isolated) | `VALIDATION PASS`; composition/reset/freed all PASS |
| 2026-08-05 | First scoped EAC extraction → `EnemyArmyCommandTelemetry` | `VALIDATION PASS`; composition/reset/freed all PASS |

## Known blockers

None for Phase 1 stability baseline — import CI is green; removable stub autoloads cleared; canonical entry scene enforced; stale root verify logs removed; freed-instance regression gated in CI. Remaining partial: `GameSettings` (referenced). Separate debug test project (#50 remainder) deferred past Phase 1.

Phase 2 military ownership: composition root, AIPlayerState SoT for identity/exec/combat/assembly/wave/formation/finishing **plus** command queue / reinforcement / TTL threat scratch / mission watchdog / creep-contest cooldowns / attack-objective timers, declared `ArmyCommanderV2` authority, intent providers with TTL/cancel/ownership. First scoped EAC extraction complete (`EnemyArmyCommandTelemetry`). Remaining EAC statics are frame-local caches + binding only. Further scoped helper extractions allowed; broad god-object splits still deferred.

## Next task

**PHASE 2 continued:** Second **scoped** `EnemyArmyCommand` helper extraction (order-agnostic military math/scoring) when a clean seam is chosen. Do not begin broad god-object splitting.
