---
name: car-3d-model
description: Use when creating, building or preparing a 3D model of a car whose parts must be individually selectable, labeled or priced. Covers modeling in Blender, splitting a downloaded or purchased car mesh into separate parts, naming objects, and exporting GLB, glTF or USDZ for a parts viewer, web page or iOS app.
---

# Car 3D model with one object per priced part

## Overview

A car model can only show a label and price for a part if that part is **its own object** whose **name is the part's catalog id**. A single fused body mesh can't be labeled. The model holds geometry and ids only. Names and prices come from `catalog.json` (see the car-parts-catalog skill, which this skill needs first).

**The contract:** every catalog part with `visible: true` maps to exactly one object, the object is named exactly as the id (`body_door_front_lh`), it has a custom property `part_id` with the same value, and every mesh in the file belongs to some part.

## Conventions

| | Blender | Exported glTF / USD |
|---|---|---|
| Units | meters, real size (a compact sedan is about 4.6 m long) | meters |
| Up | +Z | +Y (the glTF exporter converts it) |
| Car front | −Y | +Z (glTF's forward for assets) |
| Driver's side (LH) | +X | +X |
| Origin | ground level, midway between the axles | same |

Put each part's origin where it moves from: doors, hood and trunk at the hinge, wheels at the hub. That keeps open-door and exploded-view animations simple.

## Path A: build from the catalog

1. Write and validate `catalog.json` first.
2. Generate a blockout. You get one correctly named, positioned box per part, with left/right parts mirrored:
   ```bash
   blender --background --python ${CLAUDE_PLUGIN_ROOT}/scripts/build_blockout.py -- catalog.json car.glb car.blend
   ```
   With no Blender install, run it on `pip install bpy` instead (the wheel matches one Python version, e.g. bpy 5.3 needs Python 3.13): `python build_blockout.py catalog.json car.glb car.blend`.
   Parts without a built-in position land in a row beside the car with `placeholder = True`. Move each into place.
3. Refine in Blender: model each part's real shape **inside its existing object** (Tab into Edit Mode), so the name and `part_id` stay. To swap in new geometry, join it into the named object (select the new mesh, then the named object, then Ctrl+J). The active object's name is kept.

## Path B: start from an existing car mesh

Downloaded and purchased models usually come as one shell or as dozens of oddly named pieces. Check the license allows your use, and remember that brand badges and logos are trademarks.

1. **Split**: in Edit Mode, P → *By Loose Parts* (or *By Material*), then select faces and P → *Selection* for panels that are still fused. Cut along the real panel gaps.
2. **Join** fragments that are sold as one part (headlamp lens, housing and reflector → one `lighting_headlamp_lh`) with Ctrl+J.
3. **Apply** mirror modifiers before splitting sides (otherwise left and right are one object), and apply transforms with Ctrl+A → All Transforms.
4. **Rename** each object to its catalog id. Delete or join any leftover pieces.
5. **Stamp and audit**. This sets `part_id` and lists the gaps:
   ```bash
   blender car.blend --background --python ${CLAUDE_PLUGIN_ROOT}/scripts/stamp_part_ids.py -- catalog.json --save
   ```
   Repeat steps 1–5 until it prints no MISSING, STRAY or DUPLICATE lines. A part may also be an empty with child meshes, if the parent is named by id.

## Export and verify

```python
bpy.ops.export_scene.gltf(filepath="car.glb", export_format="GLB",
                          export_extras=True,   # custom properties -> glTF node extras (part_id)
                          export_yup=True, export_apply=True)
```

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/check_model.py car.glb catalog.json
```

It must print 0 errors: every visible part found, no stray meshes, no `.001` names.

**iOS / RealityKit:** `bpy.ops.wm.usd_export(filepath="car.usdc", export_custom_properties=True)` keeps each prim named by id, with `userProperties:part_id`. Look parts up by entity name in RealityKit. Package as `.usdz` with Reality Converter if needed.

## Common mistakes

| Mistake | Result | Fix |
|---|---|---|
| Body as one mesh | Nothing to click or label | Split along panel gaps (Path B step 1) |
| Mirror modifier left unapplied | Left and right parts are one object | Apply it, then separate the sides |
| Two objects named the same | Blender makes `body_hood.001`, and the part won't match | Rename. check_model flags `.NNN` names |
| Names with dots or dashes (`body.hood`) | three.js strips the dots and USD rejects them | Use catalog ids: underscores only |
| Prices or labels stored in the model | Re-pricing means re-exporting | Keep only `part_id`. The viewer reads prices from the catalog |
| Hidden parts modeled in full detail | Heavy file, nothing to see | Mark them `visible: false` in the catalog, or add a simple proxy |
| Exported without `export_extras` | No `part_id` in the GLB | Viewers fall back to node names, so names must still match |
