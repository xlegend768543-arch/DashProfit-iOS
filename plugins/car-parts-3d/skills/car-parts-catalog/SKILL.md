---
name: car-parts-catalog
description: Use when listing, labeling or pricing the parts of a specific car, building a parts breakdown or bill of materials for a vehicle, comparing OEM or dealer retail prices with aftermarket prices, estimating replacement part costs, or attaching part names and prices to a 3D car model.
---

# Car parts catalog: labeled parts with retail and aftermarket prices

## Overview

The catalog (`catalog.json`) is the single source of truth for every part's **label** and **prices**. A 3D model holds geometry and part ids only. Viewers join the two by id. Prices go stale, so they live in one file you can re-price without touching the model.

Every part carries **two prices**:

| Field | Means | Typical sources (US) |
|---|---|---|
| `retail` | New OEM part at the manufacturer's list price (MSRP) | The brand's official parts store or a dealer parts site; record MSRP, not the dealer's discounted price |
| `aftermarket` | New non-OEM part for the same fitment, as a low–high range | RockAuto, AutoZone, Advance, O'Reilly, NAPA, CarParts.com, FCP Euro (European cars); CAPA-certified for body panels |

Used, salvage and labor costs are out of scope. Add them as extra fields if the user asks.

## Workflow

1. **Pin the fitment.** You need year, make, model, trim and market. Get engine, body style and VIN when you can. If the trim is missing, ask: one trim can have LED headlamps at 3× the price of another trim's halogen ones.
2. **List the parts.** Start from [taxonomy.md](taxonomy.md). Make each entry the unit a parts counter sells (a headlamp *assembly*, not its lens and bulb), and give each side and each corner its own entry.
3. **Price each part** using the price contract below.
4. **Validate** and fix until it reports 0 errors:
   ```bash
   python3 ${CLAUDE_PLUGIN_ROOT}/scripts/validate_catalog.py catalog.json
   ```
   It checks ids, the price contract, left/right pairs, and prints retail and aftermarket totals per system.
5. **Report** totals with the estimate count next to them ("21 of 60 prices are estimates").

## Price contract

Each `retail` and `aftermarket` object has a `basis`:

- **`"quoted"`**: you read this price on a live page in this session. It needs `source` (seller), `url` (the page) and `checked_on` (today, YYYY-MM-DD).
- **`"estimate"`**: anything else, including prices from memory or training data. It needs a `note` saying what it's based on ("typical MSRP range for this panel on compact sedans"). Round estimates to whole dollars (to the nearest 5 or 10 for big parts) so they can't be mistaken for quotes.

If you can browse, quote. If you can't, estimate and say so. The validator rejects a quoted price without a URL.

`aftermarket` is `null` only when no new non-OEM part is sold (roof skins, many airbag and safety parts, recent-model trim). In that case set `aftermarket_unavailable_reason`. Never omit the field.

For `aftermarket.grade` use one of `oe_equivalent`, `capa_certified`, `economy`, `performance` or `remanufactured`, and list the brands you priced in `brands`.

## Ids and sides

- Ids are `system_part[_position]`: lowercase letters, digits and underscores. The **first word is the system**: `body_hood`, `lighting_headlamp_lh`, `wheels_tire_fr`.
- No dots, dashes or spaces. Underscores are the only separator that survives Blender, glTF, three.js (its GLTFLoader strips dots from node names) and USD/USDZ (prim names can't contain dots or dashes).
- Sides: `_lh`/`_rh`, corners `_fl _fr _rl _rr`. **LH and RH are from the driver's seat facing forward**, not the viewer's left. LH is the driver's side in the US.
- Systems: `body glass lighting wheels brakes suspension steering engine drivetrain exhaust cooling fuel electrical hvac interior trim`.

## Entry shape

```json
{
  "schema_version": "1.0",
  "vehicle": { "year": 2019, "make": "Toyota", "model": "Camry", "trim": "SE",
               "body": "4-door sedan", "engine": "2.5L I4", "market": "US", "vin": null },
  "currency": "USD",
  "priced_on": "2026-11-16",
  "parts": [
    {
      "id": "lighting_headlamp_lh",
      "name": "Headlamp assembly, left",
      "system": "lighting",
      "quantity": 1,
      "visible": true,
      "oem_part_number": "81150-06xxx",
      "fitment_note": "LED projector, SE/XSE only",
      "retail": { "price": 615, "basis": "estimate",
                  "note": "Typical MSRP for an LED headlamp assembly on this model" },
      "aftermarket": { "low": 160, "high": 310, "grade": "oe_equivalent",
                       "brands": ["TYC", "Depo"], "basis": "quoted",
                       "source": "RockAuto", "url": "https://www.rockauto.com/...",
                       "checked_on": "2026-11-16" }
    }
  ]
}
```

- `visible: false` marks parts that aren't drawn on the model (engine internals, radiator). They are still priced.
- `quantity` multiplies into totals. Use it only for identical parts in one place (lug nuts ×20). Wheels at four corners are four entries, so each can be clicked.
- One `currency` per catalog (ISO 4217).

## Common mistakes

| Mistake | Fix |
|---|---|
| One price per part | Both `retail` and `aftermarket` on every entry; `null` + reason when no aftermarket exists |
| A precise-looking price with no source | That's an estimate: `basis: "estimate"`, a note, a rounded number |
| Dealer sale price recorded as retail | Retail is MSRP; put a discounted price in `retail.note` if useful |
| Used or junkyard price as aftermarket | Aftermarket means new non-OEM |
| "Doors" as one entry | One entry per door and side; the model needs one object per entry |
| Viewer's left taken as LH | LH = driver's side (driver's seat, facing forward) |
| Prices written into the 3D model or viewer code | Prices live only in the catalog |
