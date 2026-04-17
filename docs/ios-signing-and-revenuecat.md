# iOS Signing + RevenueCat Checklist

This checklist fixes the common causes of empty RevenueCat offerings (code 23) and device signing issues.

## 0) TL;DR
- Use the iOS Public SDK key (starts with `appl_`) and pass it at run/build time.
- Set a Current offering in RevenueCat that references valid App Store product IDs.
- Ensure App Store Connect products exist for the bundle id, are Cleared for Sale, and your Agreements are accepted.
- On simulator/device, sign into App Store with a Sandbox Apple ID.

## 1) Xcode project sanity
- Bundle Identifier: `com.fermentacraft` (matches RC + App Store Connect)
- Signing: Automatic, correct Team selected
- Capabilities:
  - Sign in with Apple (present in `Runner/Runner.entitlements`)
  - In‑App Purchase (enable on the App ID in Apple Developer portal)

## 2) RevenueCat app
- Project Settings → Apps → iOS app
  - Public SDK key starts with `appl_`
  - Bundle ID = `com.fermentacraft`

## 3) RevenueCat offerings
- Create an Offering and set it as Current
- Add Packages:
  - Premium Monthly/Yearly → map to App Store subscription products
  - Pro‑Offline (optional) → map to your non‑consumable product
- Entitlements → products grant `premium` and/or `pro_offline`

## 4) App Store Connect (ASC)
- In‑App Purchases:
  - Auto‑renewable subscriptions for monthly/yearly
  - Non‑consumable for Pro‑Offline (if used on iOS)
- Each product:
  - Has price set and localizations
  - is Cleared for Sale (Approved) or at least available to fetch in Sandbox
- Agreements, Tax, and Banking: Accepted (Paid Apps Agreement)
- Subscription Group created

## 5) Device/simulator setup
- On Simulator: Settings → App Store → Sign in with a Sandbox Apple ID
- On Device: also use Sandbox Apple ID for testing
- If stuck, try another simulator runtime or a real device

## 6) Run with RC key
- VS Code: select "Flutter iOS (Simulator) – Inline Key"
- CLI:
  ```bash
  flutter run -d "iPhone 16e" --dart-define=RC_API_KEY_IOS=appl_XXXX
  ```

## 7) What logs to look for
- Configure success:
  - `[RC] iOS API key found: appl_...`
  - `[RC] Successfully configured with API key`
- Offerings error with code 23:
  - Double‑check key, bundle id, RC app, Current offering, ASC product setup, and Sandbox Apple ID

## 8) Common root causes of code 23
- Using Android/`goog_` key on iOS
- RC app’s bundle ID doesn’t match Xcode/ASC
- No Current offering in RC
- RC package points to a product ID that doesn’t exist in ASC
- ASC products not priced/cleared or agreements not accepted
- Not signed into App Store with a Sandbox Apple ID on simulator/device

## 9) Extras
- Propagation time: after creating ASC products, allow 30–120 minutes before first fetch succeeds
- If you use a StoreKit Configuration file locally, ensure the product IDs match RC; otherwise remove it and fetch from ASC

