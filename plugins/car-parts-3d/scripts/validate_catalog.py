#!/usr/bin/env python3
"""Validate a car parts catalog (catalog.json) and print its price totals.

Usage: python3 validate_catalog.py catalog.json [--quiet]

Exit 0 when there are no errors (warnings are allowed), 1 when there are errors,
2 when the file cannot be read. Standard library only.
"""
import json
import re
import sys
from datetime import date

SYSTEMS = {
    "body", "glass", "lighting", "wheels", "brakes", "suspension", "steering",
    "engine", "drivetrain", "exhaust", "cooling", "fuel", "electrical", "hvac",
    "interior", "trim",
}
GRADES = {"oe_equivalent", "capa_certified", "economy", "performance", "remanufactured"}
BASES = {"quoted", "estimate"}
ID_RE = re.compile(r"^[a-z][a-z0-9]*(_[a-z0-9]+)+$")
SIDE_SUFFIXES = {"_lh": "_rh", "_fl": "_fr", "_rl": "_rr"}


def is_money(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool) and v > 0 and round(v, 2) == v


def check_date(value, where, errors):
    if not isinstance(value, str):
        errors.append(f"{where}: checked_on is required (YYYY-MM-DD)")
        return
    try:
        d = date.fromisoformat(value)
    except ValueError:
        errors.append(f"{where}: checked_on '{value}' is not YYYY-MM-DD")
        return
    if d > date.today():
        errors.append(f"{where}: checked_on {value} is in the future")


def check_source(obj, where, errors, warnings):
    basis = obj.get("basis")
    if basis not in BASES:
        errors.append(f"{where}: basis must be 'quoted' or 'estimate', got {basis!r}")
        return
    if basis == "quoted":
        url = obj.get("url")
        if not (isinstance(url, str) and url.startswith(("http://", "https://"))):
            errors.append(f"{where}: a quoted price needs the http(s) url it was read from")
        if not obj.get("source"):
            errors.append(f"{where}: a quoted price needs a source (seller name)")
        check_date(obj.get("checked_on"), where, errors)
    else:
        if not obj.get("note"):
            errors.append(f"{where}: an estimate needs a note saying what it is based on")
        prices = [obj.get(k) for k in ("price", "low", "high") if obj.get(k) is not None]
        if any(isinstance(p, (int, float)) and p != int(p) for p in prices):
            warnings.append(f"{where}: estimate has cents; round estimates so they don't look like quotes")


def validate(cat):
    errors, warnings = [], []

    v = cat.get("vehicle")
    if not isinstance(v, dict):
        errors.append("vehicle: required object")
    else:
        for k in ("year", "make", "model", "trim"):
            if not v.get(k):
                errors.append(f"vehicle.{k}: required (prices depend on exact fitment)")

    cur = cat.get("currency")
    if not (isinstance(cur, str) and re.fullmatch(r"[A-Z]{3}", cur)):
        errors.append("currency: required ISO 4217 code such as 'USD'")

    parts = cat.get("parts")
    if not isinstance(parts, list) or not parts:
        errors.append("parts: required non-empty list")
        return errors, warnings, {}

    seen = set()
    totals = {"retail": 0.0, "after_low": 0.0, "after_high": 0.0, "parts": 0,
              "estimates": 0, "prices": 0, "no_aftermarket": 0, "by_system": {}}

    for i, p in enumerate(parts):
        pid = p.get("id") if isinstance(p, dict) else None
        where = f"parts[{i}]" + (f" ({pid})" if pid else "")
        if not isinstance(p, dict):
            errors.append(f"{where}: must be an object")
            continue
        if not isinstance(pid, str) or not ID_RE.match(pid):
            errors.append(f"{where}: id must be lowercase words joined by '_' such as 'body_hood' (no dots, dashes or spaces)")
            continue
        if pid in seen:
            errors.append(f"{where}: duplicate id")
        seen.add(pid)

        system = p.get("system")
        if system not in SYSTEMS:
            errors.append(f"{where}: system {system!r} is not one of {sorted(SYSTEMS)}")
        elif not pid.startswith(system + "_"):
            errors.append(f"{where}: id must start with its system, e.g. '{system}_...'")
        if not p.get("name"):
            errors.append(f"{where}: name (the label shown on the model) is required")
        qty = p.get("quantity", 1)
        if not (isinstance(qty, int) and qty >= 1):
            errors.append(f"{where}: quantity must be a whole number >= 1")
            qty = 1
        if "visible" in p and not isinstance(p["visible"], bool):
            errors.append(f"{where}: visible must be true or false")

        retail = p.get("retail")
        r_price = None
        if not isinstance(retail, dict):
            errors.append(f"{where}: retail price object is required")
        else:
            r_price = retail.get("price")
            if not is_money(r_price):
                errors.append(f"{where}: retail.price must be a positive amount with at most 2 decimals")
                r_price = None
            check_source(retail, f"{where} retail", errors, warnings)
            totals["prices"] += 1
            totals["estimates"] += retail.get("basis") == "estimate"

        after = p.get("aftermarket")
        a_low = a_high = None
        if after is None:
            if not p.get("aftermarket_unavailable_reason"):
                errors.append(f"{where}: aftermarket is null, so aftermarket_unavailable_reason is required")
            totals["no_aftermarket"] += 1
        elif not isinstance(after, dict):
            errors.append(f"{where}: aftermarket must be an object or null")
        else:
            a_low, a_high = after.get("low"), after.get("high")
            if not is_money(a_low) or not is_money(a_high):
                errors.append(f"{where}: aftermarket.low and .high must be positive amounts with at most 2 decimals")
                a_low = a_high = None
            elif a_low > a_high:
                errors.append(f"{where}: aftermarket.low is greater than .high")
            if after.get("grade") not in GRADES:
                errors.append(f"{where}: aftermarket.grade must be one of {sorted(GRADES)}")
            brands = after.get("brands")
            if not (isinstance(brands, list) and brands and all(isinstance(b, str) and b for b in brands)):
                errors.append(f"{where}: aftermarket.brands must list at least one brand")
            check_source(after, f"{where} aftermarket", errors, warnings)
            totals["prices"] += 1
            totals["estimates"] += after.get("basis") == "estimate"
            if (r_price and a_low and a_low > r_price
                    and after.get("grade") not in ("performance",)):
                warnings.append(f"{where}: aftermarket low ({a_low}) is above retail ({r_price}); check the retail price is MSRP for the same part")

        totals["parts"] += 1
        sysd = totals["by_system"].setdefault(system or "?", [0.0, 0.0, 0.0])
        if r_price:
            totals["retail"] += r_price * qty
            sysd[0] += r_price * qty
        # Parts with no aftermarket option cost the OEM price either way.
        low = a_low if a_low is not None else (r_price if after is None else None)
        high = a_high if a_high is not None else (r_price if after is None else None)
        if low is not None:
            totals["after_low"] += low * qty
            sysd[1] += low * qty
        if high is not None:
            totals["after_high"] += high * qty
            sysd[2] += high * qty

    for pid in seen:
        for a, b in SIDE_SUFFIXES.items():
            if pid.endswith(a) and pid[: -len(a)] + b not in seen:
                warnings.append(f"{pid}: has no matching '{pid[:-len(a)] + b}'; paired parts are priced separately")
            if pid.endswith(b) and pid[: -len(b)] + a not in seen:
                warnings.append(f"{pid}: has no matching '{pid[:-len(b)] + a}'; paired parts are priced separately")

    if totals["prices"] and totals["estimates"] / totals["prices"] > 0.5:
        warnings.append(f"{totals['estimates']} of {totals['prices']} prices are estimates; say so wherever totals are shown")

    return errors, warnings, totals


def main(argv):
    if len(argv) < 2:
        print(__doc__.strip())
        return 2
    path, quiet = argv[1], "--quiet" in argv
    try:
        with open(path, encoding="utf-8") as f:
            cat = json.load(f)
    except (OSError, json.JSONDecodeError) as e:
        print(f"cannot read {path}: {e}")
        return 2

    errors, warnings, t = validate(cat)
    for e in errors:
        print(f"ERROR   {e}")
    if not quiet:
        for w in warnings:
            print(f"WARNING {w}")
    if t:
        cur = cat.get("currency", "")
        print(f"\n{t['parts']} parts, {t['estimates']} of {t['prices']} prices are estimates, "
              f"{t['no_aftermarket']} with no aftermarket option")
        print(f"Retail (OEM) total:  {t['retail']:,.2f} {cur}")
        print(f"Aftermarket total:   {t['after_low']:,.2f} - {t['after_high']:,.2f} {cur}")
        if not quiet:
            for s, (r, lo, hi) in sorted(t["by_system"].items()):
                print(f"  {s:<12} retail {r:>11,.2f}   aftermarket {lo:>11,.2f} - {hi:,.2f}")
    print(f"\n{len(errors)} error(s), {len(warnings)} warning(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
