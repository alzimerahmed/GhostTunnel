# Hosted Config Schema — v1

Defines the JSON served from the GhostTunnel-owned config repo
[`alzimerahmed84/ghosttunnel-config`](https://github.com/alzimerahmed84/ghosttunnel-config)
(placeholder until the owner creates it — external manual step, see
`docs/phase-4-report.md`).

The app fetches (via `GitHubConfigStrategy`, `app-apple/Sources/CommonLibraryCore/Strategy/GitHubConfigStrategy.swift`):

- `https://raw.githubusercontent.com/alzimerahmed84/ghosttunnel-config/main/v1/bundle.json` — stable channel
- `https://raw.githubusercontent.com/alzimerahmed84/ghosttunnel-config/main/v1/bundle-beta.json` — beta channel

This matches the upstream `partout.io` layout the strategy expects (same file
names, `main` branch instead of the upstream website host). The model is
`ConfigBundle` (`app-apple/Sources/CommonLibraryCore/Domain/Internal/ConfigBundle.swift`)
backed by the OpenAPI schema `ConfigBundle.Config` in `scripts/openapi.yaml`
(source of truth for the generated Swift/Kotlin models — never hand-edit
`Domain/Codegen/` output).

## Top level: flag map

The document is a single JSON object mapping **config flag names** to flag
configs. Unknown flag names are ignored by the app (forward-compatible).

```json
{
  "<flag-name>": { ...Config... }
}
```

Flag names currently modeled in `scripts/openapi.yaml` (`ConfigBundle.Flag`):
`appNotWorking`, `experimentalDaemon_202610`, `experimentalDaemonOpenVPN_202610`,
`experimentalDaemonWireGuard_202610`, `unknown`. New flags may be added to the
JSON before the enum catches up — the app ignores unknown keys.

## Config object (`ConfigBundle.Config`)

| Field | Type | Required | Meaning |
|---|---|---|---|
| `rate` | integer | yes | Rollout percentage. **Only `rate == 100` activates the flag** (values `<100` or `>100` are inactive). |
| `platforms` | array of `"apple"` \| `"android"` | no | Restrict to platforms. If omitted, all platforms. |
| `minBuild` | integer | no | Minimum app build number for the flag to be active. |
| `data` | object | no | Freeform JSON payload delivered with the flag (see below). |

Activation rule (mirrors `ConfigBundle.isActive(withBuild:)`):
`rate == 100 && (minBuild absent || build >= minBuild) && (platforms absent || contains platform)`.

## `data` payload — future blocklist metadata (Phase 6)

`data` is the extension point for flag-scoped payloads. Phase 6 (DNS filtering)
will distribute blocklist metadata through it, e.g.:

```json
"data": {
  "schema": "ghosttunnel-blocklist-v1",
  "name": "GhostTunnel Basic",
  "sources": [
    { "url": "https://raw.githubusercontent.com/alzimerahmed84/ghosttunnel-config/main/blocklists/basic.txt", "format": "hosts", "sha256": "..." }
  ],
  "dohEndpoints": []
}
```

Blocklist payloads are metadata (URLs, hashes, names) — the lists themselves
are fetched separately and are untrusted input. No telemetry: the app must
fetch blocklists only when the user enables DNS filtering.

## Validation

`scripts/validate-config.sh` validates JSON well-formedness and required
fields (`rate` present and integer in every flag config) against this schema.
Run in CI via the `Config checks` job in `.github/workflows/checks.yml`.

## Example

See `config/example.json` in the GhostTunnel repo — also the fixture mirrored
by the unit tests in `app-apple/Tests/CommonLibraryTests/Strategy/`.
