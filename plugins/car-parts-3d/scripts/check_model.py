#!/usr/bin/env python3
"""Check that a car model (.glb or .gltf) and its parts catalog line up one to one.

Usage: python3 check_model.py model.glb catalog.json

Every catalog part with "visible": true (the default) must be a node in the model
named exactly as its id, or carrying extras.part_id equal to its id. Every mesh
node must belong to a catalog part. Exit 0 when they line up, 1 when they don't,
2 when a file cannot be read. Standard library only.
"""
import json
import re
import struct
import sys

BLENDER_DUP = re.compile(r"\.\d{3}$")


def load_gltf(path):
    with open(path, "rb") as f:
        data = f.read()
    if data[:4] == b"glTF":
        magic, version, length = struct.unpack_from("<4sII", data, 0)
        chunk_len, chunk_type = struct.unpack_from("<I4s", data, 12)
        if chunk_type != b"JSON":
            raise ValueError("first GLB chunk is not JSON")
        return json.loads(data[20:20 + chunk_len].decode("utf-8"))
    return json.loads(data.decode("utf-8"))


def main(argv):
    if len(argv) != 3:
        print(__doc__.strip())
        return 2
    try:
        gltf = load_gltf(argv[1])
        with open(argv[2], encoding="utf-8") as f:
            catalog = json.load(f)
    except (OSError, ValueError) as e:
        print(f"cannot read input: {e}")
        return 2

    parts = {p["id"]: p for p in catalog.get("parts", []) if isinstance(p, dict) and "id" in p}
    required = {pid for pid, p in parts.items() if p.get("visible", True)}

    nodes = gltf.get("nodes", [])
    errors, warnings = [], []
    found = {}

    def part_of(n):
        extras = n.get("extras") or {}
        return extras.get("part_id") or n.get("name")

    # A part may be a node with a mesh, or a parent node whose descendants hold the meshes.
    def owner(idx, parent_of):
        while idx is not None:
            pid = part_of(nodes[idx])
            if pid in parts:
                return pid
            idx = parent_of.get(idx)
        return None

    parent_of = {c: i for i, n in enumerate(nodes) for c in n.get("children", [])}

    for i, n in enumerate(nodes):
        name = n.get("name", f"<node {i}>")
        extras = n.get("extras") or {}
        if BLENDER_DUP.search(name):
            errors.append(f"node '{name}': Blender added a .NNN suffix, so two objects wanted the same id; rename one")
        if extras.get("part_id") and n.get("name") and extras["part_id"] != n["name"]:
            warnings.append(f"node '{name}': extras.part_id is '{extras['part_id']}'; keep the name and part_id the same")
        pid = part_of(n)
        if pid in parts:
            if pid in found:
                errors.append(f"part '{pid}' appears on two nodes ('{found[pid]}' and '{name}'); merge them or split the catalog entry")
            found[pid] = name
        if "mesh" in n and owner(i, parent_of) is None:
            errors.append(f"mesh node '{name}' is not a catalog part; add it to the catalog, rename it to a part id, or join it into its part")

    for pid in sorted(required - found.keys()):
        errors.append(f"part '{pid}' ({parts[pid].get('name', '')}) has no node in the model; model it or set \"visible\": false")
    for pid in sorted(found.keys() - required):
        warnings.append(f"part '{pid}' is modeled but marked visible: false in the catalog")

    for e in errors:
        print(f"ERROR   {e}")
    for w in warnings:
        print(f"WARNING {w}")
    print(f"\n{len(found)} of {len(required)} visible catalog parts found in the model; "
          f"{len(errors)} error(s), {len(warnings)} warning(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
