---
name: car-part-labels
description: Use when displaying a 3D car model with part labels, hover tooltips, price callouts, retail vs aftermarket price comparisons, repair cost totals or an exploded view, in a browser, three.js, React Three Fiber, SceneKit or RealityKit.
---

# Labeled, priced car model viewer

## Overview

The viewer joins a part-separated model (`model.glb`, from the car-3d-model skill) to `catalog.json` (from the car-parts-catalog skill) by part id, and shows each part's name, OEM retail price and aftermarket range. All text and prices come from the catalog at runtime. None are written into the viewer or the model.

## Use the bundled viewer

[viewer.html](viewer.html) is a complete single-file three.js viewer (three@0.170.0 from jsDelivr):

```bash
cp ${CLAUDE_PLUGIN_ROOT}/skills/car-part-labels/viewer.html site/index.html
cp car.glb site/model.glb
cp catalog.json site/catalog.json
cd site && python3 -m http.server 8000
```

Then open `http://localhost:8000/` (or `?model=x.glb&catalog=y.json`), or drop both files onto the page. Opening it from `file://` won't work, because browsers block `fetch` there.

What it does:
- **Hover** a part: highlight plus a tooltip with name, retail and aftermarket range.
- **Click** a part: a detail panel with OEM part number, both prices, grade, brands, savings %, an `estimate` badge, and source links with checked-on dates.
- **Labels**: shown on hover by default. *All* modes pin a label to every part's center.
- **Parts list** grouped by system with subtotals, plus search by name, id, OEM number or brand.
- **Totals**: retail vs aftermarket range and savings %, plus notices for estimates, catalog parts missing from the model, and meshes missing from the catalog.
- **Explode** slider: pushes parts outward from the car's center.
- Light and dark themes, and a stacked layout on phones.

## Label and price contract

When you build your own viewer, or port this one to React Three Fiber or RealityKit, keep these rules:

1. **Join** on `userData.part_id` (glTF extras), then on the node name. Walk up from the hit mesh to the first ancestor that has an id, because a part can be a group of meshes.
2. **Tooltip:** name, retail price, aftermarket low–high (or "none").
3. **Detail:** add OEM number, grade, brands, savings, `source` + `checked_on`, and the `note`. Any price with `basis: "estimate"` gets a visible estimate badge.
4. **Totals:** multiply by `quantity`. A part with no aftermarket option counts at its retail price in the aftermarket total, since it costs that either way. Show "N of M prices are estimates" next to the totals whenever N > 0.
5. **Mismatches are visible:** list catalog parts that aren't in the model and meshes that aren't in the catalog. Don't drop them silently.
6. **Links:** render catalog URLs only if they are http(s), with `rel="noopener noreferrer"`. Set catalog text with `textContent`, never `innerHTML`.

## Porting notes

- **React Three Fiber:** load with `useGLTF`, build a `Map(id → catalog part)`, handle `onPointerOver`/`onClick` on the root `<primitive>`, and render labels with drei `<Html>` at each part's bounding-box center.
- **RealityKit / SceneKit:** export USD (see car-3d-model). Each part is an entity or node named by id. Load the catalog with `Codable`. Hit-test, then walk up `parent` to the first named part.

## Common mistakes

| Mistake | Fix |
|---|---|
| Every label on by default | Gets cluttered past about 15 parts. Default to hover, offer "show all" |
| One shared material highlighted | The whole car lights up. Clone the material per part (the viewer does this on load) |
| Hovering a list row rewrites a panel above the list | The list jumps under the cursor. Update details only on canvas hover or click |
| Prices typed into labels | They go stale. Read from the catalog |
| Totals without the estimate count | Readers take estimates as quotes |
