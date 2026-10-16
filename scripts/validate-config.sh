#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: 2026 Alzimer Ahmed
# SPDX-License-Identifier: GPL-3.0
#
# Validates the hosted config JSON (config/example.json, and any bundle*.json
# passed as arguments) against config/schema.md v1:
#   - well-formed JSON
#   - top level is an object of flag name -> config object
#   - every config has an integer "rate"
#   - optional fields have the documented types
#
# Usage: scripts/validate-config.sh [file.json ...]
#        (defaults to config/example.json)
#
set -euo pipefail

root_dir="$(cd "$(dirname "$0")/.." && pwd)"

if [[ $# -gt 0 ]]; then
    files=("$@")
else
    files=("$root_dir/config/example.json")
fi

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

validate_file() {
    local file="$1"
    [[ -f "$file" ]] || fail "not a file: $file"

    python3 - "$file" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, "rb") as fh:
    try:
        doc = json.load(fh)
    except Exception as exc:
        sys.exit(f"{path}: not valid JSON: {exc}")

if not isinstance(doc, dict):
    sys.exit(f"{path}: top level must be an object (flag map), got {type(doc).__name__}")

OPTIONAL_TYPES = {
    "platforms": list,
    "minBuild": int,
    "data": dict,
}

for flag, config in doc.items():
    if not isinstance(config, dict):
        sys.exit(f"{path}: flag '{flag}' must map to an object")
    rate = config.get("rate")
    if rate is None:
        sys.exit(f"{path}: flag '{flag}' missing required field 'rate'")
    if not isinstance(rate, int) or isinstance(rate, bool):
        sys.exit(f"{path}: flag '{flag}' field 'rate' must be an integer")
    for key, typ in OPTIONAL_TYPES.items():
        if key in config and not isinstance(config[key], typ):
            sys.exit(f"{path}: flag '{flag}' field '{key}' must be {typ.__name__}")
    if "platforms" in config:
        for platform in config["platforms"]:
            if platform not in ("apple", "android"):
                sys.exit(f"{path}: flag '{flag}' invalid platform '{platform}'")

print(f"OK: {path} ({len(doc)} flags)")
PY
}

status=0
for file in "${files[@]}"; do
    validate_file "$file" || status=1
done
exit "$status"
