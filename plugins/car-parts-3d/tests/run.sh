#!/usr/bin/env bash
# Tests for the car-parts-3d scripts. Run: bash tests/run.sh
# The Blender steps run when `blender` is on PATH or BPY_PYTHON points at a Python with bpy installed;
# otherwise they are skipped and reported as skipped.
set -u
cd "$(dirname "$0")/.."
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0; skip=0
ok()   { echo "PASS  $1"; pass=$((pass+1)); }
bad()  { echo "FAIL  $1"; fail=$((fail+1)); }
expect() { # expect <name> <expected-exit> <grep-pattern-or-empty> -- cmd...
  local name=$1 want=$2 pat=$3; shift 4
  local out; out="$("$@" 2>&1)"; local got=$?
  if [ "$got" -ne "$want" ]; then bad "$name (exit $got, want $want)"; echo "$out" | tail -5; return; fi
  if [ -n "$pat" ] && ! grep -q -- "$pat" <<<"$out"; then bad "$name (missing: $pat)"; echo "$out" | tail -5; return; fi
  ok "$name"
}

CAT=examples/sample-catalog.json
expect "sample catalog validates" 0 "0 error(s)" -- python3 scripts/validate_catalog.py "$CAT"
expect "totals printed" 0 "Retail (OEM) total:  21,440.00 USD" -- python3 scripts/validate_catalog.py "$CAT"

# Each broken catalog must fail with its own message.
mutate() { python3 -c "import json,sys; c=json.load(open('$CAT')); p=c['parts']; $1; json.dump(c,open(sys.argv[1],'w'))" "$TMP/bad.json"; }
mutate "p[0]['retail']={'price':520.0,'basis':'quoted'}"
expect "quoted price without url rejected" 1 "needs the http(s) url" -- python3 scripts/validate_catalog.py "$TMP/bad.json"
mutate "p[0]['aftermarket']=None"
expect "null aftermarket without reason rejected" 1 "aftermarket_unavailable_reason is required" -- python3 scripts/validate_catalog.py "$TMP/bad.json"
mutate "p[0]['id']='body.hood'"
expect "dotted id rejected" 1 "no dots" -- python3 scripts/validate_catalog.py "$TMP/bad.json"
mutate "p[0]['id']='glass_hood'"
expect "id/system mismatch rejected" 1 "must start with its system" -- python3 scripts/validate_catalog.py "$TMP/bad.json"
mutate "p[0]['aftermarket']['low']=999"
expect "low > high rejected" 1 "greater than .high" -- python3 scripts/validate_catalog.py "$TMP/bad.json"
mutate "c['parts']=[x for x in p if x['id']!='body_fender_rh']"
expect "missing pair warned" 0 "no matching 'body_fender_rh'" -- python3 scripts/validate_catalog.py "$TMP/bad.json"
mutate "p[0]['retail']['price']=519.99"
expect "estimate with cents warned" 0 "round estimates" -- python3 scripts/validate_catalog.py "$TMP/bad.json"
mutate "p[0]['retail']={'price':519.99,'basis':'quoted','source':'Dealer','url':'https://example.com/p','checked_on':'2999-01-01'}"
expect "future checked_on rejected" 1 "in the future" -- python3 scripts/validate_catalog.py "$TMP/bad.json"

# Blender pipeline
BPY=""
if command -v blender >/dev/null; then BPY="blender"; elif [ -n "${BPY_PYTHON:-}" ]; then BPY="$BPY_PYTHON"; fi
run_bpy() { local script=$1; shift; if [ "$BPY" = blender ]; then blender --background --python "$script" -- "$@"; else "$BPY" "$script" "$@"; fi; }
if [ -z "$BPY" ]; then
  echo "SKIP  blender pipeline (no blender on PATH and BPY_PYTHON unset)"; skip=$((skip+1))
else
  expect "blockout builds" 0 "exported" -- run_bpy scripts/build_blockout.py "$CAT" "$TMP/car.glb" "$TMP/car.blend"
  expect "model matches catalog" 0 " 0 error(s)" -- python3 scripts/check_model.py "$TMP/car.glb" "$CAT"
  mutate "p.append({**p[0],'id':'body_spoiler','name':'Rear spoiler'})"
  expect "unknown part placed beside car" 0 "need placing by hand" -- run_bpy scripts/build_blockout.py "$TMP/bad.json" "$TMP/car2.glb"
  expect "model missing a catalog part fails" 1 "body_spoiler" -- python3 scripts/check_model.py "$TMP/car.glb" "$TMP/bad.json"
  expect "stamp reports all parts" 0 "stamped 34 of 34" -- run_bpy scripts/stamp_part_ids.py "$TMP/car.blend" "$CAT"
fi

echo; echo "$pass passed, $fail failed, $skip skipped"
[ "$fail" -eq 0 ]
