# Endless Battle — Commercial RTS Technical Audit

**Audit basis:** static inspection of the uploaded Godot 4 project archive, repository structure, scripts, scenes, project autoload configuration, verification logs and recent git history. I did **not** have an executable Godot runtime in this environment, so claims about measured frame time are explicitly limited to code evidence and stored logs. A profiler capture is still required before final performance conclusions.

## Executive verdict

This is a serious, ambitious prototype with a real playable loop, but its architecture is not commercially maintainable today. The project has accumulated systems faster than it established ownership boundaries. The worst problem is not a missing feature; it is **multiple systems believing they are responsible for the same state and commands**.

The strongest recent improvement is `EntityRegistry` plus `SharedSquadNavigation`. The problem is that both appear to have been added alongside old discovery and movement paths rather than replacing them. As a result, the project now has more safety layers, more checks and more managers, but not yet a simpler source of truth.

Hard scale evidence:
- **257 GDScript files**, approximately **104,371 lines**.
- Largest production scripts: `enemy_army_command.gd` **7,764**, `build_commands.gd` **5,046**, `enemy_build_manager.gd` **4,250**, `military_director_v2.gd` **3,409**, `worker.gd` **3,124** lines.
- **21 autoloads**, including match gameplay, AI, navigation, UI and debug infrastructure.
- **130** scene-group scans, **71** process callbacks, **51** deferred calls, **23** ad-hoc SceneTree timers, **778** `is_instance_valid` checks.
- Only **1 serialized `.tres/.res` resource**, despite TODO hooks for data-driven stats.

## 1. Architecture diagram

```text
InputManager / ControlGroupManager
              │
              ▼
SelectionManager ───────────────► BuildCommands / SelectionInfoPanel / HUD
              │                              │
              ▼                              ▼
       Unit order APIs ◄──────── Production / Build / Upgrade / Hero commands
              │
      ┌───────┴──────────────────────────────────────────┐
      ▼                                                  ▼
Unit / MilitaryUnit / Worker / Hero actors       FormationManager (autoload)
      │                                                  │
      ├── per-unit navigation / steering                 ├── formation slots
      ├── combat acquisition                             ▼
      └── task state machines                    SharedSquadNavigation (autoload)
                                                         │
                                                         ▼
                                                  per-unit slot orders

EnemyStrategicDirector ─┐
MilitaryDirectorV2 ─────┤
ArmyCommanderV2 ────────┤
EnemyWaveManager ───────┤
EnemyCreepManager ──────┼──► EnemyArmyCommand (static global state + order gate)
EnemyDefenseManager ────┤                    │
EnemyAggression ────────┤                    ▼
AIHeroMastery (autoload)┘              Unit order APIs

EnemyBuildManager ─► EnemyBuildPlacement ─► Worker construction state
EnemyGatherManager ───────────────────────► Worker gathering state

ResourceManager / EnemyResourceManager / TechTree / UpgradeManager
        │                       │
        └──────── globals ──────┴────► gameplay + UI

EntityRegistry exists, but many systems still bypass it via scene-group scans.
MatchSession exists, but substantial match state remains static/global.
```

## 2. Dependency map

| Source | Depends on / controls | Risk |
|---|---|---|
| `BuildCommands` | selection, buildings, queues, upgrades, shop, hero abilities, input | Presentation directly controls most gameplay domains |
| `EnemyArmyCommand` | strategic state, army composition, retreat, attack waves, caches, order authorization | Global god object and hidden temporal coupling |
| `MilitaryDirectorV2`, `ArmyCommanderV2`, wave/creep/defense/aggression managers | same enemy units and missions | Competing authority |
| `FormationManager` + `SharedSquadNavigation` + unit locomotion | movement destinations and formations | Layered navigation and duplicate calculations |
| `EnemyBuildManager` + `EnemyBuildPlacement` + `Worker` | AI construction transaction | Split ownership and recovery loops |
| `EnemyGatherManager` + `Worker` | resource job assignment/execution | Reassignment conflict |
| `TechTree` / `UpgradeManager` | scene entities and UI | Globals coupled to scene topology |
| `EntityRegistry` | indexed entity handles | Correct direction, incomplete adoption |


## 3. Largest risks

1. **Command authority collision:** several AI subsystems and movement systems can affect the same units.
2. **Global/static lifetime:** match state is stored in autoloads and static variables, requiring manual resets.
3. **God objects:** core files are too large to review, test or change safely.
4. **Layered navigation:** shared squad routing has not clearly eliminated per-unit path calculations.
5. **Hot-path discovery:** gameplay systems still scan scene groups instead of relying on indexed data.
6. **Hybrid data architecture:** Resource hooks exist, but balance/content remain code-driven.
7. **Temporal coupling:** deferred calls, timers, signals and pending transitions make behavior order-dependent.
8. **Weak verification gate:** stored logs contain historical parse failures and leaks.

## 4–9. Critical findings by domain

### Runtime safety
The `EntityRegistry`/handle direction is correct, but 778 validity checks show that object lifetime is still not structurally controlled. Static caches, distributed `queue_free`, deferred callbacks and ad-hoc timers create stale-action risk. Stored test output also reports leaked physics bodies, ObjectDB instances and resources.

### Performance
The most likely scaling bottlenecks are repeated scene-group scans, distributed per-actor update callbacks, target acquisition, duplicated navigation work, mass reorders and broad UI polling. These are evidence-backed structural risks, but the exact percentage of frame time remains uncertain until benchmark profiling is run.

### AI
The AI has many sophisticated concepts—strategic state, attack waves, retreat, regroup, creeping, defense, aggression and hero mastery—but they are distributed across overlapping authorities. This explains why adding more logic does not reliably create smarter behavior: each local system can be reasonable while the combined behavior is contradictory.

### Navigation vs Warcraft III
Warcraft III-quality movement is not “one path per unit every frame.” It is hierarchical: group command interpretation, bounded path/corridor work, local slotting/avoidance, stable target ownership and conservative replanning. Endless Battle now has a shared squad layer, but per-unit movement generations, repath timers, worker task navigation, formation logic and recovery heuristics remain. This can produce wobble, stuck recovery loops and frame spikes.

### Gameplay
The main gameplay bottleneck is command consistency. Attack-move, chase, retreat, regroup and hero control span multiple state machines. Until order ownership and resume semantics are explicit, animation/content polish will not make control feel WC3-level.

### UI
`BuildCommands` and `SelectionInfoPanel` are too broad. The UI knows concrete building types, queues, upgrades, shop items and hero abilities, and it polls in `_process`. This architecture directly explains stale-panel regressions and makes every new content type increase UI branching.

### Data architecture
The project should become substantially more data-driven. Unit, building, hero, ability, item, upgrade and AI strategy definitions should be typed Resources validated at startup. Code should implement reusable mechanics; data should select and tune them.

### Recommended professional structure
```text
res://
  app/                 # bootstrap, match composition root, session lifecycle
  simulation/          # fixed tick, entity lifecycle, teams, spatial index
  commands/            # command DTOs, queue, command gateway
  movement/            # squad route, formations, local locomotion, nav adapters
  combat/              # targeting, damage, projectiles, buffs
  economy/             # resources, gathering, construction, production
  ai/
    planning/          # strategic planner, utility scoring
    missions/          # mission definitions and squad leases
    tactical/          # execution controllers
    knowledge/         # visibility-limited blackboard
  content/
    units/ buildings/ heroes/ abilities/ items/ upgrades/ ai_profiles/
  presentation/
    selection/ command_panel/ hud/ minimap/ feedback/
  infrastructure/      # save, settings, telemetry, pooling
  tests/               # separate test scenes and fixtures
```

## 10. Top 100 issues ranked by severity

### 1. [BLOCKER] God-object AI command authority
- **Exact file(s):** `scripts/systems/enemy_army_command.gd`
- **Function(s)/scope:** `file-wide; 7,764 lines, 96 static variables`
- **Root cause / why:** One static class owns strategic state, army modes, retreat, assembly, waves, targeting, caches, order authorization and diagnostics.
- **Impact:** Any change can create hidden state coupling, stale match state and contradictory transitions.
- **Recommended solution:** Replace with one match-scoped AI facade and explicit state-machine services; eliminate static mutable match state.

### 2. [BLOCKER] Multiple competing military authorities
- **Exact file(s):** `enemy_army_command.gd; military_director_v2.gd; army_commander_v2.gd; enemy_wave_manager.gd; enemy_combat_controller.gd; enemy_creep_manager.gd; enemy_defense_manager.gd`
- **Function(s)/scope:** `multiple update/order functions`
- **Root cause / why:** Several systems can decide missions, regroup, attack, retreat or defense. Authority is coordinated by flags rather than ownership.
- **Impact:** Order churn, mode loops, hero separation, attack/retreat oscillation and debugging ambiguity.
- **Recommended solution:** Define exactly one command issuer. Other systems publish intents/threats, never direct unit orders.

### 3. [BLOCKER] UI god object
- **Exact file(s):** `scripts/ui/build_commands.gd`
- **Function(s)/scope:** `file-wide; 5,046 lines; _process near line 408`
- **Root cause / why:** One Control handles building placement, production, cancellation, upgrades, shop, hotkeys, hero abilities, labels and refresh.
- **Impact:** Stale UI, regression blast radius, expensive polling and impossible isolated tests.
- **Recommended solution:** Split by selected-entity presenter: production, construction, upgrades, shop, hero abilities and hotkey router.

### 4. [BLOCKER] Enemy construction god object
- **Exact file(s):** `scripts/systems/enemy_build_manager.gd`
- **Function(s)/scope:** `file-wide; 4,250 lines`
- **Root cause / why:** Planning, prerequisites, affordability, queues, placement, worker assignment, retries and timers are mixed.
- **Impact:** AI economy deadlocks and placement failures become cross-system failures.
- **Recommended solution:** Separate build planner, placement service, construction executor and recovery policy.

### 5. [BLOCKER] Worker god object
- **Exact file(s):** `scripts/units/worker.gd`
- **Function(s)/scope:** `file-wide; 3,124 lines`
- **Root cause / why:** Movement, gathering, delivery, construction, wall jobs, unstuck, navigation and AI reassignment live in one actor.
- **Impact:** Worker bugs corrupt economy, navigation and construction simultaneously.
- **Recommended solution:** Move jobs into explicit worker task objects/components with one task state machine.

### 6. [CRITICAL] Static AI state survives scene lifetime
- **Exact file(s):** `scripts/systems/enemy_army_command.gd`
- **Function(s)/scope:** `reset_match_state() near line 530`
- **Root cause / why:** 96 static variables require manual reset.
- **Impact:** Missed fields can leak state between restarts and tests.
- **Recommended solution:** Make AI state an instantiated Node owned by MatchSession; static helpers must be stateless.

### 7. [CRITICAL] Shared navigation added without removing per-unit navigation
- **Exact file(s):** `scripts/systems/shared_squad_navigation.gd; scripts/base/unit.gd; scripts/units/worker.gd`
- **Function(s)/scope:** `issue_group_command(); request_movement_target(); worker task navigation`
- **Root cause / why:** Squad routing coexists with per-unit agents, repath timers, stuck logic and slot orders.
- **Impact:** The game can still calculate one squad route plus many unit routes and recovery paths.
- **Recommended solution:** Use squad route only for corridor/anchor; local steering must not request independent long paths except fallback.

### 8. [CRITICAL] Runtime group scans in AI hot paths
- **Exact file(s):** `enemy_army_command.gd (20); enemy_build_manager.gd (17); enemy_gather_manager.gd (12); military_director_v2.gd (8)`
- **Function(s)/scope:** `multiple get_nodes_in_group calls`
- **Root cause / why:** Scene-tree scans are repeatedly used despite EntityRegistry existing.
- **Impact:** Cost grows with all scene nodes and multiplies across AI ticks.
- **Recommended solution:** Route all entity queries through indexed registry snapshots and spatial query services.

### 9. [CRITICAL] EntityRegistry adoption is incomplete
- **Exact file(s):** `scripts/systems/entity_registry.gd plus systems still using groups`
- **Function(s)/scope:** `get_registered_ids(); get_nodes_in_group users`
- **Root cause / why:** A registry exists, but old discovery paths remain widespread.
- **Impact:** Two sources of truth, stale membership differences and no guaranteed performance gain.
- **Recommended solution:** Mandate registry for gameplay entities; retain groups only for editor semantics/debug.

### 10. [CRITICAL] Navigation verification log contains compile failures
- **Exact file(s):** `nav_verify_log.txt`
- **Function(s)/scope:** `logged parse errors`
- **Root cause / why:** The stored navigation verification reports unresolved Unit/UnitNavigation types and dependent compile failures.
- **Impact:** Navigation changes were at least once unverified or committed alongside broken validation.
- **Recommended solution:** Run clean headless import and full script parse in CI; reject commits on any parse failure.

### 11. [CRITICAL] Verification logs show leaked objects/resources
- **Exact file(s):** `balance_overhaul_verify_run2.txt`
- **Function(s)/scope:** `exit diagnostics`
- **Root cause / why:** 4 Jolt bodies, 13 ObjectDB instances and 7 resources remained at exit.
- **Impact:** Tests may mask lifetime leaks; repeated matches may accumulate nodes/resources.
- **Recommended solution:** Add teardown assertions, await queued frees, release RIDs, and track object counts before/after match reset.

### 12. [CRITICAL] Autoload stubs are registered as production globals
- **Exact file(s):** `autoloads/game_settings.gd; fog_of_war_manager.gd; projectile_manager.gd`
- **Function(s)/scope:** `_ready/pass or file-level pass`
- **Root cause / why:** Registered globals advertise systems that are TODO/no-op.
- **Impact:** Callers assume functionality that does not exist; architecture map is misleading.
- **Recommended solution:** Remove unused autoloads or implement minimal explicit interfaces and fail-fast diagnostics.

### 13. [CRITICAL] Data-driven architecture is mostly absent
- **Exact file(s):** `project has 1 .tres/.res; base/unit.gd; base/building.gd; base/hero.gd`
- **Function(s)/scope:** `TODO load stats from Resource`
- **Root cause / why:** Stats and behavior remain script constants/exports despite Resource hooks.
- **Impact:** Balance changes require code edits and create unit/building divergence.
- **Recommended solution:** Create typed UnitData, BuildingData, HeroData, AbilityData, UpgradeData and AIProfile resources.

### 14. [CRITICAL] Per-frame UI polling
- **Exact file(s):** `scripts/ui/build_commands.gd`
- **Function(s)/scope:** `_process() near line 408`
- **Root cause / why:** Large command UI refreshes from _process in addition to signals.
- **Impact:** UI work occurs every frame even when selection/resources are unchanged.
- **Recommended solution:** Use dirty flags and event-driven presenters; no broad refresh in _process.

### 15. [CRITICAL] 71 process callbacks fragment scheduling
- **Exact file(s):** `71 _process/_physics_process callbacks across gameplay scripts`
- **Function(s)/scope:** `distributed callbacks`
- **Root cause / why:** Each actor/system owns independent cadence and ordering.
- **Impact:** Unpredictable frame spikes and hard-to-reproduce order dependencies.
- **Recommended solution:** Centralize AI, combat acquisition and maintenance into budgeted tick schedulers.

### 16. [CRITICAL] Order authorization is callback/global-flag based
- **Exact file(s):** `scripts/systems/enemy_army_command.gd`
- **Function(s)/scope:** `with_authorized_orders() near line 880`
- **Root cause / why:** Global authorization state wraps callbacks.
- **Impact:** Nested/deferred calls can bypass or inherit authority incorrectly.
- **Recommended solution:** Pass an explicit CommandContext/token to the only command gateway.

### 17. [CRITICAL] AI transition logic has multiple pending-state layers
- **Exact file(s):** `enemy_army_command.gd`
- **Function(s)/scope:** `request_strategic_state/apply_pending_strategic_transition and attack-wave equivalents`
- **Root cause / why:** Strategic and wave transitions are separately deferred.
- **Impact:** Transitions can observe stale mode and produce oscillation.
- **Recommended solution:** Single hierarchical state machine with atomic transition and entry/exit actions.

### 18. [CRITICAL] Combat strength evaluation is duplicated/centralized in giant static class
- **Exact file(s):** `enemy_army_command.gd`
- **Function(s)/scope:** `estimate_combat_strength; estimate_local_fight_balance`
- **Root cause / why:** Evaluation, observation cache and retreat decisions are tightly coupled.
- **Impact:** Balance tuning can silently alter strategic behavior everywhere.
- **Recommended solution:** Dedicated CombatPowerService with deterministic inputs and tests.

### 19. [CRITICAL] Construction placement and execution are split across oversized coupled systems
- **Exact file(s):** `enemy_build_manager.gd; enemy_build_placement.gd; worker.gd`
- **Function(s)/scope:** `placement/retry/worker build functions`
- **Root cause / why:** Reservations, reachability and worker commitment cross three state machines.
- **Impact:** Ghost reservations, build-from-distance, retry loops and stuck workers.
- **Recommended solution:** Transactional build job: reserve → validate → assign → reach → commit → complete/cancel.

### 20. [CRITICAL] No reproducible profiling evidence for 200+ units
- **Exact file(s):** `project logs and PerfCounters`
- **Function(s)/scope:** `diagnostic infrastructure only`
- **Root cause / why:** The project contains counters, but no attached frame profile, budgets or benchmark scene results.
- **Impact:** Performance conclusions remain partly static, not measured.
- **Recommended solution:** Create deterministic 50/100/200/400-unit benchmark scenes and capture profiler traces.

### 21. [HIGH] EnemyArmyCommand cache invalidation is manual
- **Exact file(s):** `enemy_army_command.gd`
- **Function(s)/scope:** `purge_stale_runtime_caches`
- **Root cause / why:** Static caches need explicit purging.
- **Impact:** Freed/stale handles and inconsistent army membership.
- **Recommended solution:** Registry-driven invalidation and immutable query snapshots.

### 22. [HIGH] Excessive validity checks signal weak lifetime ownership
- **Exact file(s):** `project-wide (778 is_instance_valid calls)`
- **Function(s)/scope:** `many functions`
- **Root cause / why:** Callers defensively probe objects instead of owning handles/lifetimes.
- **Impact:** Noise hides real lifetime bugs and adds branches.
- **Recommended solution:** Use EntityHandle at boundaries and typed ownership contracts.

### 23. [HIGH] Deferred calls in worker lifecycle
- **Exact file(s):** `worker.gd (8 call_deferred)`
- **Function(s)/scope:** `multiple task transitions`
- **Root cause / why:** Task state may change before deferred callback runs.
- **Impact:** Old callbacks act on new jobs or freed targets.
- **Recommended solution:** Generation tokens on deferred work; cancel on task transition.

### 24. [HIGH] UpgradeManager deferred fan-out
- **Exact file(s):** `autoloads/upgrade_manager.gd (6 call_deferred)`
- **Function(s)/scope:** `signal/update paths`
- **Root cause / why:** Global upgrade propagation is deferred and loosely ordered.
- **Impact:** Stats/UI can disagree for a frame or after reset.
- **Recommended solution:** Synchronous domain event with versioned team upgrade state.

### 25. [HIGH] TechTree scans scene groups
- **Exact file(s):** `autoloads/tech_tree.gd (5 group scans)`
- **Function(s)/scope:** `progression queries`
- **Root cause / why:** Global tech state discovers world entities.
- **Impact:** Domain model depends on scene topology and repeated scans.
- **Recommended solution:** TechTree stores authoritative team progression; buildings publish events.

### 26. [HIGH] FormationManager is another global movement authority
- **Exact file(s):** `autoloads/formation_manager.gd (803 lines)`
- **Function(s)/scope:** `formation command functions`
- **Root cause / why:** Formation and SharedSquadNavigation overlap responsibilities.
- **Impact:** Double slotting, duplicate destinations and wobble.
- **Recommended solution:** Merge into one formation/navigation command service.

### 27. [HIGH] Base Unit combines orders, movement, steering and lifecycle
- **Exact file(s):** `scripts/base/unit.gd (1,744 lines)`
- **Function(s)/scope:** `issue_order through movement functions`
- **Root cause / why:** Core actor is too broad and inherited by all units.
- **Impact:** Every unit pays complexity and regressions spread globally.
- **Recommended solution:** OrderQueue, Locomotion, Combatant and Selection components.

### 28. [HIGH] MilitaryUnit adds another large behavior layer
- **Exact file(s):** `scripts/base/military_unit.gd (934 lines)`
- **Function(s)/scope:** `combat/update functions`
- **Root cause / why:** Combat state sits on top of already large Unit.
- **Impact:** Deep inheritance with implicit state interactions.
- **Recommended solution:** Composition with explicit combat state machine.

### 29. [HIGH] Hero class hierarchy duplicates hooks with pass stubs
- **Exact file(s):** `base/hero.gd; units/melee_hero.gd`
- **Function(s)/scope:** `multiple pass methods`
- **Root cause / why:** Subclass contract is implicit and large.
- **Impact:** Missing override silently disables behavior.
- **Recommended solution:** Typed ability/passive components and abstract fail-fast methods.

### 30. [HIGH] SelectionManager is oversized
- **Exact file(s):** `scripts/systems/selection_manager.gd (1,892 lines)`
- **Function(s)/scope:** `selection/input/refresh functions`
- **Root cause / why:** Input, hit testing, selection semantics and UI communication are mixed.
- **Impact:** Selection bugs produce stale command UI and control conflicts.
- **Recommended solution:** Selection model + input adapter + presentation events.

### 31. [HIGH] SelectionInfoPanel is oversized
- **Exact file(s):** `scripts/ui/selection_info_panel.gd (1,547 lines)`
- **Function(s)/scope:** `refresh functions`
- **Root cause / why:** Many entity types are rendered by one panel script.
- **Impact:** Type branches and stale references grow with content.
- **Recommended solution:** Presenter registry per selectable type.

### 32. [HIGH] Enemy gather manager duplicates worker autonomy
- **Exact file(s):** `enemy_gather_manager.gd; worker.gd`
- **Function(s)/scope:** `assignment/recovery functions`
- **Root cause / why:** Manager and worker both decide jobs/recovery.
- **Impact:** Reassignment loops and idle-worker thrashing.
- **Recommended solution:** Manager assigns job; worker executes only; explicit completion/failure events.

### 33. [HIGH] Enemy strategic director overlaps military director
- **Exact file(s):** `enemy_strategic_director.gd; military_director_v2.gd`
- **Function(s)/scope:** `update/state functions`
- **Root cause / why:** Both interpret strategic conditions and priorities.
- **Impact:** Conflicting mission timing and unclear logs.
- **Recommended solution:** One strategic planner producing a single intent stream.

### 34. [HIGH] Legacy wave system remains beside V2 military system
- **Exact file(s):** `enemy_wave_manager.gd; military_director_v2.gd`
- **Function(s)/scope:** `wave/update functions`
- **Root cause / why:** Old wave concepts coexist with mission-based V2.
- **Impact:** Duplicate launches and incompatible readiness gates.
- **Recommended solution:** Delete or adapt legacy wave manager behind one planner interface.

### 35. [HIGH] Aggression subsystem can override normal strategy
- **Exact file(s):** `enemy_aggression.gd; enemy_army_command.gd`
- **Function(s)/scope:** `enter/exit aggression`
- **Root cause / why:** Aggression mode is parallel state rather than strategy parameter.
- **Impact:** Sudden all-in behavior conflicts with retreat/defense.
- **Recommended solution:** Model aggression as utility weights inside planner.

### 36. [HIGH] Emergency defense is embedded in army command
- **Exact file(s):** `enemy_army_command.gd`
- **Function(s)/scope:** `activate/update/deactivate_emergency_defense`
- **Root cause / why:** Defense owns offensive army state directly.
- **Impact:** Base defense can starve all other missions or loop.
- **Recommended solution:** Threat responder requests priority intent; commander arbitrates once.

### 37. [HIGH] Creep manager can compete for the same units
- **Exact file(s):** `enemy_creep_manager.gd; military_director_v2.gd`
- **Function(s)/scope:** `creep mission functions`
- **Root cause / why:** Creeping has its own selection/mission logic.
- **Impact:** Single units or hero can detach from main group.
- **Recommended solution:** Mission allocator leases squads atomically.

### 38. [HIGH] Hero mastery is a global autoload with 1,504 lines
- **Exact file(s):** `scripts/systems/ai_hero_mastery.gd`
- **Function(s)/scope:** `file-wide`
- **Root cause / why:** Hero tactical state is global and large.
- **Impact:** Cross-match state and tight coupling to military AI.
- **Recommended solution:** Per-AI hero controller component owned by AI player.

### 39. [HIGH] AIHeroMastery had recent parser errors
- **Exact file(s):** `ai_hero_mastery_verify_err.txt; latest commit`
- **Function(s)/scope:** `verification/commit evidence`
- **Root cause / why:** Core AI system required parser-error repair.
- **Impact:** High regression rate in oversized script.
- **Recommended solution:** Reduce file and add parse gate/typed tests.

### 40. [HIGH] Direct scene NodePaths in command UI are brittle
- **Exact file(s):** `build_commands.gd lines 5-6`
- **Function(s)/scope:** `exported ../../ paths`
- **Root cause / why:** UI depends on exact scene hierarchy.
- **Impact:** Scene refactors silently break command panel.
- **Recommended solution:** Inject interfaces or resolve via owner composition root.

### 41. [HIGH] Only one serialized Resource file exists
- **Exact file(s):** `project-wide`
- **Function(s)/scope:** `resource count`
- **Root cause / why:** Content is not externalized.
- **Impact:** Commercial-scale balance/content iteration is impractical.
- **Recommended solution:** Resource catalogs plus validation tooling.

### 42. [HIGH] Navigation agent voxel precision warnings
- **Exact file(s):** `construction_verify_log.txt`
- **Function(s)/scope:** `agent_radius warnings`
- **Root cause / why:** Agent radius is quantized by navmesh cell size.
- **Impact:** Clearance differs from configured collision size, causing edge sticking.
- **Recommended solution:** Align navmesh cell size/agent radii and bake profiles per unit class.

### 43. [HIGH] Runtime navmesh source parsing warning
- **Exact file(s):** `construction_verify_log.txt`
- **Function(s)/scope:** `navigation bake warning`
- **Root cause / why:** Navigation source geometry is parsed at runtime.
- **Impact:** Load spikes and nondeterministic startup/build behavior.
- **Recommended solution:** Bake navigation offline or incrementally update bounded obstacle data.

### 44. [HIGH] Squad navigation still issues staggered per-unit slot orders
- **Exact file(s):** `shared_squad_navigation.gd`
- **Function(s)/scope:** `_issue_staggered_slot_orders/_issue_slot_order_for_unit`
- **Root cause / why:** Shared route ends in individual movement orders.
- **Impact:** Can still cause order bursts and local path requests.
- **Recommended solution:** Feed local desired velocity/slot targets without full repath.

### 45. [HIGH] Squad target search is centralized but not spatially indexed
- **Exact file(s):** `shared_squad_navigation.gd`
- **Function(s)/scope:** `_tick_target_search`
- **Root cause / why:** Threat acquisition may still query broad world state.
- **Impact:** Army combat spikes remain at scan intervals.
- **Recommended solution:** Spatial hash/quadtree query with capped candidates.

### 46. [HIGH] Squad stall recovery can trigger mass reorders
- **Exact file(s):** `shared_squad_navigation.gd`
- **Function(s)/scope:** `_recover_stalled_squad`
- **Root cause / why:** Whole squad recovery reacts to aggregate stall.
- **Impact:** One blocked unit can reorder an entire army.
- **Recommended solution:** Separate anchor stall from member lag; recover only affected cohort.

### 47. [HIGH] Worker has separate task navigation stack
- **Exact file(s):** `worker.gd`
- **Function(s)/scope:** `_refresh_task_navigation/_process_task_navigation_movement`
- **Root cause / why:** Worker locomotion bypasses shared base unit path semantics.
- **Impact:** Different stuck behavior and duplicated navigation bugs.
- **Recommended solution:** Common locomotion service with job-specific destination provider.

### 48. [HIGH] Construction repath logic is worker-specific
- **Exact file(s):** `worker.gd`
- **Function(s)/scope:** `_try_repath_construction_movement`
- **Root cause / why:** Construction has bespoke repathing.
- **Impact:** Repath storms during blocked building approaches.
- **Recommended solution:** Shared bounded repath policy and reserved approach slots.

### 49. [HIGH] Timers are created ad hoc in production buildings
- **Exact file(s):** `stable.gd; barracks.gd; command_center.gd`
- **Function(s)/scope:** `create_timer users`
- **Root cause / why:** Queue timing is distributed across scene timers.
- **Impact:** Cancellation/reset and pause behavior can diverge.
- **Recommended solution:** Deterministic production queue ticked by match clock.

### 50. [HIGH] Large debug verification scripts live inside project
- **Exact file(s):** `scripts/debug (39 scripts; one 1,791 lines)`
- **Function(s)/scope:** `verification scenes`
- **Root cause / why:** Tests increase project import surface and may depend on production globals.
- **Impact:** Slow validation and risk of test-only code affecting exports.
- **Recommended solution:** Separate test project/addon and exclude from release exports.

### 51. [HIGH] Stored verification logs include stale failures
- **Exact file(s):** `multiple root txt logs`
- **Function(s)/scope:** `file-wide`
- **Root cause / why:** Repository mixes current code with historical failed outputs.
- **Impact:** Auditors/developers cannot tell current truth.
- **Recommended solution:** CI artifacts outside source tree; latest signed test summary only.

### 52. [MEDIUM] ProjectileManager is a no-op autoload
- **Exact file(s):** `autoloads/projectile_manager.gd`
- **Function(s)/scope:** `file-wide pass`
- **Root cause / why:** Global system exists without implementation.
- **Impact:** False abstraction and dead API surface.
- **Recommended solution:** Remove until implemented or route projectiles through pool service.

### 53. [MEDIUM] FogOfWarManager is a no-op autoload
- **Exact file(s):** `autoloads/fog_of_war_manager.gd`
- **Function(s)/scope:** `_ready pass`
- **Root cause / why:** Commercial RTS visibility is not architecturally present.
- **Impact:** AI/player information rules cannot be validated.
- **Recommended solution:** Authoritative visibility grid queried by both UI and AI knowledge model.

### 54. [MEDIUM] GameSettings is a no-op autoload
- **Exact file(s):** `autoloads/game_settings.gd`
- **Function(s)/scope:** `_ready pass`
- **Root cause / why:** Settings resource is planned but absent.
- **Impact:** Options become scattered constants.
- **Recommended solution:** Typed settings resource loaded once and injected.

### 55. [MEDIUM] Base data loading hooks are empty
- **Exact file(s):** `unit.gd; building.gd; hero.gd`
- **Function(s)/scope:** `_load/apply data TODOs`
- **Root cause / why:** Resource fields exist but do not drive stats.
- **Impact:** Hybrid data/code configuration creates divergence.
- **Recommended solution:** Complete data application and validate all required fields.

### 56. [MEDIUM] Enemy build placement is oversized
- **Exact file(s):** `scripts/systems/enemy_build_placement.gd (2,130 lines)`
- **Function(s)/scope:** `file-wide`
- **Root cause / why:** Geometry, search and policy are combined.
- **Impact:** Placement tuning risks correctness regressions.
- **Recommended solution:** Pure placement query service with bounded candidate generation.

### 57. [MEDIUM] Combat target validation is oversized
- **Exact file(s):** `scripts/systems/combat_target_validation.gd (1,355 lines)`
- **Function(s)/scope:** `file-wide`
- **Root cause / why:** Validation policy is centralized but too broad.
- **Impact:** Target semantics become hard to reason about.
- **Recommended solution:** Small composable filters: faction, visibility, reachability, priority.

### 58. [MEDIUM] Enemy attack path defense is another tactical authority
- **Exact file(s):** `enemy_attack_path_defense.gd (859 lines)`
- **Function(s)/scope:** `update/order helpers`
- **Root cause / why:** Path defense can influence army routing separately.
- **Impact:** Conflicting destinations and detours.
- **Recommended solution:** Publish threat costs into shared route planner.

### 59. [MEDIUM] Enemy combat controller has its own process callback
- **Exact file(s):** `enemy_combat_controller.gd`
- **Function(s)/scope:** `_process/_physics_process`
- **Root cause / why:** Combat controller ticks independently of directors.
- **Impact:** Frame-order-dependent decisions.
- **Recommended solution:** Budgeted AI scheduler with fixed phase order.

### 60. [MEDIUM] Tower logic ticks independently
- **Exact file(s):** `scripts/buildings/tower.gd`
- **Function(s)/scope:** `process callback`
- **Root cause / why:** Each tower can scan/target separately.
- **Impact:** Many towers create synchronized scan spikes.
- **Recommended solution:** Central defense targeting scheduler or staggered buckets.

### 61. [MEDIUM] Minimap updates independently
- **Exact file(s):** `scripts/ui/minimap.gd`
- **Function(s)/scope:** `process callback`
- **Root cause / why:** Potential full-map UI work on frame cadence.
- **Impact:** UI cost scales with unit count.
- **Recommended solution:** Event-driven markers with capped update rate/interpolation.

### 62. [MEDIUM] TooltipManager is an autoload UI global
- **Exact file(s):** `scripts/ui/tooltip_manager.gd`
- **Function(s)/scope:** `process callback`
- **Root cause / why:** Global UI service owns frame processing.
- **Impact:** Scene coupling and difficult teardown.
- **Recommended solution:** HUD-owned tooltip controller.

### 63. [MEDIUM] Perf overlay is a production autoload
- **Exact file(s):** `scripts/debug/perf_debug_overlay.gd`
- **Function(s)/scope:** `autoload registration`
- **Root cause / why:** Debug UI is globally active infrastructure.
- **Impact:** Release overhead and coupling.
- **Recommended solution:** Compile/export feature flag and lazy activation.

### 64. [MEDIUM] Perf counters are global mutable state
- **Exact file(s):** `scripts/debug/perf_counters.gd`
- **Function(s)/scope:** `autoload registration`
- **Root cause / why:** Instrumentation can be called from anywhere.
- **Impact:** Counter semantics drift and reset becomes unclear.
- **Recommended solution:** Typed metric API with frame lifecycle and benchmark exporter.

### 65. [MEDIUM] Team identity likely remains integer-based across systems
- **Exact file(s):** `project-wide team_id use`
- **Function(s)/scope:** `many APIs`
- **Root cause / why:** Raw ints cross domain boundaries.
- **Impact:** Invalid team values and accidental player-centric logic.
- **Recommended solution:** Team/Faction value object and relation service.

### 66. [MEDIUM] Scene groups remain architectural APIs
- **Exact file(s):** `130 get_nodes_in_group calls`
- **Function(s)/scope:** `project-wide`
- **Root cause / why:** Strings define domain membership.
- **Impact:** Renames and missing registration fail at runtime.
- **Recommended solution:** Typed registry categories and startup validation.

### 67. [MEDIUM] StringName/string command identifiers are scattered
- **Exact file(s):** `build_commands.gd and production systems`
- **Function(s)/scope:** `train_id/placement_id/upgrade_id`
- **Root cause / why:** Identifiers are not centrally schema-validated.
- **Impact:** Typos become runtime no-ops.
- **Recommended solution:** Generated catalog IDs from resources with validator.

### 68. [MEDIUM] Production cancellation logic is duplicated by building type
- **Exact file(s):** `build_commands.gd`
- **Function(s)/scope:** `_cancel_barracks/_cancel_stable/_cancel_artillery`
- **Root cause / why:** UI knows concrete queue implementations.
- **Impact:** Every new producer adds UI branches.
- **Recommended solution:** IProductionQueue interface exposed by selected building.

### 69. [MEDIUM] Production refresh logic duplicated by building type
- **Exact file(s):** `build_commands.gd`
- **Function(s)/scope:** `_refresh_*_production_slots`
- **Root cause / why:** Presenter branches per building.
- **Impact:** Stale labels/buttons and high maintenance.
- **Recommended solution:** Generic queue view-model.

### 70. [MEDIUM] Upgrade UI duplicated by system
- **Exact file(s):** `build_commands.gd`
- **Function(s)/scope:** `academy/blacksmith/stable update functions`
- **Root cause / why:** Each upgrade family has bespoke wiring.
- **Impact:** Inconsistent affordability/lock states.
- **Recommended solution:** Generic UpgradeDefinition-driven grid.

### 71. [MEDIUM] Shop UI built directly from gameplay definitions
- **Exact file(s):** `build_commands.gd`
- **Function(s)/scope:** `_build_shop_item_ui`
- **Root cause / why:** UI construction and item domain are coupled.
- **Impact:** Recipe/content changes require UI changes.
- **Recommended solution:** Catalog presenter and reusable item slot scene.

### 72. [MEDIUM] Hero ability input lives in building command panel
- **Exact file(s):** `build_commands.gd`
- **Function(s)/scope:** `_try_cast_hero_ability`
- **Root cause / why:** Unrelated command surfaces share one script.
- **Impact:** Input conflicts and selection-sensitive bugs.
- **Recommended solution:** Dedicated command router and hero command presenter.

### 73. [MEDIUM] Control group, input and selection ownership are split across globals
- **Exact file(s):** `ControlGroupManager; InputManager; SelectionManager`
- **Function(s)/scope:** `input handlers`
- **Root cause / why:** Multiple systems interpret the same events.
- **Impact:** Double handling and focus conflicts.
- **Recommended solution:** Single input command mapper feeding selection/command domains.

### 74. [MEDIUM] Match reset relies on many systems cooperating
- **Exact file(s):** `MatchSession plus static managers`
- **Function(s)/scope:** `reset functions`
- **Root cause / why:** No single ownership tree guarantees teardown.
- **Impact:** Leaks and stale caches across restart.
- **Recommended solution:** Match root owns all match-scoped nodes; deleting root resets state.

### 75. [MEDIUM] Effects have multiple global/pool pathways
- **Exact file(s):** `DeathEffects; ImpactEffects; death_fx_pool; impact_fx_pool`
- **Function(s)/scope:** `spawn/pool functions`
- **Root cause / why:** Overlapping abstractions for effects.
- **Impact:** Leaks, inconsistent pooling and duplicate code.
- **Recommended solution:** One effect service with typed pools and lifecycle metrics.

### 76. [MEDIUM] 367 queue_free calls indicate highly distributed destruction
- **Exact file(s):** `project-wide`
- **Function(s)/scope:** `many functions`
- **Root cause / why:** Many systems destroy nodes directly.
- **Impact:** Use-after-free risk and hard teardown ordering.
- **Recommended solution:** Entity lifecycle service; actors request destruction, owner performs it.

### 77. [MEDIUM] 261 direct signal connections need lifecycle discipline
- **Exact file(s):** `project-wide`
- **Function(s)/scope:** `connect sites`
- **Root cause / why:** Distributed connect/disconnect patterns are difficult to audit.
- **Impact:** Duplicate callbacks after re-entry and stale subscribers.
- **Recommended solution:** Owner-bound signals, one-shot where appropriate, connection helper tests.

### 78. [MEDIUM] 23 ad-hoc SceneTree timers are not centrally paused/reset
- **Exact file(s):** `project-wide`
- **Function(s)/scope:** `create_timer sites`
- **Root cause / why:** Timers can outlive task context or ignore match lifecycle assumptions.
- **Impact:** Callbacks after cancellation/reset.
- **Recommended solution:** MatchClock scheduler with cancellable handles.

### 79. [MEDIUM] 51 deferred calls create temporal coupling
- **Exact file(s):** `project-wide`
- **Function(s)/scope:** `call_deferred sites`
- **Root cause / why:** Correctness depends on end-of-frame ordering.
- **Impact:** Intermittent stale state and hard debugging.
- **Recommended solution:** Explicit command/event queues with generation/version checks.

### 80. [MEDIUM] Base Unit has empty virtual command methods
- **Exact file(s):** `unit.gd lines 285-310`
- **Function(s)/scope:** `command_attack/etc pass`
- **Root cause / why:** Unsupported orders silently do nothing.
- **Impact:** UI/AI may believe order succeeded.
- **Recommended solution:** Return explicit unsupported result or abstract interface segregation.

### 81. [MEDIUM] Movement and combat timing are bucketed per unit
- **Exact file(s):** `unit.gd`
- **Function(s)/scope:** `tick_chase_update_timer/tick_combat_target_scan_timer`
- **Root cause / why:** Actor-local timers distribute work but remain numerous.
- **Impact:** Budget control is approximate and can synchronize.
- **Recommended solution:** Central scheduler assigns fixed per-frame budgets.

### 82. [MEDIUM] Duplicate destination skipping is symptom-level mitigation
- **Exact file(s):** `logs and group command code`
- **Function(s)/scope:** `order dedupe paths`
- **Root cause / why:** Spam is filtered after multiple systems decide the same order.
- **Impact:** CPU spent before skip and underlying authority conflict persists.
- **Recommended solution:** Prevent duplicate producers; command gateway dedupes only as final guard.

### 83. [MEDIUM] AI diagnostics are embedded in behavior code
- **Exact file(s):** `enemy_army_command.gd and enemy_ai_debug.gd`
- **Function(s)/scope:** `debug logging functions`
- **Root cause / why:** Behavior and observability share state.
- **Impact:** Log changes can affect giant files and performance.
- **Recommended solution:** Structured event stream consumed by optional debugger.

### 84. [MEDIUM] AI state labels/reasons are hand-maintained
- **Exact file(s):** `enemy_army_command.gd`
- **Function(s)/scope:** `label/debug functions`
- **Root cause / why:** Parallel enums and string labels drift.
- **Impact:** Misleading diagnostics.
- **Recommended solution:** State objects expose canonical debug metadata.

### 85. [MEDIUM] No explicit simulation tick boundary
- **Exact file(s):** `project-wide`
- **Function(s)/scope:** `mixed _process/_physics_process/timers`
- **Root cause / why:** Gameplay and AI advance on different clocks.
- **Impact:** Variable behavior across FPS and pause states.
- **Recommended solution:** Fixed simulation tick for gameplay; render interpolation separately.

### 86. [MEDIUM] Likely nondeterministic iteration over scene order/dictionaries
- **Exact file(s):** `AI query code`
- **Function(s)/scope:** `group/query loops`
- **Root cause / why:** Selection may depend on insertion/tree order.
- **Impact:** Different outcomes across runs complicate balance tests.
- **Recommended solution:** Sort candidates by stable ID after deterministic scoring.

### 87. [MEDIUM] No clear command latency budget
- **Exact file(s):** `input/selection/unit order stack`
- **Function(s)/scope:** `input to issue_order path`
- **Root cause / why:** Commands traverse UI/global managers and actor queues.
- **Impact:** Perceived sluggishness and inconsistent immediate feedback.
- **Recommended solution:** Measure click-to-ack and click-to-motion; immediate local acknowledgement.

### 88. [MEDIUM] Attack-move spans order, movement and acquisition layers
- **Exact file(s):** `unit.gd; military_unit.gd; squad navigation`
- **Function(s)/scope:** `command_attack_move plus scans`
- **Root cause / why:** No single owner defines interruption/resume semantics.
- **Impact:** Units wobble between path and target, fail to resume, or chase too far.
- **Recommended solution:** Explicit AttackMove state with leash, target lease and resume waypoint.

### 89. [MEDIUM] Hold/patrol support is optional pass-based API
- **Exact file(s):** `unit.gd`
- **Function(s)/scope:** `supports/command methods`
- **Root cause / why:** Capabilities are discovered at runtime.
- **Impact:** Commands silently mismatch units.
- **Recommended solution:** Capability components/interfaces.

### 90. [MEDIUM] Hero control likely inherits army automation conflicts
- **Exact file(s):** `hero classes + AI hero mastery + army systems`
- **Function(s)/scope:** `hero commands`
- **Root cause / why:** Hero can be controlled by strategic, tactical and mastery logic.
- **Impact:** Hero lags, separates or casts during retreat.
- **Recommended solution:** Single hero controller consumes current squad mission and tactical policy.

### 91. [MEDIUM] Economy balance is coupled to AI scripts
- **Exact file(s):** `enemy build/gather/production managers`
- **Function(s)/scope:** `constants and policies`
- **Root cause / why:** AI pacing and game balance are not cleanly separated.
- **Impact:** Balance change breaks AI build order.
- **Recommended solution:** AI strategy references data-driven build goals and economy model.

### 92. [MEDIUM] No formal cheese/threat model
- **Exact file(s):** `strategic/defense systems`
- **Function(s)/scope:** `heuristics`
- **Root cause / why:** Rush, tower, worker harassment and expansion denial are handled ad hoc.
- **Impact:** AI is exploitable by strategies outside scripted cases.
- **Recommended solution:** Threat taxonomy and utility-based response tests.

### 93. [MEDIUM] No visibility/knowledge boundary for AI
- **Exact file(s):** `Fog manager stub + AI world scans`
- **Function(s)/scope:** `group scans`
- **Root cause / why:** AI can potentially access perfect world state.
- **Impact:** Unfair behavior and impossible WC3-like scouting.
- **Recommended solution:** AI blackboard receives only visible/remembered information.

### 94. [MEDIUM] No explicit spatial index for nearby combat queries
- **Exact file(s):** `combat validation/AI scans`
- **Function(s)/scope:** `world candidate searches`
- **Root cause / why:** EntityRegistry indexes category, not position.
- **Impact:** Target search scales poorly with unit count.
- **Recommended solution:** Uniform grid/spatial hash updated on coarse cadence.

### 95. [MEDIUM] Navigation route cache ownership is unclear
- **Exact file(s):** `shared_squad_navigation.gd`
- **Function(s)/scope:** `context route fields`
- **Root cause / why:** Routes live in squad contexts while actors own movement generations.
- **Impact:** Stale routes after obstacle/map changes.
- **Recommended solution:** Route version keyed by nav map revision and destination signature.

### 96. [MEDIUM] Formation width compression is heuristic
- **Exact file(s):** `shared_squad_navigation.gd`
- **Function(s)/scope:** `_estimate_formation_width/_update_passage_compression`
- **Root cause / why:** No robust corridor width/path funnel integration.
- **Impact:** Clumping at chokepoints and oscillation.
- **Recommended solution:** Path corridor analysis and lane/column mode transitions.

### 97. [MEDIUM] Slot assignment can conflict with collision radii
- **Exact file(s):** `shared_squad_navigation.gd`
- **Function(s)/scope:** `_assign_stable_slots`
- **Root cause / why:** Formation geometry may not use per-unit footprint.
- **Impact:** Cavalry/siege overlap or block infantry.
- **Recommended solution:** Footprint-aware packing and role lanes.

### 98. [MEDIUM] Siege handling is only a boolean branch
- **Exact file(s):** `shared_squad_navigation.gd`
- **Function(s)/scope:** `_has_siege`
- **Root cause / why:** Mixed-speed/size squads need more than presence detection.
- **Impact:** Army stretching and cannon blockage.
- **Recommended solution:** Movement classes, speed governor and rear-column reservation.

### 99. [MEDIUM] Worker corner nudge is heuristic recovery
- **Exact file(s):** `worker.gd`
- **Function(s)/scope:** `corner stuck/nudge functions`
- **Root cause / why:** Local oscillation is solved by side nudges.
- **Impact:** Workers can jitter indefinitely around geometry.
- **Recommended solution:** Validated approach points and nav corridor obstacle avoidance.

### 100. [MEDIUM] Construction start range has multiple similarly named checks
- **Exact file(s):** `worker.gd`
- **Function(s)/scope:** `is_in_build_start_range/_is_in_build_start_range`
- **Root cause / why:** Public/private duplicated semantics.
- **Impact:** Callers may use inconsistent thresholds.
- **Recommended solution:** One authoritative function with documented footprint distance.

## Repair roadmap

### PHASE 1 — Project Stability
1. Add clean headless import/parse CI and make any script error fatal. 2. Build a deterministic match-reset test and eliminate leaked ObjectDB/RID/resources. 3. Remove or disable stub autoloads. 4. Establish one canonical main scene and clean test artifacts. 5. Add crash/freed-instance regression tests around orders, construction, hero casting and match restart.

### PHASE 2 — Architecture
1. Create a match-owned composition root. 2. Replace static mutable AI state with instantiated AIPlayerState. 3. Declare one military command authority. 4. Convert wave/creep/defense/aggression systems into intent providers. 5. Split `BuildCommands`, `EnemyBuildManager`, `Worker`, `Unit`, and `SelectionManager`. 6. Complete EntityRegistry adoption. 7. Introduce explicit domain events and cancellable task generations.

### PHASE 3 — Performance
1. Build 50/100/200/400-unit benchmark scenes. 2. Capture profiler traces and define budgets. 3. Remove scene-group scans from hot paths. 4. Add spatial indexing. 5. Centralize/stagger AI and combat ticks. 6. Convert UI to dirty/event-driven refresh. 7. Measure allocations/order counts/repaths per second.

### PHASE 4 — Navigation
1. Decide one movement architecture. 2. Use one shared squad corridor/anchor path. 3. Keep per-unit movement local only. 4. Merge formation and squad-navigation ownership. 5. Implement footprint-aware slot packing, speed classes and chokepoint column compression. 6. Replace heuristic nudges with validated approach slots and bounded fallback. 7. Tune navmesh voxel/cell sizes against unit radii.

### PHASE 5 — AI
1. Implement one hierarchical planner/state machine. 2. Add atomic squad leases. 3. Separate strategic intent from tactical execution. 4. Introduce visibility-limited AI knowledge. 5. Data-drive build orders and difficulty. 6. Add deterministic scenario tests: rush, tower defense, worker harassment, expansion denial, retreat, creep-to-level-3, regroup and finishing.

### PHASE 6 — Gameplay
1. Formalize order semantics and acknowledgement. 2. Rebuild attack-move as an explicit state. 3. Measure command latency. 4. Standardize target leases, chase leash and resume behavior. 5. Componentize hero abilities and production queues. 6. Fix selection/command presentation through view-models.

### PHASE 7 — Balance
1. Externalize all stats to typed resources. 2. Create economy/combat simulation tests. 3. Define time-to-kill, income, tech and army-size targets. 4. Add cheese matrix and counters. 5. Tune AI from the same data as player rules.

### PHASE 8 — Content
Only after stability/performance gates pass: additional factions, heroes, items, recipes, buildings, creeps and maps. Every new content type must require data creation, not new branches in god scripts.

### PHASE 9 — Polish
Audio/visual feedback, animation, fog-of-war presentation, accessibility, settings, save/replay support, onboarding, robust export pipeline, platform QA and long-match soak tests.


## Subsystem scores

| Area | Score | Brutal assessment |
|---|---:|---|
| Architecture | **2.5/10** | Functional prototype architecture, not shippable studio architecture. God objects and overlapping authorities dominate. |
| AI | **3.5/10** | Ambitious and feature-rich, but too many controllers and state layers make behavior fragile and difficult to prove. |
| Navigation | **3.0/10** | Shared squad routing is a promising patch, but it coexists with per-unit pathing and heuristic recovery. |
| Performance | **3.0/10** | Instrumentation exists, but broad scans, distributed ticks, layered navigation and no 200+ unit benchmark prevent confidence. |
| Gameplay | **5.0/10** | A meaningful playable RTS loop exists. Responsiveness and combat consistency are held back by systems architecture. |
| Maintainability | **2.0/10** | 104k GDScript lines, several 3k–8k-line files, minimal data resources, and high temporal coupling. |
| Commercial readiness | **1.5/10** | Mid-prototype. Not near a reliable public commercial release without a major stabilization/refactor program. |


## Distance from Warcraft III quality

As a complete commercial RTS, this project is approximately **15–25% of the way to Warcraft III-quality engineering and product reliability**, although it may be further along in raw feature count. That percentage is necessarily an informed estimate, not a measurable fact. Warcraft III quality requires not only units, heroes, buildings and AI features, but years of iteration on deterministic rules, movement edge cases, controls, balance, content tooling, replayability, multiplayer-grade state discipline, performance across hardware and enormous QA coverage.

The biggest obstacles are:
1. **One source of truth for commands and state.**
2. **Replacing global/static lifetime with match-owned systems.**
3. **A unified hierarchical movement architecture.**
4. **Measured 200+ unit performance with spatial indexing and fixed budgets.**
5. **Data-driven content and balance tooling.**
6. **Scenario-based AI and gameplay regression testing.**

The project should not be abandoned. It should stop expanding horizontally until the first four roadmap phases are complete. Otherwise every new feature will cost more, break more unrelated systems and push WC3-quality further away rather than closer.
