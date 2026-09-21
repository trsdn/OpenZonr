# Self-assessment

Assessment of this repository against the
[Repository Quality Standard](https://github.com/trsdn/.github/blob/v1.19.0/docs/repository-quality-standard.md)
version 1.19.0, made on 2026-09-21 by an AI agent (Claude Sonnet 5) working in a
fresh clone, from the state of `main` after the safety-net and pipeline pull
requests (#61, #62). The result is in [`.github/conformance.yml`](../.github/conformance.yml).

Overall state: **Needs work**. Nine criteria are `Fail` and none of them is a
critical one; `Partial` and `Not applicable` results do not lower the state.

## Profiles

Baseline, Public, Software and Package apply. Deployable does not: users download
and install the app, which is the "macOS app or CLI" row of the profile table, so
`D01`-`D06` are `Not applicable` with the sentence "not a standing deployment".
Documentation does not apply. Published Site applies by definition (an app that
people use without needing the repository), but the repository publishes no site,
so the `W` criteria are `Not applicable` with the sentence "no site exists: the
repository has a README and no website, no Pages source and no homepage".
Archived does not apply.

## What was read and what was not

Read: the whole tree, `Package.swift`, `Package.resolved`, the README, `CHANGELOG.md`,
`Sources/OpenZonrApp/Info.plist`, the source files that name a network address,
logging, accessibility labels or formatting, the GitHub settings and alert APIs, the
workflow runs on the pull requests, and the latest release `v0.1.2`. Ran locally:
`swift build -c release -Xswiftc -warnings-as-errors`, `swiftlint lint --strict` and
`swift test` (106 tests in 15 suites, and the core and mac suites), all passing.
Downloaded the `v0.1.2` ZIP, checked its checksum against the release's `.sha256`,
unpacked it, read `Info.plist`, and ran `codesign --verify --deep --strict`,
`spctl --assess` and `stapler validate` on the unpacked app. The app was **not
launched** and the DMG was not mounted. Not read: the release broker's repository,
which builds and publishes the release, beyond the `provenance.json` it attaches.

Readings of judgement words, applied the same way as in every repository this
assessor assesses: the audience in `B02` counts as stated when the README names the
problem and the people who have it; "covers important behaviour" in `S02` means the
main placement logic is exercised and at least one failure path is asserted;
`S03` is met by a lint check plus the compiler's type check, which is the minimum
reading, and no separate format check is required; interface criteria (`X01`-`X03`)
are decided from source and the app was not operated.

## Results

| Criterion | Result | Note |
|---|---|---|
| `B01` | pass | Description: "macOS window manager with drop zones and rule-based automatic window placement across monitor profiles". |
| `B02` | pass | README has purpose, status line, the problem it solves for people with several displays, build and use, and links to `docs/`, issues and the licence. |
| `B03` | pass | `LICENSE`, MIT, detected by GitHub. |
| `B04` | pass | `.gitignore` covers `.build/`, `.swiftpm/`, Xcode and macOS output. `git ls-files` lists no key, `.env` or certificate; a pattern search over the whole history found no credential. `Package.resolved` is committed on purpose and documented as machine-owned. |
| `B05` | pass | `AGENTS.md` names three commands; they pass locally and CI is green on pull request #62. |
| `B06` | pass | Single maintainer; all three merge methods are enabled and `AGENTS.md` states that every change reaches `main` through a pull request. No open Dependabot, code scanning or secret scanning alert (all three read with `gh api`). |
| `B07` | pass | `Package.swift` declares the one dependency at an exact version, `Package.resolved` locks it, macOS 14 and Swift 6 are declared. |
| `B08` | pass | `CHANGELOG.md` has an entry for `0.1.2`, the latest release. |
| `B09` | pass | Public, agrees with the README's MIT licence; no homepage and the README names no site; not archived. |
| `B10` | pass | Owner is the account that owns the repository; the README's status line states the maintenance status and commits landed today. |
| `B11` | pass | `.github/conformance.yml`, dated today. |
| `B12` | pass | Topic `trsdn-standard` set. |
| `B13` | partial | The validation commands and the macOS 14 minimum appear in the README, `AGENTS.md`, `ci.yml` and `.github/github-app.yml`, by hand. All agree, so this is not a `Fail`. |
| `B14` | pass | `AGENTS.md` "Credentials and revocation": the repository holds none, and names the broker-held signing credentials and who revokes them. |
| `B15` | fail | The published app statically links AppUpdater and Version (`Package.resolved`) and carries no notice or licence text of either, and the repository states no approach. Fix: a `THIRD_PARTY_NOTICES.md` bundled by the release build. |
| `B16` | fail | `gh api repos/trsdn/OpenZonr/branches/main/protection` answers 404 and there is no ruleset. A repository setting, so left to the maintainer. |
| `P01` | pass | MIT is OSI approved. |
| `P02` | pass | Inherited `CONTRIBUTING.md` and `CODE_OF_CONDUCT.md` from the account. |
| `P03` | pass | Inherited `SECURITY.md` and private vulnerability reporting enabled. |
| `P04` | pass | Issue forms and a pull-request template are inherited from the account. The community profile API lists the pull-request template but reports `issue_template` as null, so the issue forms were decided from the files in the account repository, not from the API. |
| `P05` | partial | Install, configuration, examples, compatibility and support status are covered. The README has no security statement and no link to the security policy. |
| `P06` | pass | GitHub reports README, licence, contributing guide and code of conduct (community health 100%). |
| `P07` | pass | Description and the topic are set; there is no site, so no homepage is required. |
| `P08` | partial | Badge block is licence, platform, CI, release and conformance in that order. The platform badge is a fixed `macOS 14+` value beside the manifest with no check that covers it, which the badge rules class as `Partial`. |
| `P09` | fail | A runner is available and no generated activity card is published. Fix: the `stats.yml` template. Not adopted in this pass. |
| `P10` | pass | Inherited bug form asks for expected result, actual result, reproduction and version and environment. |
| `P11` | pass | Inherited pull-request template covers summary, related issue, validation and impact. |
| `P12` | pass | Dependabot alerts and security updates are enabled. |
| `P13` | pass | CodeQL default setup is configured for Swift (`gh api .../code-scanning/default-setup`: `configured`, `swift`); its analysis on pull requests #61 and #62 succeeded in about 20 minutes with no error. No advanced workflow was added, because default setup works here. |
| `S01` | pass | `Package.resolved` plus documented `swift build`. |
| `S02` | pass | 106 tests plus the core and mac suites; the placement decisions, rule engine and configuration validation are exercised, and the validation tests assert rejected input. Interface and real Accessibility behaviour are not covered, and the README says which measurements were made by hand. |
| `S03` | pass | `swiftlint lint --strict` and the compiler's type check with warnings as errors run in CI on every pull request; CodeQL adds static analysis. Only a subset of lint rules is on (`.swiftlint.yml`), and there is no separate format check. |
| `S04` | pass | README and manifest claim macOS 14 or later, a range; CI runs on `macos-15` and `macos-latest`. |
| `S05` | pass | Secret scanning is enabled and `secret-scan.yml` runs the shared scanner on pushes and pull requests. |
| `S06` | pass | Configuration is a JSON file with a committed example; the default path is computed from the user's home directory at run time, and no credential or personal value is committed. |
| `S07` | pass | Error messages name the failed operation and cause; the logging read in source does not write credentials. Window titles do appear in the local diagnostic output by design and go nowhere else. |
| `S08` | pass | `.github/dependabot.yml` for Actions and the Swift package. |
| `S09` | fail | Checks exist, but no ruleset or protection requires one. A repository setting, so left to the maintainer. |
| `S10` | pass | README and `docs/konzept.md` name the components and the constraints (signed bundle, Accessibility grant, `Package.resolved` byte-identical to the broker). |
| `S11` | pass | Every workflow declares `permissions`: `contents: read`, and `pull-requests: read` for the scan. |
| `S12` | pass | Actions from GitHub are at a major tag (`actions/checkout@v7`); shared workflows are called from the account at `@main`. |
| `S13` | na | No workflow uses `pull_request_target` or `workflow_run`. |
| `D01` | na | Not a standing deployment: users install the app from a release (macOS app row). |
| `D02` | na | Not a standing deployment (macOS app row). |
| `D03` | na | Not a standing deployment (macOS app row). |
| `D04` | na | Not a standing deployment (macOS app row). |
| `D05` | na | Not a standing deployment (macOS app row). |
| `D06` | na | Not a standing deployment (macOS app row). |
| `R01` | partial | Name and version live in `Info.plist`. Description, licence and repository URL have no home in `Package.swift` or `Info.plist` (see `I02`, `I03`). |
| `R02` | pass | `CHANGELOG.md` names Semantic Versioning. |
| `R03` | pass | Tag `v0.1.2` names commit `a9607d7`, the same commit as `source.commit_sha` in the release's `provenance.json`. The README documents the broker command that builds from a tag and publishes to the release. |
| `R04` | pass | Tag `v0.1.2`, `CFBundleShortVersionString` 0.1.2 read from the downloaded ZIP, release title `v0.1.2`. |
| `R05` | partial | A kit exists (`smoke-test.yml`, `docs/release-smoke-tests.md`) but no recorded run of it is complete yet: the run for `v0.1.2` (Actions run 35648787565) was still queued for a hosted macOS runner when this was written. Becomes `pass` when that run succeeds and its job summary is recorded below. The assessor did check the same properties by hand on the downloaded ZIP (see `R08`) without launching the app, which is not a kit run. |
| `R06` | pass | The release notes name specific user-visible changes (the app icon, the "Letzter Zug" menu line); nothing breaking to warn about. |
| `R07` | pass | The release body is the `0.1.2` changelog entry, which exists and is not empty; the README and `CHANGELOG.md` document that the broker refuses to publish without it. |
| `R08` | partial | The artifact is Developer ID signed and notarized (verified on the download: `codesign` valid, `spctl` "accepted, source=Notarized Developer ID", `stapler validate` worked) and the release carries the broker's `provenance.json`. The README says a GitHub attestation is deliberately not used but does not tell a consumer how to verify a download. Fix: one paragraph naming `codesign`, `spctl` and `provenance.json`. |
| `R09` | partial | No release gate or checklist exists. Read now, no Dependabot or secret scanning alert is open, but nothing records a scan for the release commit. Fix: a dated line in the release notes or `AGENTS.md`. |
| `I01` | pass | Read from the `v0.1.2` ZIP: `CFBundleName` OpenZonr, version 0.1.2, equal to the release. |
| `I02` | fail | The bundle's `Info.plist` has no repository or issue tracker URL. Not changed here because it is `Sources/`. |
| `I03` | fail | No SPDX identifier, `NSHumanReadableCopyright` is "OpenZonr", which is not a holder's name, and no licence text is in the bundle although MIT requires the notice to accompany copies. |
| `I04` | partial | The menu shows the name and version (`Bundle.main` version, `AppModel.swift`). No repository or issue link was found in the app's views; read from source, the app was not operated. |
| `I05` | pass | `CFBundleIconFile` is `AppIcon` and `AppIcon.icns` is in the `v0.1.2` bundle. No store listing or site exists. |
| `I06` | pass | `__VERSION__` in `Info.plist` is replaced by the builder from the tag (`Scripts/bundle.sh` locally, the broker for releases); every other value is a constant in that one source-controlled file. |
| `T01` | na | Not a documentation repository; its product is an application. |
| `T02` | na | Not a documentation repository. |
| `T03` | na | Not a documentation repository. |
| `T04` | na | Not a documentation repository. |
| `T05` | na | Not a documentation repository. |
| `W01` | na | No site exists: the repository has a README and no website, no Pages source and no homepage. |
| `W02` | na | No site exists (see `W01`). |
| `W03` | na | No site exists (see `W01`). |
| `W04` | na | No site exists (see `W01`). |
| `W05` | na | Retired. |
| `W06` | na | Retired. |
| `W07` | na | No site exists (see `W01`). |
| `W08` | na | No site exists (see `W01`). |
| `W09` | na | No site exists (see `W01`). |
| `G01` | pass | `AGENTS.md` at the root. |
| `G02` | pass | Purpose, layout table and the three validation commands; run locally and green in CI. |
| `G03` | pass | History rewriting, force pushes, secrets, releases and tags, and data-destructive commands are named. Deployments are not named: the repository deploys nothing (treated as not applicable). |
| `G04` | pass | No tool-specific instruction file exists. `.github/github-app.yml` points at `AGENTS.md`. |
| `G05` | pass | The validation sequence is named in `AGENTS.md` and passes. |
| `G06` | pass | `.build/` is git-ignored; `AGENTS.md` lists the generated icon, the badge output and the machine-owned `Package.resolved`. |
| `G07` | pass | `AGENTS.md` "Attribution" states the trailer and review expectation. |
| `G08` | pass | `.github/github-app.yml` is committed, non-empty and points at `AGENTS.md`. |
| `L01` | partial | The README declares German as the primary language in one sentence. The standard asks for English unless the subject matter is inherently German, which it is not. Recorded as a stated choice the criterion does not allow. |
| `L02` | pass | Sampled `MenuContent`, `StatusWindow`, `ActivityWindow`, the editor views and the command line help: user-facing strings are German, the declared primary language. |
| `L03` | pass | The README states German only and that there is no further localization. |
| `L04` | na | One locale and no string catalog. |
| `L05` | partial | The log window's timestamps use a fixed `HH:mm:ss.SSS` pattern in `Log.swift`, not the user's locale. Nothing else formats a displayed date, number or currency by hand. |
| `L06` | na | No translations shipped. |
| `L07` | fail | README, `docs/`, code comments, identifiers in part, the last commit messages and the release notes are German. `AGENTS.md`, the workflows and `.github/` files are English. |
| `X01` | pass | Read from source: standard SwiftUI controls and menu items; the drag gesture for zones has a keyboard-reachable equivalent in the menu ("Aktuelles Fenster festhalten") and the rule editor. The app was not operated. |
| `X02` | partial | One `accessibilityLabel` in the source against several buttons that show only a symbol; standard controls with text supply their own name. Read from source only. |
| `X03` | partial | Platform text styles are used mostly, but a handful of fixed `.system(size:)` fonts and colour-only status uses were found (source read, counts by search). |
| `X04` | fail | The command line output uses Unicode decoration and there is no plain or no-colour mode documented or implemented. |
| `X05` | fail | No statement of accessibility limitations, and none that none are known. |
| `Y01` | pass | README "Sprache und Datenschutz" states that no user data is collected or sent; source agrees (the only network contact is the update check). |
| `Y02` | pass | The one destination, GitHub Releases for the update check, is named with its purpose. Source shows no other address. |
| `Y03` | pass | No analytics, crash reporting or telemetry in source or dependencies (searched for Sentry, Crashlytics, analytics, telemetry). |
| `Y04` | pass | The README names the configuration file and the UserDefaults domain and how to delete them. |
| `Y05` | pass | The README states that no third party receives user content. |
| `Y06` | pass | Data persists only as the configuration file and preferences, and the README says how to delete both. |
| `A01` | na | The repository is not archived. |
| `A02` | na | The repository is not archived. |
| `A03` | na | The repository is not archived. |
| `A04` | na | The repository is not archived. |

## Release smoke test (R05)

Kit: `.github/workflows/smoke-test.yml`, documented in
[`release-smoke-tests.md`](release-smoke-tests.md). Run for `v0.1.2`: workflow run
35648787565, dispatched 2026-09-21 by the assessing agent, queued when this record
was written; the result is not recorded here and is not assumed.
