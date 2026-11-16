# Car Parts 3D

Claude Code skills for building 3D car models where **every part is its own labeled object, priced at both OEM retail and aftermarket**.

| Skill | Claude uses it when you ask to… |
|---|---|
| `car-parts-catalog` | list or price a car's parts, compare dealer and aftermarket prices, or build a parts bill of materials |
| `car-3d-model` | model a car in Blender, split a downloaded car mesh into parts, or export GLB/glTF/USDZ |
| `car-part-labels` | show the model with labels, price tooltips, totals or an exploded view |

All three are model-invoked: describe the task ("make a labeled, priced 3D model of a 2019 Camry SE") and Claude loads the ones it needs.

## The pipeline

```
catalog.json ──► build_blockout.py ──► car.blend ──► refine in Blender ──► car.glb ──► viewer.html
 (labels +        (one named box         (stamp_part_ids.py       (check_model.py
  both prices)     per part)              audits names)            verifies the match)
```

- **`catalog.json`** is the single source of truth for part names and prices. Each part has `retail` (OEM MSRP) and `aftermarket` (new non-OEM low–high, or `null` with a reason). Each price is either `quoted` (with seller, URL and date) or an `estimate` (with a note). Viewers show an "estimate" badge, so a guess never passes for a quote.
- **The model** holds geometry and ids only. Each object is named by its part id (`body_door_front_lh`) and carries a `part_id` custom property, which becomes glTF extras or USD userProperties.
- Ids use only lowercase letters, digits and underscores, so they survive Blender, glTF, three.js and USD unchanged.

## Scripts

| Script | Needs | Does |
|---|---|---|
| `scripts/validate_catalog.py catalog.json` | Python 3 | Checks ids, the price contract and left/right pairs; prints retail and aftermarket totals by system |
| `scripts/build_blockout.py catalog.json out.glb [out.blend]` | Blender, or `pip install bpy` | One named, positioned blockout object per visible part, with sides mirrored |
| `scripts/stamp_part_ids.py car.blend catalog.json [--save]` | Blender, or bpy | Sets `part_id` on matching objects; lists missing, stray and duplicate objects |
| `scripts/check_model.py car.glb catalog.json` | Python 3 | Confirms the model and catalog match one to one |
| `skills/car-part-labels/viewer.html` | a browser and a static server | three.js viewer: hover tooltips, click for details, labels, parts list with subtotals, totals, explode |

Under Blender, run a script as `blender --background --python script.py -- args`. With the bpy wheel, run `python script.py args`.

## Try it

```bash
cd plugins/car-parts-3d
python3 scripts/validate_catalog.py examples/sample-catalog.json
mkdir -p /tmp/site
python scripts/build_blockout.py examples/sample-catalog.json /tmp/site/model.glb   # Python with bpy
cp examples/sample-catalog.json /tmp/site/catalog.json
cp skills/car-part-labels/viewer.html /tmp/site/index.html
cd /tmp/site && python3 -m http.server 8000
```

The sample catalog is a generic "Example Compact Sedan" with illustrative estimates. Its prices are not quotes.

## Install

```bash
claude plugin marketplace add xlegend768543-arch/DashProfit-iOS
```

```text
/plugin install car-parts-3d@dashprofit-plugins
```

Or from a checkout: `claude --plugin-dir ./plugins/car-parts-3d`.

## Tests

```bash
bash tests/run.sh
```

The Blender steps run when `blender` is on PATH, or when `BPY_PYTHON` points at a Python with bpy installed. Otherwise they are skipped.
