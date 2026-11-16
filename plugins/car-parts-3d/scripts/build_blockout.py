"""Build a part-separated blockout car in Blender from a parts catalog, and export it as GLB.

Run with Blender:   blender --background --python build_blockout.py -- catalog.json out.glb [out.blend]
or with bpy (pip):  python build_blockout.py catalog.json out.glb [out.blend]

Every visible catalog part becomes one object named exactly as its id, with the
custom property part_id (exported as glTF extras). Paired parts (_lh/_rh,
_fl/_fr, _rl/_rr) are mirrored across the car's centerline. Parts that have no
entry in LAYOUT are put on a row beside the car with placeholder=True so they
can be found and placed by hand. The blockout is the starting point to refine:
replace each box with real geometry and keep the object name.

Conventions: meters, Blender Z up, car front toward -Y, ground at Z=0, origin
between the axles. The driver's left (LH) is +X. In the exported glTF that is
front +Z, up +Y, left +X, which is the glTF spec's orientation for assets.
"""
import json
import math
import sys

import bpy

# id -> (shape, location xyz, size xyz, rotation xyz in degrees)
# Only LH / front-left / rear-left are listed; the other side is mirrored.
# Shapes: "box", or "wheel" (cylinder on the X axis; size = radius, width, unused).
LAYOUT = {
    "body_hood":            ("box", (0.0, -1.62, 0.86), (1.50, 1.00, 0.04), (4, 0, 0)),
    "body_roof":            ("box", (0.0, 0.25, 1.43), (1.30, 1.40, 0.04), (0, 0, 0)),
    "body_trunk_lid":       ("box", (0.0, 1.92, 0.96), (1.46, 0.60, 0.04), (-4, 0, 0)),
    "body_bumper_front":    ("box", (0.0, -2.24, 0.45), (1.78, 0.16, 0.40), (0, 0, 0)),
    "body_bumper_rear":     ("box", (0.0, 2.24, 0.50), (1.78, 0.16, 0.40), (0, 0, 0)),
    "body_grille":          ("box", (0.0, -2.17, 0.70), (0.80, 0.05, 0.16), (0, 0, 0)),
    "body_fender_lh":       ("box", (0.86, -1.55, 0.66), (0.06, 1.20, 0.44), (0, 0, 0)),
    "body_door_front_lh":   ("box", (0.88, -0.32, 0.72), (0.06, 1.10, 0.80), (0, 0, 0)),
    "body_door_rear_lh":    ("box", (0.88, 0.76, 0.72), (0.06, 0.96, 0.80), (0, 0, 0)),
    "body_quarter_panel_lh": ("box", (0.86, 1.66, 0.70), (0.06, 1.00, 0.50), (0, 0, 0)),
    "body_mirror_lh":       ("box", (0.99, -0.78, 1.05), (0.16, 0.10, 0.12), (0, 0, 0)),
    "glass_windshield":     ("box", (0.0, -0.78, 1.17), (1.36, 0.70, 0.02), (-35, 0, 0)),
    "glass_back_window":    ("box", (0.0, 1.30, 1.17), (1.30, 0.60, 0.02), (40, 0, 0)),
    "lighting_headlamp_lh": ("box", (0.60, -2.12, 0.74), (0.42, 0.12, 0.13), (0, 0, 0)),
    "lighting_taillamp_lh": ("box", (0.66, 2.20, 0.86), (0.36, 0.08, 0.12), (0, 0, 0)),
    "wheels_tire_fl":       ("wheel", (0.78, -1.35, 0.33), (0.33, 0.22, 0), (0, 0, 0)),
    "wheels_tire_rl":       ("wheel", (0.78, 1.35, 0.33), (0.33, 0.22, 0), (0, 0, 0)),
    "wheels_wheel_fl":      ("wheel", (0.79, -1.35, 0.33), (0.22, 0.23, 0), (0, 0, 0)),
    "wheels_wheel_rl":      ("wheel", (0.79, 1.35, 0.33), (0.22, 0.23, 0), (0, 0, 0)),
    "brakes_rotor_fl":      ("wheel", (0.64, -1.35, 0.33), (0.15, 0.03, 0), (0, 0, 0)),
    "brakes_rotor_rl":      ("wheel", (0.64, 1.35, 0.33), (0.14, 0.03, 0), (0, 0, 0)),
}
MIRROR = {"_rh": "_lh", "_fr": "_fl", "_rr": "_rl"}

# One material per system so the blockout reads at a glance.
SYSTEM_COLORS = {
    "body": (0.55, 0.06, 0.06, 1), "glass": (0.55, 0.70, 0.80, 0.35),
    "lighting": (0.95, 0.92, 0.75, 1), "wheels": (0.06, 0.06, 0.06, 1),
    "brakes": (0.45, 0.45, 0.47, 1), "trim": (0.10, 0.10, 0.10, 1),
}
DEFAULT_COLOR = (0.6, 0.6, 0.6, 1)


def resolve(pid):
    """Return (layout, mirrored) for a part id, mirroring right-side parts from the left."""
    if pid in LAYOUT:
        return LAYOUT[pid], False
    for right, left in MIRROR.items():
        if pid.endswith(right) and pid[: -len(right)] + left in LAYOUT:
            return LAYOUT[pid[: -len(right)] + left], True
    # Tires are named per corner, so wheels_tire_fr resolves through the _fr rule above.
    return None, False


def material_for(system):
    name = f"mat_{system}"
    mat = bpy.data.materials.get(name)
    if mat:
        return mat
    mat = bpy.data.materials.new(name)
    rgba = SYSTEM_COLORS.get(system, DEFAULT_COLOR)
    mat.diffuse_color = rgba
    try:
        mat.use_nodes = True  # deprecated (always on) in newer Blender; harmless
    except AttributeError:
        pass
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = rgba
        bsdf.inputs["Alpha"].default_value = rgba[3]
        bsdf.inputs["Roughness"].default_value = 0.35 if system in ("body", "glass") else 0.6
    if rgba[3] < 1:
        mat.surface_render_method = "BLENDED"
    return mat


def collection_for(system):
    name = f"sys_{system}"
    col = bpy.data.collections.get(name)
    if not col:
        col = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(col)
    return col


def make_object(pid, shape, loc, size, rot):
    if shape == "wheel":
        bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=size[0], depth=size[1],
                                            location=loc, rotation=(0, math.radians(90), 0))
    else:
        bpy.ops.mesh.primitive_cube_add(size=1, location=loc,
                                        rotation=tuple(math.radians(r) for r in rot))
        bpy.context.object.scale = size
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj = bpy.context.object
    obj.name = pid
    obj.data.name = pid
    return obj


def main(argv):
    args = argv[argv.index("--") + 1:] if "--" in argv else argv[1:]
    if len(args) < 2:
        print(__doc__)
        sys.exit(2)
    catalog_path, out_glb = args[0], args[1]
    out_blend = args[2] if len(args) > 2 else None
    with open(catalog_path, encoding="utf-8") as f:
        catalog = json.load(f)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    unplaced = []
    for part in catalog["parts"]:
        if not part.get("visible", True):
            continue
        pid, system = part["id"], part["system"]
        layout, mirrored = resolve(pid)
        if layout:
            shape, loc, size, rot = layout
            if mirrored:
                loc = (-loc[0], loc[1], loc[2])
                rot = (rot[0], -rot[1], -rot[2])
        else:
            shape, size, rot = "box", (0.25, 0.25, 0.25), (0, 0, 0)
            loc = (2.5, -2.0 + 0.4 * len(unplaced), 0.125)
            unplaced.append(pid)
        obj = make_object(pid, shape, loc, size, rot)
        obj["part_id"] = pid
        if pid in unplaced:
            obj["placeholder"] = True
        obj.data.materials.append(material_for(system))
        for col in list(obj.users_collection):
            col.objects.unlink(obj)
        collection_for(system).objects.link(obj)
        if obj.name != pid:
            raise RuntimeError(f"Blender renamed {pid} to {obj.name}; ids must be unique")

    if out_blend:
        bpy.ops.wm.save_as_mainfile(filepath=out_blend)
    bpy.ops.export_scene.gltf(filepath=out_glb, export_format="GLB",
                              export_extras=True, export_yup=True, export_apply=True)
    print(f"exported {out_glb}")
    if unplaced:
        print(f"{len(unplaced)} part(s) need placing by hand (beside the car, placeholder=True): "
              + ", ".join(unplaced))


if __name__ == "__main__":
    main(sys.argv)
