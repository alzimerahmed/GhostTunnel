# GhostTunnel — Rules for AI Agents

## Project

GhostTunnel = open-source VPN and privacy client (fork of Passepartout, GPLv3; upstream: https://github.com/partout-io/passepartout; our repo: https://github.com/alzimerahmed/GhostTunnel, owner: Alzimer Ahmed <alzimerahmed84@gmail.com>). Inherits the full Passepartout feature set: OpenVPN (incl. Tunnelblick XOR patch) and WireGuard client, on-demand rules, DNS/HTTP-proxy override, custom routing, provider presets, iCloud sync, Shortcuts, Apple TV support. Differentiation: clean branding, privacy-first, no telemetry.

**License:** GPLv3. Upstream `LICENSE` must be preserved — GPLv3 does not permit relicensing. Our additions carry our copyright notice; upstream attribution stays in README/headers where required.

**Scope:** Native apps only — Apple (iOS/macOS/tvOS, Xcode/Swift), Android (Gradle, in progress upstream), cross-platform desktop (CMake + wxWidgets), plus the `partout` core (git submodule) and the OpenAPI model toolchain. No web client. All verification is CI-only (see Build/Verify).

## How It Works (domain constraints — read before touching the code)

- **`partout/` is the VPN core** — a git submodule pointing to https://github.com/partout-io/partout (Swift, platform-independent: connection profiles, tunnels, WireGuard/OpenVPN implementations, DNS, routing). Do NOT vendor or hand-edit it; changes to core behavior happen upstream or via the app layer. CI checks it out recursively.
- **`app-apple/`** is the primary client: `Passepartout/` (Xcode project, App + Intents + assets, `Config*.xcconfig` for bundle identity), `Sources/` (shared SwiftUI code, Swift Package), `Tests/`, `ci/`, `fastlane/` (screenshots/distribution), `swiftgen.yml` (generated asset/string accessors — regenerate, never hand-edit generated files).
- **`app-android/`**: Gradle + Kotlin client (upstream work-in-progress).
- **`app-cross/`**: CMake + wxWidgets cross-platform desktop app + tunnel binary (`CMakePresets.json`).
- **API models**: `scripts/gen-models.sh` + `openapi.yaml` + `openapitools.json` generate provider API models (`@openapitools/openapi-generator-cli` in `package.json`) — regenerate, don't hand-edit generated output.
- **Translations**: `scripts/import-translations.sh` — generated localization files are not hand-edited.

## Tech Stack & Conventions (do not fight it)

- **Apple**: Swift 6, Xcode 26, iOS 17+ / macOS 14+ / tvOS 17+, SwiftUI, Swift Package (`app-apple/Package.swift`), swiftgen for codegen.
- **Android**: Kotlin + Gradle (`app-android/`).
- **Cross**: C++/CMake presets (`CMakePresets.json`), wxWidgets.
- **Ruby tooling**: `Gemfile` (fastlane, `.ruby-version`).
- **Commits**: Conventional Commits for our changes (`type(scope): description`); upstream history style is irrelevant — this repo has fresh history.
- **Bundle identity**: GhostTunnel branding (`com.ghosttunnel.*` bundle IDs, display name GhostTunnel) landed in Phase 3 — CI-verified; never change ad hoc. Xcode target/scheme/directory names (`Passepartout*`) and the Android Kotlin namespace remain upstream-named for stability.

## Build / Verify

```bash
# CI (GitHub Actions, .github/workflows/ — PR to master + manual):
#   checks.yml                — reusable: Apple tests (macos-26), Partout core tests, Cross checks (ubuntu)
#   test.yml                  — calls checks.yml on PRs
#   distribute_apple.yml / export_apple.yml / package_apple.yml / package_android.yml / release*.yml
#                             — secret-dependent (fastlane, gpg, signing); DISABLED on this fork
# Local scripts (CI context only): ci/run-apple-tests.sh, ci/run-partout-swift-tests.sh, ci/run-partout-tests.sh, ci/run-api-tests.sh
```

**Remote-first verification (mandatory):** we do NOT build or test locally — this workspace is Windows and all builds/tests run in GitHub Actions. Local work is edit-only: static review while iterating. Push and let CI verify; a CI green check counts as the gate.

**Signing/distribution:** release, export, distribute, and package workflows require upstream secrets (fastlane match, gpg, App Store credentials) we do not have — they stay disabled on the fork; `checks.yml`/`test.yml` are the active gate. Never hardcode signing material.

## Removed on Purpose — Do NOT Re-add

- Secret-dependent workflows: `distribute_apple.yml`, `export_apple.yml`, `package_apple.yml`, `package_android.yml`, `release.yml`, `release_manual.yml` — re-enabling them makes pushes fail on missing secrets. Keep them disabled or delete; `checks.yml` + `test.yml` are the gate.
- `CLA.rst`, `CONTRIBUTING.md` (upstream governance docs we don't maintain) — may be removed/replaced with our own.
- Upstream badges/links to passepartout.io, TestFlight, App Store — replaced with GhostTunnel identity.

## Gotchas

- **`partout` submodule is empty locally** unless initialized; CI checks it out (`submodules: recursive`). Never commit into it or assume its files exist locally.
- **No local build safety net** — grep all references (Package.swift, xcconfig, xcodeproj, gradle, CMakeLists, workflows) before deleting or renaming anything.
- **Generated files**: swiftgen output, OpenAPI-generated models, imported translations are produced by `scripts/` — regenerate, don't hand-edit.
- **Xcode project edits**: `project.pbxproj` is fragile — prefer xcconfig/SwiftPM-level changes; verify in CI.
- **Windows checkout**: symlinks and case-sensitive paths can be hostile; avoid `git clean -fdx`.
- **GPLv3**: no proprietary additions; third-party deps must stay GPLv3-compatible.

## Agent Guidelines & Constraints

### Do's
- **Write tests** for new behavior (Swift Testing / XCTest in `app-apple/Tests/`); run in CI only.
- **Conventional Commits** for our changes.
- **Respect module boundaries** — app logic in `app-apple/Sources/`, never inside the `partout` submodule.
- **Plan discipline** — `docs/plan.md` must contain a Quality Gate phase and a Release phase. Every `idea.md` Feature Gap entry maps to a phase or is explicitly deferred. When a phase answers an open question in `docs/research.md`, close it there in the same change.

### Don'ts
- **NO local builds or test runs** — verification is CI-only (user directive; Windows host).
- **NO secrets in code** — signing keys via CI secrets only; none exist on the fork yet.
- **NO new heavy dependencies** without a decision record in `docs/research.md` (license must stay GPLv3-compatible).
- **NO deleting resources** without grepping all reference types (Package.swift, pbxproj, xcconfig, gradle, CMakeLists, workflows).
- **NO renaming bundle IDs/product names ad hoc** — that is a planned phase, CI-verified.

## Agent Guidelines & Workflow (this repo's .devin system)

### Resource Discipline (mandatory, non-trivial tasks)
Before any non-trivial task:
1. Read `docs/toolset.md` intent-map (task type → resources)
2. Invoke every skill + sub-agent in that row
3. Read every rule for that task type (`.devin/rules/`)
4. At task end: `code-reviewer` sub-agent on final diff (non-negotiable)
5. Append learnings via `/ce-compound` if durable lesson

Phase implementations (task completes a docs/plan.md row): follow `.devin/prompt/phase.md`.

Skip all this for single-line edits, pure Q&A, reading files.

### Project-Type Filter (cross-platform VPN client)
Per `docs/toolset.md` intent-map:
- **Skip web-only:** pwa-engineer, seo-specialist (web), css-architect, playwright-design-clone, payment-integrator, email-engineer, monorepo-manager, web-scraper, search-optimization, backend-architect (no server).
- **Keep universal:** code-reviewer, debugger, test-engineer, security-auditor, performance-engineer, git-master, migration-specialist, docs-writer, build-optimizer, devops-engineer, dx-optimizer, caveman-compressor, vibe-coding-auditor, type-safety-engineer, state-manager, i18n-specialist, media-optimizer, animation-engineer, frontend-designer (native UI taste), content-writer, database-engineer (profile/persistence), search-architect (in-app search).
- **Quality gates:** CI-only — Apple tests (macOS), Partout core tests, Cross checks on GitHub Actions. No local builds.

## Communication Style

Default **caveman-lite** (lightly compressed, readable, technically accurate). `/caveman` skill for full/ultra/wenyan modes.

## Quick Task Flow

Quick tasks: `.devin/prompt/quick.md` (commandments) + `.devin/prompt/rules.md` (scoping, verification, escalation). Phased work: `.devin/prompt/phase.md`.

## Key References

> Note: `docs/*.md` files below are the private knowledge layer (gitignored) — they exist only in the local workspace, not for external cloners.

- `docs/toolset.md` — intent map (task type → skills, sub-agents, rules)
- `docs/plan.md` — phased plan + status
- `docs/project.md` — project state/structure
- `docs/tools-log.md` — .devin resources invoked per session
- `docs/CONCEPTS.md` — project vocabulary
- `docs/research.md` — research, ADRs, gotchas, open questions
- `docs/idea.md` — competitive analysis + Feature Gap List
- `docs/design/design-system.md` — UI tokens + rules
