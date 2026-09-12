# Endless Battle worker

Original procedural, low-poly interpretation of the supplied worker concept sheet.
The GLB is used by `scenes/units/worker.tscn` for player and enemy workers.

- Editable Blender source: `source/worker.blend` (Blender 5.2).
- Runtime asset: `worker.glb`; 16 bones, four mesh objects, three materials.
- Clips: Idle, Walk, Run, Attack, Chop, Mine, CarryWood, CarryGold,
  CarryWoodIdle, CarryGoldIdle, Build, Repair, Death.
- Blue/red scarf and apron identify the team. Wood and gold cargo are separate
  skinned meshes, shown only on carrying trips.
- WorkerArtVisuals reads existing worker job state. It does not issue orders,
  change movement, resources, combat, collisions, or work timing.
- DeathEffects owns detached animated worker corpses and clears them on match reset.

Idle, walk, chop, mine, carrying, construction and death are wired to existing
gameplay. Run, attack and repair clips are supplied for future gameplay support;
this asset does not give workers new abilities or add a sprint/repair system.

## Rebuild

Run from the project root:

```powershell
& 'C:\Program Files\Blender Foundation\Blender 5.2\blender.exe' --background --factory-startup --python scripts/art/build_worker.py
```

Godot imports the GLB. Its checked-in import settings use
`scripts/art/worker_post_import.gd` to preserve vertex paint and independent team
cloth colours. Blender source is ignored by Godot so it does not import twice.

## Inspect

- F6 on `scenes/debug/worker_art_gallery.tscn`: imported animation gallery.
- F6 on `scenes/debug/worker_match_preview.tscn`: actual battlefield, camera near
  a player worker assigned to the nearest safe tree. The match stays playable.
- `scenes/debug/verify_worker_art.tscn`: clip, job mapping, material, cargo and
  corpse lifecycle assertions.

This is a game-ready first art pass, not a sculpted reproduction of the concept.
The concept image is not embedded in the shipped model.
