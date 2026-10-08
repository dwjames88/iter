# Licensing

Iter sells signed-release licence keys through Lemon Squeezy. This page covers the app's side: how a key is activated, what is stored and sent, the offline rules, how licensing stays switched off in 0.x, the plan for crediting early buyers at App Store launch, and the Lemon Squeezy setup checklist. The site's side (the `/buy` page, the webhook, the buyer ledger) is in the site repository's `docs/licensing.md`.

The code is the `IterLicensing` module in `Packages/IterKit` (Foundation, Security and CryptoKit only). The Settings screens are `App/Sources/Settings/LicenceSettingsPane.swift` (Mac and iOS) over `LicenceSettingsModel`.

## The flow

1. A buyer pays on the site's `/buy` page (a Lemon Squeezy checkout).
2. Lemon Squeezy emails the receipt with the licence key. The key is also on the buyer's My Orders page (https://app.lemonsqueezy.com/my-orders).
3. In Iter, **Settings ▸ Licence**: paste the key, optionally rename this Mac, choose **Activate**.
4. Later, **Check Now** asks the server again, and **Deactivate This Mac…** frees one of the key's activations so it can be used on another Mac.

"Where's my key?" in Settings opens the site's `/activate` page (`LicenceSetup.activateURL`, built from `LicenceSetup.siteOrigin`, which follows the site's `SITE_ORIGIN`).

## The License API

The app calls three public endpoints of the Lemon Squeezy License API with form-encoded POSTs and `Accept: application/json`. No API key is in the app, and none is needed.

| Call | Endpoint | Docs |
|---|---|---|
| Activate | `POST https://api.lemonsqueezy.com/v1/licenses/activate` | https://docs.lemonsqueezy.com/api/license-api/activate-license-key |
| Validate | `POST https://api.lemonsqueezy.com/v1/licenses/validate` | https://docs.lemonsqueezy.com/api/license-api/validate-license-key |
| Deactivate | `POST https://api.lemonsqueezy.com/v1/licenses/deactivate` | https://docs.lemonsqueezy.com/api/license-api/deactivate-license-key |

Overview: https://docs.lemonsqueezy.com/api/license-api. The docs do not list status codes; `LicenseClient` handles 404 (unknown key), 400 (refused, with a reason), 422 (missing parameter), 429 (rate limit) and `valid: false` bodies. The client rejects a key whose `store_id` or `product_id` differs from the expected ones, and frees the seat it just used.

## What is sent

To Lemon Squeezy: the licence key, the instance name (the Mac's hardware model plus the name the person chose, for example "Mac15,3 – Sam's MacBook"), and, on validate and deactivate, the instance id Lemon Squeezy returned at activation. Nothing else: no analytics, no hardware identifiers, no account.

## What is stored, and where

Everything is in the Keychain, generic-password items under the service `com.dwjames.iter.license`:

- `license`: the key, instance id and name, the time of the last successful validation, the buyer's email and the activation date (JSON), together with an HMAC grace token.
- `salt`: a random per-install salt, the key for the grace token, so the record cannot be edited or copied to another install without the check noticing.
- `trial-start`: when a trial began, if one was ever started. This build never starts one.

Deactivating clears the `license` item.

## Offline rules

- A licence stays valid for 14 days after the last successful check. After that the state is "needs a check" until a validation succeeds.
- If the clock has been set back by more than a day since the last check, the state is also "needs a check".
- A network failure never revokes anything. Validation that cannot reach the server leaves the state to these time rules.
- A key the server reports as disabled, unknown or for another product is treated as revoked: the local activation is cleared. A lapsed key is expired.
- A stored record whose grace token does not verify counts as "needs a check".

## What is gated: nothing, in 0.x

`LicenseGate` reads the Info.plist key `IterLicensingEnforced`, fed by the build setting `ITER_LICENSING_ENFORCED` (in `project.yml`, default `NO`; the iOS app inherits it). `NO`, missing or unrecognised means not enforced, and `LicenseGate.allows(_:state:)` then returns true for every `ProFeature`. No feature is defined as Pro yet, so no code asks the gate.

Settings ▸ Licence is hidden too. Launch with `-IterShowLicensing YES` to show it (`-IterSettingsTab licence` then opens it). Without that switch nothing about licensing is visible. See TESTING.md ("Licence (hidden)").

Turn `ITER_LICENSING_ENFORCED` to `YES` only when a Pro feature has been defined and the Licence pane is shown to everyone.

## Crediting early buyers at App Store launch

The site records every buyer in a Cloudflare D1 ledger (site repository, branch `preview-site`, `docs/licensing.md`). Lemon Squeezy's webhook (`order_created`, `order_refunded`, `license_key_created`) fills one row per order: email, order id, licence key, product and variant, date and refund status. At App Store launch that ledger is the list of who paid and was not refunded.

Options, neutrally:

- **Apple offer codes.** Create offer codes for the App Store app or its in-app purchase and send one to each unrefunded buyer's email. Apple's rules require In-App Purchase for digital unlocks bought inside the app, so a credit that unlocks something in the App Store build should be redeemed through Apple, not through a key typed into the app. Codes can be one-time or custom and have per-quarter limits; check the current limits in App Store Connect.
- **Promo codes.** Promo codes are for paid apps and have a small yearly allowance per version; they suit a handful of people, not a ledger of any size.
- **A "Founding buyer" unlock checked by email or key.** The app (or a Worker) would check the buyer's email or key against the ledger. This keeps an out-of-store entitlement alive inside the store build, which App Store review may question when the unlock was not bought through In-App Purchase. Treat it as the riskiest of the three.
- **Keep the direct build.** Early buyers keep using the signed direct download, which keeps licensing and updating as they are.

The plan this page recommends: issue Apple offer codes to the ledger's emails, and keep the direct licence working for those who prefer it.

## Lemon Squeezy setup checklist

1. Create a Lemon Squeezy account and a store.
2. Set the store currency and tax settings.
3. Create the product "Iter for Mac" (single payment) with one variant.
4. On the variant, enable **Generate license keys**: activation limit 3, no expiry (licence length: lifetime). Docs: https://docs.lemonsqueezy.com/help/licensing/generating-license-keys
5. Note the store id and the product id and put them in `LicenceSetup.clientConfiguration` (`Packages/IterKit/Sources/IterLicensing/LicenceText.swift`) as `expectedStoreID` and `expectedProductID`. These are the `LicenseClient.Configuration` values.
6. Copy the product's checkout (share) URL into the site's `LS_CHECKOUT_URL` (`src/config/site.ts`).
7. In Lemon Squeezy **Settings ▸ Webhooks**: URL `https://<site domain>/api/ls/webhook`; signing secret the same value you give `npx wrangler secret put LS_WEBHOOK_SECRET`; events `order_created`, `order_refunded`, `license_key_created`.
8. Make a test-mode purchase end to end: pay, receive the email, activate in Iter (launched with `-IterShowLicensing YES`), check the ledger row, deactivate, then refund and confirm the key shows as revoked after Check Now.
9. Set the site's `SALES_OPEN` to true and deploy.
10. Turn `ITER_LICENSING_ENFORCED` to `YES` only once a Pro feature is defined.

None of this has been exercised against a live store yet; the tests use a fake `URLProtocol` with the payloads from Lemon Squeezy's documentation.
