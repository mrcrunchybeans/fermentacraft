# CI/CD with GitHub Actions for FermentaCraft

This repo is wired to build iOS on GitHub-hosted macOS runners so you don’t need a personal Mac for archiving or uploading to TestFlight/App Store.

## Workflows in this repo

- iOS CI (Simulator): `.github/workflows/ios-ci.yml`
  - Builds and tests for the iOS Simulator (no codesign). Useful for PRs.
- iOS Release (TestFlight): `.github/workflows/ios-release.yml`
  - Builds a signed Release IPA and uploads it to TestFlight using App Store Connect API.
- Android Release (Play Console): `.github/workflows/android-release.yml`
  - Builds a signed AAB and uploads it to Google Play Console.

## Prerequisites (one-time)

- Apple Developer Program account (active) and App Store Connect access.
- App ID capabilities configured (Sign in with Apple, In‑App Purchases). Entitlements match the app.
- Apple Distribution Certificate (.p12) and password.
- App Store Connect API Key (Key ID, Issuer ID, and Private Key text).
- RevenueCat Public SDK Keys for iOS and Android.
- Google Play Console access and service account JSON key.

### Generate/signing assets

- Apple Distribution cert (.p12)
  - If you already have a cert: export from Keychain as `.p12` with a password.
  - If you need to create one without a Mac, you can use OpenSSL to generate a CSR and then convert the resulting cert + private key into a `.p12`.
- App Store Connect API Key
  - App Store Connect → Users and Access → Keys → Generate API Key (App Manager role or higher).
- Google Play service account JSON
  - In Play Console, navigate to Settings → Developer account → API access, and create a service account.

## Required GitHub Secrets

Create these repository secrets (Settings → Secrets and variables → Actions):

- `RC_API_KEY_IOS` — RevenueCat iOS public SDK key (appl_...)
- `RC_API_KEY_ANDROID` — RevenueCat Android public SDK key (goog_...)
- `IOS_DISTRIBUTION_CERT_P12` — base64 of your Apple Distribution `.p12`
- `IOS_CERT_PASSWORD` — password for the `.p12`
- `APP_STORE_CONNECT_API_KEY_ID` — ASC API Key ID
- `APP_STORE_CONNECT_API_ISSUER_ID` — ASC Issuer ID
- `APP_STORE_CONNECT_API_PRIVATE_KEY` — contents of the `.p8` private key
- `ANDROID_KEYSTORE_BASE64` — base64 of your `release.keystore`
- `ANDROID_KEYSTORE_PASSWORD` — keystore password
- `ANDROID_KEY_ALIAS` — key alias
- `ANDROID_KEY_PASSWORD` — key password
- `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` — contents of your Play service account JSON (as a single-line JSON string)

Tip to create the base64 string on any machine:

```bash
base64 -w 0 path/to/your_certificate.p12
```

Example to base64 a keystore:

```bash
base64 -w 0 release.keystore
```

## How the workflows work

### iOS CI (Simulator)
- Runs on `push`/`pull_request` to `main`, and on manual dispatch.
- Installs Xcode 16.2 and Flutter 3.35.4, runs `flutter pub get`, `flutter analyze`, `flutter test`, precaches iOS artifacts, and performs a Debug simulator build with `--no-codesign`.
- Uploads the built Simulator app bundle and diagnostics as artifacts.

### iOS Release (TestFlight)
- Triggered manually via the Actions tab (`workflow_dispatch`).
- Steps:
  1. Set up Xcode and Flutter, `flutter pub get`, pods install.
  2. Import signing certificate (from `IOS_DISTRIBUTION_CERT_P12`/`IOS_CERT_PASSWORD`).
  3. Download App Store provisioning profile automatically with ASC API credentials.
  4. Build a release IPA (`flutter build ipa`) with export options `app-store`.
  5. Upload the IPA to TestFlight with Fastlane Pilot and your ASC API key.
- Artifacts include the IPA, Podfile.lock, and key build files for traceability.

### Android Release (Play Console)
- Triggered manually via the Actions tab (`workflow_dispatch`).
- Steps:
  1. Restores Flutter, installs dependencies.
  2. Reconstructs `android/app/release.keystore` from `ANDROID_KEYSTORE_BASE64` and writes `android/key.properties` for Gradle signing.
  3. Optionally sets `flutter.versionCode` in `android/local.properties` so your versionCode monotonically increases (default: GitHub run number).
  4. Builds a release AAB with `flutter build appbundle` passing RevenueCat keys via `--dart-define`.
  5. Uploads to the specified Play track using `fastlane supply` with your service account JSON.
- Artifacts include the built AAB and key build files for traceability.

## Using the workflows

- For continuous checks: rely on "iOS CI (Simulator)" on PRs.
- For releases: open the Actions tab, pick "iOS Release (App Store/TestFlight)", click "Run workflow".
  - Optionally set a custom `build-number`; otherwise the GitHub run number is used.
  - `pubspec.yaml` version `x.y.z+build` feeds into iOS via `$(FLUTTER_BUILD_NAME)` and `$(FLUTTER_BUILD_NUMBER)` (already configured in `ios/Runner/Info.plist`).
- For Android releases: open the Actions tab, pick "Android Release (Play Console)", click "Run workflow".
  - Optionally set the `track` for Play Console (default is `internal`).

## Customization knobs

- Flutter version: adjust `FLUTTER_VERSION` in workflows.
- Xcode version: set via `setup-xcode` action input.
- Minimum iOS version: currently pinned to 15.0 in the workflow to avoid SDK mismatches.
- RevenueCat keys: passed in via `--dart-define` from secrets.

## Troubleshooting

- Codesign: ensure the `.p12` matches the provisioning profile; the download step uses your ASC API creds and `com.fermentacraft` bundle ID.
- Provisioning: if bundle IDs or capabilities don’t match, ASC profile download will fail. Update the App ID capabilities to include SIWA and IAP.
- CocoaPods: transient failures happen. The workflow runs `pod repo update` then `pod install`. If issues persist, clear the cache key.
- Build numbers: App Store requires monotonically increasing build numbers. Override with the input or let the workflow use the GitHub run number.
- RevenueCat offerings (code 23): ensure an uploaded TestFlight build exists, IAPs are attached to the app version, products are localized and cleared for sale, and allow propagation time.
- ATS/Networking: we removed `NSAllowsArbitraryLoads`; all endpoints must be HTTPS or use explicit ATS exceptions.

## What this replaces (so you can ditch a Mac)

- Local Xcode Archive and Transporter upload: now handled in CI.
- Manual signing profile management: CI imports certs and downloads profiles automatically.
- You still need a Mac only for local debugging/simulator runs outside CI. All packaging and distribution are covered by Actions.

## Next steps

- If you also want Android Play Store deploys, add a Linux job to build and sign an AAB and upload with `fastlane supply`.
- Consider GitHub Environments with approvals for production runs to protect secrets.
- Add release notes automation by reading from a CHANGELOG or GitHub tag message.

## Environment protections (Approvals) and scoped secrets

To require approvals before a release deploys and to scope secrets to trusted environments:

1. Go to GitHub → Settings → Environments.
2. Create an environment named `app-store` (used by `.github/workflows/ios-release.yml`).
   - Add Required reviewers (e.g., your account or a team). The workflow will pause until approved.
   - Optionally add environment-specific secrets here instead of repo-level (e.g., the iOS cert and ASC API secrets) for tighter control.
3. Create an environment named `play-store` (used by `.github/workflows/android-release.yml`).
   - Add Required reviewers.
   - Optionally add Android-specific secrets here (keystore, Play service account JSON).

The workflows declare `environment: app-store` and `environment: play-store`, so they’ll automatically enforce these protections.

## Auto-generated release notes (changelog)

Both mobile release workflows generate concise release notes automatically:

- Each workflow checks out with `fetch-depth: 0` to access git history.
- It finds the previous tag (`git describe --tags --abbrev=0`).
- It builds `CHANGELOG.txt` with `git log --pretty=format:'- %s' <prev-tag>..HEAD`.
- If no prior tag exists, it falls back to a single “Automated build” line.
- iOS: notes are passed to TestFlight via Fastlane Pilot `--changelog`.
- Android: notes are passed to Play Console via Fastlane Supply `--release_notes` (English locale by default).

Tips:
- Tag your releases (e.g., `git tag v2.0.0 && git push --tags`) to make the notes reflect changes since the last release.
- You can manually edit `CHANGELOG.txt` in a job step if you want custom content.

## Enabling protections & notes – quick checklist

- Create environments `app-store` and `play-store` with required reviewers.
- (Optional) Move release secrets to those environments for scoping.
- Start tagging releases to improve changelog diffs.
- Trigger the workflows from the Actions tab; they will pause for approval if reviewers are configured.
