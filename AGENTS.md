# Agent instructions

Read this before changing anything in this repository.

## What this repository is

OpenZonr is a macOS window manager with drop zones, built with Swift Package
Manager for macOS 14 or later. It is a menu bar app (`LSUIElement`, no Dock icon)
that places windows into zones by rule when they open, and a command line tool,
`openzonr`, that shares the same binary and is used for diagnostics. End users
install the signed, notarized DMG or ZIP from GitHub Releases and receive updates
in place through the app itself (AppUpdater, checking GitHub Releases). A bad
release reaches every installed copy, so changes to the update code, the bundle
identity in `Sources/OpenZonrApp/Info.plist`, and `Package.resolved` can strand
users on an old version.

## What this repository is not

- Not a Mac App Store app: there is no sandbox, receipt or App Store review.
- Not the release pipeline. Building, signing, notarizing and publishing happen in
  the separate repository `trsdn/macos-notarization-broker`, started by the
  maintainer. Nothing here signs or publishes a release.
- Not a tiling window manager. It places the few apps that have a rule.

## Layout

| Path | Purpose |
|---|---|
| `Sources/OpenZonrCore/` | Platform-independent, tested logic: geometry, display identity, rules, profiles, configuration, validation, placement. No dependencies. |
| `Sources/OpenZonrMac/` | Everything that talks to macOS: Accessibility, CoreGraphics displays, the watch engine, the command line subcommands. No dependencies. |
| `Sources/OpenZonrApp/` | The menu bar app. Depends on AppUpdater. `Info.plist` lives here because the release broker expects it at exactly this path. |
| `Sources/openzonr/` | `swift run openzonr` for development. |
| `Tests/OpenZonrCoreTests/`, `Tests/OpenZonrMacTests/`, `Tests/OpenZonrAppTests/` | Unit tests for the pure decisions in each layer. They do not cover the interface, real Accessibility access, real displays or an actual update; those are measured by hand and recorded in `docs/`. |
| `Scripts/bundle.sh` | Builds and signs a local app bundle. See the destructive-command rules below before running it. |
| `Scripts/make-icon.swift` | Draws `Resources/AppIcon.icns`. |
| `docs/` | Concept, configuration reference, measurements and open questions, in German. |
| `docs/self-assessment.md`, `.github/conformance.yml` | The repository's assessment against the Repository Quality Standard. |
| `CHANGELOG.md` | Source of the release notes. |

- Generated, never hand-edit: `.build/` (SwiftPM output, git-ignored);
  `Resources/AppIcon.icns` (committed, regenerate with `swift Scripts/make-icon.swift`);
  `.github/badges/` and the badge block in `README.md` (regenerate with the
  conformance script the conformance workflow calls).
- Machine-owned: `Package.resolved`. It is committed on purpose, because the
  release broker builds against `--only-use-versions-from-resolved-file` and
  compares it byte for byte with its own reviewed copy. Change it only through
  `Package.swift` or a Dependabot pull request, and say in the pull request that
  the broker's copy must be updated before the next release.

## Setup

```sh
swift build
```

Requires macOS 14 or later and Swift 6 (`swift-tools-version: 6.0` in
`Package.swift`). SwiftLint is needed for the lint step: `brew install swiftlint`.

## Run

```sh
swift run openzonr --help
```

A working placement needs a signed bundle with the Accessibility grant, which an
unsigned `swift run` binary does not get. See the README for the bundle route.

## Validate before proposing a change

All three must succeed. CI runs the same three on every pull request.

```sh
swift build -c release -Xswiftc -warnings-as-errors
swiftlint lint --strict
swift test
```

The build type-checks the whole package under Swift 6 language mode with warnings
as errors. `swiftlint lint --strict` runs the small rule set in `.swiftlint.yml`,
which passes today, so any violation is a regression; add a rule only in the change
that fixes its last violation. `swift test` runs the unit tests. For a change to
placement, drop zones, permissions or updates, also build a bundle to a temporary
location (`Scripts/bundle.sh "$(mktemp -d)/OpenZonr.app"`) and check the affected
flow by hand, and say in the pull request what you tried.

## Conventions

- The user interface, `docs/`, code comments and the changelog are written in
  German, and new text there follows that. This file and the standard's
  own files are English.
- Commits follow Conventional Commits, `type(scope): description`, as in the
  existing history.
- User-visible changes get an entry under `[Unreleased]` in `CHANGELOG.md`. The
  broker publishes only when `[Unreleased]` is empty and a section for the version
  exists, and that section's text becomes the release notes.
- Release identity comes from `Sources/OpenZonrApp/Info.plist`, where `__VERSION__`
  is replaced by whoever builds: `Scripts/bundle.sh` locally, the broker from the
  tag.
- Pull requests are how every change reaches `main`; nothing is pushed straight to it.
- Docs state measurements as measured and mark what was not measured. Keep that
  distinction when editing them.

## Do not do these

- Do not rewrite history, force push, or delete branches that are not yours.
- Do not commit secrets, tokens, certificates, `.p12` files, keychains or notary
  profiles.
- Do not publish a release, create or move tags, or change repository settings.
  The maintainer starts a release from the broker repository, and pushing a tag
  or running the broker on your own would reach every installed copy.
- Do not edit the update code path (`Sources/OpenZonrApp/Update/`), the
  `Info.plist` identifier keys, or `Package.resolved` without a pull request the
  maintainer approves. Do not add a build-attestation policy to the updater: the
  release is built by the broker, so there is no provenance from this repository
  to verify (see the README section on updates).
- Do not run `Scripts/bundle.sh` without a target argument. Its default target is
  `~/Applications/OpenZonr.app`, the copy the maintainer has granted Accessibility
  access to; replacing it can invalidate that grant.
- Do not run destructive commands against the machine you are on: no
  `tccutil reset`, no `defaults delete` for `com.trsdn.openzonr`, and no removal
  of `~/Library/Application Support/OpenZonr/` or `~/Applications/OpenZonr.app`.
  The configuration file there is the user's data.
- Do not hand-edit the generated paths listed above.
- Do not add or upgrade dependencies without a pull request the maintainer
  approves. Dependabot proposes routine updates weekly. The core and mac targets
  are dependency-free on purpose.
- Do not send user content off the machine: window titles, application names and
  file paths stay local. The only network contact is the update check against
  GitHub Releases.

## Credentials and revocation

This repository holds no credential and needs none for CI; the workflows use only
the per-run `GITHUB_TOKEN`. The signing and notarization credentials are held by
the release broker repository and the maintainer's keychain, not here. If one is
exposed, the maintainer revokes it at its source first (the Developer ID
certificate in the Apple Developer portal, an app-specific password at
appleid.apple.com) and then replaces it in the broker. An agent never rotates or
revokes a credential; it stops and reports where the credential was seen.

## Attribution

Commits made by an agent carry a `Co-Authored-By` trailer that names the agent,
and a pull request description says it was agent-authored. Every change is reviewed
by the maintainer in a pull request before it merges.
