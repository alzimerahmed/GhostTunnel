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

# Validate the app-owned catalog payload only when supplied. Empty endpoints
# are valid (and mean no filtering endpoint is available).
if "ghosttunnelBlocklistMetadata" in doc:
    metadata_config = doc["ghosttunnelBlocklistMetadata"]
    if not isinstance(metadata_config, dict):
        sys.exit(f"{path}: ghosttunnelBlocklistMetadata must be an object")
    metadata = metadata_config.get("data")
    if not isinstance(metadata, dict):
        sys.exit(f"{path}: ghosttunnelBlocklistMetadata.data must be an object")
    if metadata.get("schema") != "ghosttunnel-blocklist-v1":
        sys.exit(f"{path}: blocklist metadata schema must be ghosttunnel-blocklist-v1")
    if not isinstance(metadata.get("name"), str) or not metadata["name"].strip():
        sys.exit(f"{path}: blocklist metadata name must be a non-empty string")
    sources = metadata.get("sources")
    if not isinstance(sources, list):
        sys.exit(f"{path}: sources must be an array")
    import re
    from urllib.parse import urlsplit
    for index, source in enumerate(sources):
        prefix = f"{path}: sources[{index}]"
        if not isinstance(source, dict):
            sys.exit(f"{prefix} must be an object")
        url = source.get("url")
        try:
            parsed = urlsplit(url) if isinstance(url, str) else None
        except ValueError:
            parsed = None
        if parsed is None or parsed.scheme.lower() != "https" or not parsed.hostname or parsed.username is not None or parsed.password is not None:
            sys.exit(f"{prefix}.url must be an HTTPS URL with a host and no userinfo")
        if source.get("format") != "hosts":
            sys.exit(f"{prefix}.format must be hosts")
        digest = source.get("sha256")
        if not isinstance(digest, str) or not re.fullmatch(r"[0-9a-fA-F]{64}", digest):
            sys.exit(f"{prefix}.sha256 must be 64 hexadecimal characters")
    endpoints = metadata.get("dohEndpoints")
    if not isinstance(endpoints, list):
        sys.exit(f"{path}: dohEndpoints must be an array")
    endpoint_urls = set()
    for index, endpoint in enumerate(endpoints):
        prefix = f"{path}: dohEndpoints[{index}]"
        if not isinstance(endpoint, dict):
            sys.exit(f"{prefix} must be an object")
        url = endpoint.get("url")
        try:
            parsed = urlsplit(url) if isinstance(url, str) else None
            port = parsed.port if parsed is not None else None
        except ValueError:
            parsed = None
            port = None
        if parsed is None or parsed.scheme.lower() != "https" or not parsed.hostname or parsed.username is not None or parsed.password is not None:
            sys.exit(f"{prefix}.url must be an HTTPS URL with a host and no userinfo")
        if port == 443:
            port = None
        identity = (
            parsed.scheme.lower(),
            parsed.hostname.lower(),
            port,
            parsed.path or "/",
            parsed.query,
        )
        if identity in endpoint_urls:
            sys.exit(f"{prefix}.url duplicates another DoH endpoint")
        endpoint_urls.add(identity)
        if not isinstance(endpoint.get("name"), str) or not endpoint["name"].strip():
            sys.exit(f"{prefix}.name must be a non-empty string")

print(f"OK: {path} ({len(doc)} flags)")
PY
}

status=0
for file in "${files[@]}"; do
    validate_file "$file" || status=1
done
exit "$status"
