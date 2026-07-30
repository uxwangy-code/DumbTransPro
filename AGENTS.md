# DumbTransPro Agent Rules

This is the Codex-facing entrypoint for the DumbTransPro app repository. Use
`README.md` for runnable commands and `CLAUDE.md` for product/commercial context.
If rules conflict, follow: current user instruction > `AGENTS.md` > `CLAUDE.md`
/ `README.md` > code convention.

## Project Scope

- macOS menu bar translation app built with Swift 6 and SwiftPM, not an Xcode
  project.
- The repository is public. Keep business strategy, revenue details, private
  credentials, and marketing drafts out of this repo; use
  `/Users/thirty/myproject/side-business` for operating notes.
- Do not remove the release artifact gate or bypass signing/notarization checks
  to make a release faster.

## Development Checks

- For code changes, run the most relevant `swift test --filter ...` first; run
  broader `swift test` when touching shared behavior.
- For release or runtime configuration changes, also run
  `bash scripts/bundle.sh` or the project release script as appropriate.
- Release artifacts must pass `scripts/check-release-artifact.sh`; it verifies
  version/build plus `DTPUsageTelemetryURL`, `DTPLicensePurchaseURL`, and
  `DTPLicenseVerifyURL` in the final `Info.plist`.

## Release Flow

- Current production release: `v1.5.4` / build `154`, published on 2026-07-30
  at <https://github.com/uxwangy-code/DumbTransPro/releases/tag/v1.5.4>.
- Formal release entrypoint:

```bash
DUMBTRANS_SIGNING_IDENTITY="Developer ID Application: yan wang (8896V2K559)" \
DUMBTRANS_NOTARY_PROFILE="dumbtrans-notary" \
bash scripts/release-update.sh <version> <build> RELEASE_NOTES.md
```

- Production defaults embedded by `scripts/release-update.sh`:

```bash
DUMBTRANS_USAGE_TELEMETRY_URL="https://telemetry.whimsycode.com/events"
DUMBTRANS_LICENSE_PURCHASE_URL="https://uxwangy-code.github.io/DumbTransPro/#pricing"
DUMBTRANS_LICENSE_VERIFY_URL="https://license.whimsycode.com/api/licenses/verify"
```

- Public release requires explicit user approval before `git push`, GitHub
  Release creation, tag push, or publishing `docs/appcast.xml`.
- Before calling a release done, verify all three:
  - `spctl -a -vv --type execute build/DumbTransPro.app` reports
    `accepted` / `Notarized Developer ID`;
  - `xcrun stapler validate build/DumbTransPro.app` succeeds;
  - GitHub Release asset size, `docs/appcast.xml`, and the public Pages appcast
    all point to the same version and zip.

## Signing And Notarization

- Developer ID identity: `Developer ID Application: yan wang (8896V2K559)`.
- Notary keychain profile: `dumbtrans-notary`.
- If `notarytool` returns `403` with "required agreement is missing or has
  expired", check Apple Developer Account agreements for team `8896V2K559`.
  App Store Connect Paid Apps bank/tax setup is not required for Developer ID
  notarization.

## Cross-Repo Coordination

- The telemetry collector lives in
  `/Users/thirty/myproject/DumbTransProTelemetry`.
- New app releases must embed `https://telemetry.whimsycode.com/events`; the
  old `workers.dev` endpoint is kept only so older app builds still work.
- When changing telemetry payload fields or endpoint defaults, update both this
  repo and the telemetry repo docs/tests in the same cleanup pass.
