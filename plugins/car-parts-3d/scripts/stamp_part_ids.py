"""Stamp part ids on the objects of an open Blender file and report what doesn't match the catalog.

Run inside Blender (Scripting tab, or headless):
    blender car.blend --background --python stamp_part_ids.py -- catalog.json [--save]
or with bpy (pip):
    python stamp_part_ids.py car.blend catalog.json [--save]

For every mesh object whose name is a catalog id, sets the custom property
part_id (exported to glTF extras and USD userProperties) and names its mesh
data the same. Prints the catalog parts with no object and the mesh objects
that aren't parts, so you know what to rename, join or separate next.
"""
import json
import re
import sys

import bpy

DUP = re.compile(r"\.\d{3}$")


def main(argv):
    args = argv[argv.index("--") + 1:] if "--" in argv else argv[1:]
    if args and args[0].endswith(".blend"):
        bpy.ops.wm.open_mainfile(filepath=args.pop(0))
    if not args:
        print(__doc__)
        sys.exit(2)
    with open(args[0], encoding="utf-8") as f:
        catalog = json.load(f)
    parts = {p["id"]: p for p in catalog["parts"]}
    wanted = {pid for pid, p in parts.items() if p.get("visible", True)}

    stamped, strays, dups = set(), [], []
    for obj in bpy.data.objects:
        if obj.type != "MESH":
            continue
        if DUP.search(obj.name):
            dups.append(obj.name)
        if obj.name in parts:
            obj["part_id"] = obj.name
            if obj.data.users == 1:
                obj.data.name = obj.name
            stamped.add(obj.name)
        elif not (obj.parent and obj.parent.name in parts):
            strays.append(obj.name)

    print(f"stamped {len(stamped)} of {len(wanted)} visible parts")
    for pid in sorted(wanted - stamped):
        print(f"MISSING  {pid}  ({parts[pid]['name']})")
    for name in sorted(strays):
        print(f"STRAY    {name}  (rename to a part id, join into its part, or parent it to one)")
    for name in sorted(dups):
        print(f"DUPLICATE {name}  (two objects wanted the same name)")
    if "--save" in args:
        bpy.ops.wm.save_mainfile()
        print("saved")


if __name__ == "__main__":
    main(sys.argv)
