# Release Lifecycle Handoff

Last updated: 2026-06-29

This note captures the context for the `codex/release-lifecycle-ux` branch so a new machine or chat can continue without replaying the whole discussion.

## What This Branch Changes

- License UX no longer downgrades a previously verified Pro user to Free just because network verification fails. Explicit invalid/refunded/disabled results still deactivate the key.
- Settings now shows Pro verification status, including "last verified" and retry guidance when network verification is currently unavailable.
- Manual "Check for Updates" now gives visible feedback when the current version is already latest, and still opens the Sparkle update window when an update exists.
- The app starts lightweight background update checks and changes the menu title to "发现新版本 x.x.x..." when a newer version is detected.
- Release scripts now pass telemetry, purchase URL, and license verification URL through to the built app.

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

- China: Qianxun virtual-card resale. Create a product page manually, upload generated license TXT inventory, and let buyers receive a card key.
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
DUMBTRANS_LICENSE_PURCHASE_URL="https://your-domain.example/buy"
DUMBTRANS_LICENSE_VERIFY_URL="https://dumbtrans-license-gateway.whimsycode.workers.dev/api/licenses/verify"
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

- runs on Cloudflare Workers + D1 at `https://dumbtrans-license-gateway.whimsycode.workers.dev`;
- exposes `/api/licenses/verify` for the app;
- stores only license HMAC hash and visible suffix, not plaintext keys;
- supports manual smoke/test license issuing;
- supports by-key refund/disable for support;
- supports two-step Qianxun card-stock flow: local TXT generation first, then hash-only import/activation.

The app still keeps Gumroad verifier fallback for existing or overseas keys.

## Open Follow-Ups

- Create the Qianxun product page and connect the domestic website button.
- Generate and import the first small Qianxun TXT inventory only after the product page is ready.
- Decide whether to migrate old Gumroad keys into the new backend or keep app-side Gumroad fallback for the first release.
- Update `docs/index.html` with the real Qianxun purchase URL after the product page is ready.
- Review public legal copy again before launch, especially if the domestic payment provider becomes final.
