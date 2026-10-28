# Approved original design reconstruction

Design authority: `E:/CODEX/2026-10-18/Q版医院美术重设计/direction-approved.md` and the unchanged `production-v1/assets/05-base-facilities.png`, `06-treatment-equipment.png`, `01-staff-roster.png`. User approved C character/equipment with A mobile UI. These are original project design images; no Theme Hospital game assets are included.

Six equipment meshes were authored in Blender from these images. Editable sources and authoring script are retained under `E:/CODEX/2026-10-19/医院原稿落地/outputs/editable` and `work/build_reference_equipment.py`. Runtime GLBs retain enamel, brass, upholstery and glass PBR materials. `equipment-thumbnails.png` is rendered from the exact runtime meshes by `tests/render_reference_equipment.gd`; it does not use the concept illustration as a game background.

`ui/approved-staff-roster.png` is an unchanged copy of the approved staff sheet. The welcome guide uses its R01 portrait with the original prototype's 210×210 SVG viewBox. This guide image does not assert that the scene's receptionist model has been rebuilt to match it.

The character samples in the local untracked `characters` directory failed visual review. They are not selected by SceneArtLibrary, not committed as runtime resources, and are explicitly excluded from Android export. The separate TripoSR probe remains in the authoring task outputs and is not a game resource. Existing scene characters remain the older draft models; original character fidelity has not been achieved.

Current equipment reconstruction is an intermediate implementation. Fine sculpting, wear/texture, lighting, actor contact with the apparatus and room furnishing still differ from the approved design. Behavior tests and resource counts do not constitute visual acceptance.
