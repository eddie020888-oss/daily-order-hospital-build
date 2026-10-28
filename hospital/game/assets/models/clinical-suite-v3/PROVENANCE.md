# Clinical suite 03 — wide patient chair and runtime thumbnails

The patient chair is sized against the actual P01 seated skin (about 0.80m shoulder/arm silhouette), rather than the old narrow chair's art bounds. Width is 0.940m, inner arm clearance 0.820m; the top remains 0.835m, seat 0.290m, and front/back extents remain -0.246m/+0.240m. Its lateral solid geometry stays within the real one-metre service lane in all four rotations. No actor, animation, simulation cell, navigation, room size, or save field was changed.

Editable source: `E:/CODEX/2026-10-20/医院人物设备整景统一/work/candidates/furniture-03/patient-chair-editable.blend`. Frozen author: `work/build_clinical_furniture_03.py` under the same task. Earlier sources/candidates remain intact.

All six `*-thumbnail.png` files were rendered in Godot from the actual SceneArtLibrary runtime assets, with runtime lighting and the fixed game camera direction. The diagnosis image includes its actual workstation, doctor chair and patient chair; reception includes separate pods with a central gap. These are transparent equipment previews, not concept illustrations or game backgrounds.

Renderer and source/PNG hashes: `E:/CODEX/2026-10-20/医院人物设备整景统一/outputs/设备同源缩略图-03/manifest.json`. Static source/clean reimport: `reports/static-handoff-03.json`. Four-rotation actual-solid checks: `reports/station-clearance-final.log.output.txt`, all under that task.

Art/UI acceptance and Android hardware performance acceptance remain false. Only four character identities currently use the revised simplified style; the other 120 identities still use prior art.
