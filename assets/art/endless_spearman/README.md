# Spearman art pass

Original stylized, medium-detail interpretation of the supplied concept. Rounded
helmet and armour, geometric chainmail, folded team cloth, spear and heater shield.
This is not a photorealistic or sculpted reproduction of the painted reference.

`source/spearman.blend` is editable in Blender 5.2; `spearman.glb` is the game asset.
One skinned mesh, 16 bones, three shared materials; about 17,000 source vertices.
The import settings reuse `worker_post_import.gd` to preserve vertex paint.

Eight clips: Idle, Walk, Run, Attack, AttackSweep, Hit, Guard, Death.
Idle/walk, successful combat strikes, Hold Position and death are connected to
existing gameplay. Run, sweep and hit are available for later combat variation.
Damage, reach, cooldown, collision and navigation are unchanged.

Rebuild from the project root with Blender:
`blender --background --factory-startup --python scripts/art/build_spearman.py`.
The authoring script reuses `build_worker.py` geometry/rig helpers but does not
replace the worker asset.

F6 `scenes/debug/spearman_match_preview.tscn` for a real battlefield demonstration.
`scenes/debug/verify_spearman_art.tscn` checks animation imports, a damaging strike,
red team cloth and the detached death animation.
