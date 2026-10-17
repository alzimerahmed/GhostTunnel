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

## `data` payload — blocklist metadata (Phase 6)

The `ghosttunnelBlocklistMetadata` flag carries the DNS-filtering blocklist
catalog in its `data` payload. The flag uses the standard `ConfigBundle.Config`
fields (`rate`, `platforms`, `minBuild`) and is only surfaced to the app when
the flag is active per the activation rule above. Its `data` object is decoded
and validated by `BlocklistCatalog`
(`app-apple/Sources/AppLibrary/Observables/BlocklistCatalog.swift`); any
violation of the rules below causes the whole payload to be rejected (the app
behaves as if no catalog were configured).

```json
"ghosttunnelBlocklistMetadata": {
  "rate": 100,
  "platforms": ["apple"],
  "data": {
    "schema": "ghosttunnel-blocklist-v1",
    "name": "GhostTunnel Basic",
    "sources": [],
    "dohEndpoints": []
  }
}
```

### `data` fields

| Field | Type | Required | Validation |
|---|---|---|---|
| `schema` | string | yes | Must be exactly `ghosttunnel-blocklist-v1`. |
| `name` | string | yes | Non-empty after trimming whitespace. Display name for the catalog. |
| `sources` | array of objects | yes | May be empty. Each entry: `url` (HTTPS URL with a host, no userinfo — no embedded username/password), `format` (must be `"hosts"`), `sha256` (exactly 64 hexadecimal characters — the expected digest of the hosts file). |
| `dohEndpoints` | array of objects | yes | May be empty (means no filtering endpoint is offered). Each entry: `name` (non-empty after trimming whitespace — shown in the DNS settings picker), `url` (HTTPS URL with a host, no userinfo). Endpoint URLs must be unique. |

### Current behavior and caveats

- **Metadata only.** The app does not yet download hosts files or enforce
  local DNS filtering from `sources[]`; the entries are validated so the
  catalog format is stable, but no blocklist content is fetched or applied.
- **DoH is explicit opt-in.** Configured `dohEndpoints` are listed as
  selectable resolvers in the DNS module settings. DNS queries are sent to a
  configured resolver only when the user explicitly selects it; until then the
  VPN-provided DNS is used. Selecting a resolver sends that provider the
  device's DNS queries — only list endpoints you trust.
- **Do not configure a live third-party endpoint by default.** The shipped
  sample (`config/example.json`) keeps `dohEndpoints` empty; any real endpoint
  is an operational decision, not a default.
- `scripts/validate-config.sh` enforces the same rules (schema value,
  non-empty names, HTTPS/no-userinfo URLs, `format: hosts`, 64-hex `sha256`)
  on any bundle containing `ghosttunnelBlocklistMetadata`.

## Validation

`scripts/validate-config.sh` validates JSON well-formedness and required
fields (`rate` present and integer in every flag config) against this schema.
Run in CI via the `Config checks` job in `.github/workflows/checks.yml`.

## Example

See `config/example.json` in the GhostTunnel repo — also the fixture mirrored
by the unit tests in `app-apple/Tests/CommonLibraryTests/Strategy/`.
