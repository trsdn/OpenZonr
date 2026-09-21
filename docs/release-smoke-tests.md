# Release smoke tests

A published release is installed as a consumer receives it and checked without
anyone operating the app.

## How

[`smoke-test.yml`](../.github/workflows/smoke-test.yml) runs on demand for a tag,
under Actions, Release smoke test, Run workflow. The release itself is built,
signed, notarized and published by the notarization broker, so no workflow here
runs at release time. The maintainer or an agent starts the smoke test for the
new tag after the broker has published. It:

1. downloads the arm64 DMG and its checksum from the GitHub release and verifies
   the checksum;
2. installs the app into a temporary directory, so nothing outlives the run;
3. checks the signature, the Gatekeeper assessment and the notarization ticket,
   which is what macOS applies to a downloaded app.

The dated record is the job summary of each run: version, asset, macOS version,
what was exercised, and the result.

## What it does not cover

The app is not started. It is a menu bar app whose useful behaviour needs the
Accessibility permission and a logged-in desktop with real displays, which a hosted
runner does not have. The `selftest` subcommand described in the README needs that
permission too, so it cannot run unattended. Placement, drop zones and the update
path are checked by hand.

## Status

Not yet run. The first run is for `v0.1.2`; its workflow run is recorded in
[the self-assessment](self-assessment.md) under `R05`.
