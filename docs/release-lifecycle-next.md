# Release Lifecycle Notes

Last updated: 2026-07-30

This note captures release configuration, commercial routing, and operational
checks so a new machine or chat can continue without replaying the whole
discussion.

## Current Production Status

- Latest public release: `v1.5.4` / build `154`, published on 2026-07-30.
- GitHub Release: <https://github.com/uxwangy-code/DumbTransPro/releases/tag/v1.5.4>
- Release asset: `DumbTransPro-1.5.4.zip`, size `3840096` bytes.
- Main release commit: `773ae94 Update appcast for v1.5.4`.
- Public appcast: <https://uxwangy-code.github.io/DumbTransPro/appcast.xml>
- Production telemetry endpoint embedded by default:
  `https://telemetry.whimsycode.com/events`.
- The telemetry `workers.dev` URL remains enabled only for older app builds.

## What The Current Release Line Contains

- Translation Settings now has one explicit AI/offline selector shared by
  in-place translation and lookup translation.
- The app remembers the selected engine, allows offline settings to save without
  an AI provider, and gives clearer guidance for missing API keys or language
  packs.
- Offline short-word translation uses explicit Chinese-English language pairs,
  preventing the system language picker from appearing for words such as
  `Settings`, `API`, `OpenAI`, and `test`.
- License UX no longer downgrades a previously verified Pro user to Free just because network verification fails. Explicit invalid/refunded/disabled results still deactivate the key.
- Settings now shows Pro verification status, including "last verified" and retry guidance when network verification is currently unavailable.
- Manual "Check for Updates" now gives visible feedback when the current version is already latest, and still opens the Sparkle update window when an update exists.
- The app starts lightweight background update checks and changes the menu title to "发现新版本 x.x.x..." when a newer version is detected.
- Release scripts now pass telemetry, purchase URL, and license verification URL through to the built app, then verify the generated app bundle before archiving it.
- `v1.5.4` embeds the custom telemetry domain so corporate networks that block
  `workers.dev` can still report anonymous product events when the user has not
  opted out.

## Release Configuration Gate

`scripts/release-update.sh` defaults production builds to:

```bash
DUMBTRANS_USAGE_TELEMETRY_URL="https://telemetry.whimsycode.com/events"
DUMBTRANS_LICENSE_PURCHASE_URL="https://uxwangy-code.github.io/DumbTransPro/#pricing"
DUMBTRANS_LICENSE_VERIFY_URL="https://license.whimsycode.com/api/licenses/verify"
```

Before creating the release zip, it calls `scripts/check-release-artifact.sh`.
That check must fail if the built `Info.plist` is missing `DTPUsageTelemetryURL`,
`DTPLicensePurchaseURL`, `DTPLicenseVerifyURL`, or the macOS 13 minimum-system
declaration, or if the app version/build does not match the requested release.

## Commercial Direction

The current recommendation is Free + Pro one-time purchase.

- Free should prove the product value quickly: offline translation on macOS 15+, basic AI providers, and a small daily AI quota.
- Pro should unlock long-term high-frequency use: all providers, custom endpoints, unlimited AI actions, and future workflow features.
- Do not start with a subscription while users provide their own AI API keys. Subscription only becomes natural later if DumbTrans Pro provides hosted AI quota.

## Pricing

First paid launch:

- Early bird: CNY 9.9
- Standard price: CNY 39

Possible future paid layer:

- Keep Pro as one-time purchase for local/BYOK use.
- Add a separate hosted AI service fee only if the product starts providing AI API quota directly.

## Payment Channel Plan

Short term:

- China: Qianxun virtual-card resale. Buyers receive a card key that is also the DumbTrans Pro license key.
- Overseas: keep Gumroad.
- Do not add Dodo Payments or Paddle yet.
- Do not do automatic region detection in the app or website. Show two purchase entrances and let users choose.

Website copy should make this explicit:

- "国内用户：微信/支付宝购买"
- "海外用户：Gumroad 购买"

## License Architecture

The app should not call domestic payment providers directly.

Client build-time configuration:

```bash
DUMBTRANS_LICENSE_PURCHASE_URL="https://uxwangy-code.github.io/DumbTransPro/#pricing"
DUMBTRANS_LICENSE_VERIFY_URL="https://license.whimsycode.com/api/licenses/verify"
```

Client verification request contract:

```json
{
  "license_key": "DTP-XXXX",
  "increment_uses": true,
  "app": "DumbTransPro"
}
```

Client accepts either of these successful response shapes:

```json
{ "valid": true }
```

```json
{ "is_valid": true }
```

Invalid/refunded/disabled responses should return:

```json
{
  "valid": false,
  "reason": "refunded"
}
```

The deployed backend now:

- runs on Cloudflare Workers + D1 at `https://license.whimsycode.com`;
- exposes `/api/licenses/verify` for the app;
- stores only license HMAC hash and visible suffix, not plaintext keys;
- supports manual smoke/test license issuing;
- supports by-key refund/disable for support;
- supports two-step Qianxun card-stock flow: local TXT generation first, then hash-only import/activation.
- current Qianxun product: `https://www.qianxun1688.com/details/2EB3C4E0`.
- first Qianxun batch is already active in production: 50 `card_stock` licenses imported into D1 and uploaded to Qianxun on 2026-06-29.

The app still keeps Gumroad verifier fallback for existing or overseas keys.

## Operational Invariants

- Keep future Qianxun batches import-before-upload: generate TXT, import the same TXT into the gateway, verify one suffix/key, then upload the TXT to Qianxun.
- Keep `docs/index.html` domestic button pointed at the current Qianxun product URL.
- Keep new app releases pointed at `https://telemetry.whimsycode.com/events`.

## Open Follow-Ups

- Decide whether to migrate old Gumroad keys into the new backend or keep app-side Gumroad fallback for the first release.
- Review public legal copy again before launch, especially if the domestic payment provider becomes final.
