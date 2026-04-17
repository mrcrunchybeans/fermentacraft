# FermantaCraft Build & Release Guide

Complete guide for building and releasing FermantaCraft on Android and iOS using GitHub Actions.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Android Release Process](#android-release-process)
  - [Local Android Build](#local-android-build)
  - [GitHub Action: Android Release](#github-action-android-release)
- [iOS Release Process](#ios-release-process)
  - [GitHub Action: iOS Release](#github-action-ios-release)
- [Version Management](#version-management)
- [Required Secrets & Setup](#required-secrets--setup)
- [Troubleshooting](#troubleshooting)
- [Quick Reference](#quick-reference)

---

## Overview

FermantaCraft uses:
- **Flutter 3.35.4** with Dart 3.9.2
- **GitHub Actions** for automated CI/CD
- **Fastlane** for store uploads (Play Console & TestFlight)
- **RevenueCat** for subscription management
- **App Store Connect API** for iOS automation
- **Google Play Developer API** for Android automation

**Build outputs:**
- **Android**: AAB (Android App Bundle) for Play Console
- **iOS**: IPA for TestFlight/App Store

---

## Prerequisites

### Local Development
- Flutter 3.35.4 installed
- Android Studio with SDK 34+ (for Android)
- Xcode 16.2 on macOS (for iOS, CI only)
- Valid signing credentials for both platforms

### Store Accounts
- **Google Play Console** access with release management permissions
- **Apple Developer Program** membership (organization or individual)
- **App Store Connect** access with admin/app manager role

### API Keys
- **RevenueCat** API keys for iOS and Android
- **App Store Connect API** key (.p8 file, issuer ID, key ID)
- **Google Play Service Account** JSON credentials

---

## Android Release Process

### Local Android Build

Build an Android App Bundle (AAB) locally for testing or manual upload:

```powershell
# 1. Navigate to project root
cd c:\Users\Brian\tst\fermentacraft

# 2. Clean previous builds
flutter clean

# 3. Get dependencies
flutter pub get

# 4. Build release AAB
flutter build appbundle --release `
  --dart-define=RC_API_KEY_ANDROID="your_rc_android_key_here" `
  --dart-define=RC_API_KEY_IOS="your_rc_ios_key_here"
```

**Output location:** `build\app\outputs\bundle\release\app-release.aab`

**Note:** The AAB must be signed. Configure signing in `android/key.properties`:

```properties
storePassword=<your_keystore_password>
keyPassword=<your_key_password>
keyAlias=<your_key_alias>
storeFile=<path_to_keystore.jks>
```

### GitHub Action: Android Release

**Workflow file:** `.github/workflows/android-release.yml`

#### Triggering the Workflow

1. Go to **Actions** tab in GitHub
2. Select **"Android Release (Play Console)"** workflow
3. Click **"Run workflow"**
4. Configure options:
   - **track**: `internal`, `alpha`, `beta`, or `production` (default: `internal`)
   - **build-number**: Leave empty to auto-generate (recommended)

#### What It Does

1. **Setup**: Installs Java 17, Flutter 3.35.4
2. **Configure Signing**: Decodes keystore from secrets, sets up `key.properties`
3. **Version**: 
   - Uses `build-number` input OR auto-generates from `GITHUB_RUN_NUMBER`
   - Extracts marketing version (X.Y) from `pubspec.yaml`
4. **Build**: Creates release AAB with RevenueCat keys injected
5. **Generate Release Notes**: Pulls changelog from git commits since last tag
6. **Upload**: Uses Fastlane `supply` to upload to Play Console track
7. **Artifact**: Uploads AAB and release notes as GitHub artifacts

#### Track Progression

- **internal**: Internal testing (team only)
- **alpha**: Closed alpha testers
- **beta**: Open or closed beta testers  
- **production**: Public release

**Best practice:** Test in `internal` → `alpha` → `beta` → `production`

#### Example Run

```
Inputs:
- track: beta
- build-number: (leave empty)

Result:
- versionCode: 12700 (calculated from run #127)
- versionName: 2.0.127 (from pubspec.yaml 2.0 + run number)
- Uploads to beta track
- Users in beta testing group receive update
```

---

## iOS Release Process

iOS builds **must** run through GitHub Actions due to macOS/Xcode requirements.

**Workflow file:** `.github/workflows/ios-release.yml`

**Detailed reference:** See [ios-release-workflow.md](./ios-release-workflow.md) for deep technical details.

### GitHub Action: iOS Release

#### Triggering the Workflow

1. Go to **Actions** tab in GitHub
2. Select **"iOS Release (App Store/TestFlight)"** workflow
3. Click **"Run workflow"**
4. Configure options:
   - **release-channel**: Tag for artifacts (default: `manual`)
   - **build-number**: Leave empty to auto-generate (recommended)

#### What It Does

1. **Setup macOS Runner**: Uses macOS-15 with Xcode 16.2
2. **Install iOS SDK**: Force-downloads iOS platform runtime if missing (fixes common errors)
3. **Flutter Setup**: Installs Flutter 3.35.4, precaches iOS artifacts
4. **Dependencies**: Runs `pod install` in `ios/` directory (with retry logic)
5. **Simulator Build** (optional): Builds debug app for testing on simulator
6. **Signing**:
   - Imports distribution certificate (.p12)
   - Downloads App Store provisioning profile
   - **Critical**: Selects profile with "Sign in with Apple" entitlement
7. **Version**:
   - Calculates monotonic build-number: `(run_number × 100) + attempt`
   - Derives marketing version: `X.Y.Z` (Z = same as build-number)
8. **Build IPA**: Runs `flutter build ipa` with RevenueCat keys
9. **Upload to TestFlight**: Uses Fastlane `pilot` with App Store Connect API
10. **Artifacts**: Uploads IPA, changelog, project files

#### Version Formula

```
build-number = (GITHUB_RUN_NUMBER × 100) + GITHUB_RUN_ATTEMPT
build-name (marketing version) = X.Y.Z

Example (run #42, attempt 1):
- build-number: 4201
- build-name: 2.0.4201
```

**Why this formula?**
- Guarantees **strictly increasing** build numbers on re-runs
- Avoids "closed train" errors in App Store Connect
- Each re-run gets unique version (attempt increments)

#### Example Run

```
Inputs:
- release-channel: v2.1-beta
- build-number: (leave empty)

Result:
- Run #50, Attempt 1
- build-number: 5001
- build-name: 2.0.5001
- Uploads to TestFlight
- Available for internal/external testing
```

---

## Version Management

### pubspec.yaml

The **source of truth** for marketing version:

```yaml
version: 2.0.0+1
```

- `2.0.0` = Marketing version (X.Y.Z format)
- `+1` = Build number (ignored by CI, overridden)

### CI Version Override

Both workflows **override** build numbers:

**Android:**
```yaml
versionCode: ${{ inputs.build-number || env.GITHUB_RUN_NUMBER }}
versionName: X.Y.<run_number>
```

**iOS:**
```bash
BUILD_NUMBER=$(( GITHUB_RUN_NUMBER * 100 + ATTEMPT ))
BUILD_NAME=X.Y.$BUILD_NUMBER
```

### Manual Version Bump

To release a new **major** or **minor** version:

1. Edit `pubspec.yaml`:
   ```yaml
   version: 2.1.0+1  # Bump 2.0 → 2.1
   ```

2. Commit and push:
   ```powershell
   git add pubspec.yaml
   git commit -m "chore: bump version to 2.1.0"
   git push
   ```

3. Trigger workflows (they'll use 2.1 as base)

---

## Required Secrets & Setup

### GitHub Environments

Create two environments in repository settings:

1. **play-store** (Android)
2. **app-store** (iOS)

### Android Secrets (play-store environment)

| Secret Name | Description |
|------------|-------------|
| `UPLOAD_KEYSTORE_BASE64` | Base64-encoded keystore file (.jks) |
| `KEYSTORE_PASSWORD` | Keystore password |
| `KEY_ALIAS` | Key alias name |
| `KEY_PASSWORD` | Key password |
| `PLAY_CONSOLE_SERVICE_ACCOUNT` | Google Play service account JSON (base64) |
| `RC_API_KEY_ANDROID` | RevenueCat Android API key |
| `RC_API_KEY_IOS` | RevenueCat iOS API key (needed for dart-defines) |

**Generate keystore base64:**
```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("path\to\keystore.jks"))
```

**Generate service account JSON base64:**
```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("path\to\service-account.json"))
```

### iOS Secrets (app-store environment)

| Secret Name | Description |
|------------|-------------|
| `IOS_DISTRIBUTION_CERT_P12` | Base64-encoded distribution certificate (.p12) |
| `IOS_CERT_PASSWORD` | Certificate password |
| `APP_STORE_CONNECT_API_KEY_ID` | API Key ID (e.g., `ABC123DEFG`) |
| `APP_STORE_CONNECT_API_ISSUER_ID` | Issuer ID (UUID format) |
| `APP_STORE_CONNECT_API_PRIVATE_KEY` | Raw .p8 file contents (with BEGIN/END lines) |
| `RC_API_KEY_IOS` | RevenueCat iOS API key |
| `RC_API_KEY_ANDROID` | RevenueCat Android API key (needed for dart-defines) |

**Generate certificate base64:**
```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("path\to\certificate.p12"))
```

**Get .p8 contents:**
```powershell
Get-Content path\to\AuthKey_ABC123.p8 -Raw
```

### Setting Up App Store Connect API

1. Go to [App Store Connect](https://appstoreconnect.apple.com/)
2. **Users and Access** → **Keys** (under Integrations)
3. Click **+** to generate new key
4. Select **Admin** or **App Manager** role
5. Download `.p8` file (can only download once!)
6. Note the **Key ID** and **Issuer ID**

### Sign in with Apple Requirement

⚠️ **Critical for iOS builds:**

The iOS workflow REQUIRES a provisioning profile with **Sign in with Apple** capability:

1. Go to [Apple Developer Portal](https://developer.apple.com/)
2. **Certificates, Identifiers & Profiles**
3. Select your App ID (`com.fermentacraft`)
4. Edit capabilities → Enable **Sign in with Apple**
5. **Profiles** → Find your App Store Distribution profile
6. Delete and regenerate (or edit and regenerate)
7. Re-run the GitHub Action (it auto-downloads the new profile)

**Without this:** ExportArchive will fail with entitlement errors.

---

## Troubleshooting

### Android Issues

#### Build Fails: "Keystore not found"

**Cause:** `UPLOAD_KEYSTORE_BASE64` secret is invalid or missing.

**Fix:**
1. Verify secret exists in `play-store` environment
2. Re-encode keystore:
   ```powershell
   [Convert]::ToBase64String([IO.File]::ReadAllBytes("upload-keystore.jks")) | Set-Clipboard
   ```
3. Update secret with clipboard contents

#### Upload Fails: "Version code already exists"

**Cause:** You're trying to upload a build-number that's already in Play Console.

**Fix:**
- Use a higher `build-number` input
- OR wait for next run (auto-increments from run number)
- OR delete draft release in Play Console

#### Fastlane Supply Errors

**Common issues:**
- Service account lacks permissions → Add to Play Console users with release manager role
- API not enabled → Enable Google Play Developer API in Google Cloud Console
- JSON format → Ensure service account JSON is valid and base64-encoded correctly

### iOS Issues

#### "iOS 18.2 is not installed" / Destination Errors

**Cause:** iOS platform runtime missing on runner.

**Fix:** The workflow auto-fixes this with `xcodebuild -downloadPlatform iOS`. If it persists:
1. Check "Ensure iOS platform SDK is installed" step logs
2. Verify "Preflight iOS destination" passes
3. Report to GitHub if runner provisioning is broken

#### ExportArchive Fails: "Sign in with Apple entitlement missing"

**Cause:** Provisioning profile doesn't include SIWA capability.

**Fix:**
1. Regenerate profile in Apple Developer Portal (see setup section)
2. Ensure `Runner.entitlements` has:
   ```xml
   <key>com.apple.developer.applesignin</key>
   <array>
       <string>Default</string>
   </array>
   ```
3. Re-run workflow (auto-downloads new profile)

#### Upload to TestFlight Fails

**Cause:** Invalid API key or permissions issue.

**Fix:**
1. Verify API key has Admin or App Manager role
2. Check `.p8` contents in secret (must include `-----BEGIN PRIVATE KEY-----`)
3. Verify Key ID and Issuer ID match App Store Connect
4. Check App Store Connect for stuck/processing builds (may need 24h)

#### IPA Not Found After Build

**Cause:** Export failed or IPA naming changed.

**Fix:**
1. Check "Build iOS IPA" step logs for export errors
2. Workflow auto-discovers `*.ipa` in `build/ios/ipa/`
3. If export fails, check signing/provisioning errors above

### Version Issues

#### "Closed train" Error (iOS)

**Cause:** Submitting a build with same or lower version than existing approved/processing build.

**Fix:** The workflow's formula prevents this. If you see it:
1. Check App Store Connect for stuck builds
2. Manually specify higher `build-number` input
3. Never manually edit the version formula in workflow

#### Build Numbers Out of Sync

**Situation:** Android at versionCode 300, iOS at 5001.

**Solution:** This is NORMAL. Platforms use different formulas:
- Android: Simple run number
- iOS: run × 100 + attempt (for re-run safety)

They don't need to match. Each platform's build numbers only compare within that platform.

---

## Quick Reference

### Triggering Releases

**Android Internal Testing:**
```
Actions → Android Release → Run workflow
- track: internal
- build-number: (empty)
```

**Android Beta Release:**
```
Actions → Android Release → Run workflow
- track: beta
- build-number: (empty)
```

**Android Production:**
```
Actions → Android Release → Run workflow
- track: production
- build-number: (empty)
```

**iOS TestFlight:**
```
Actions → iOS Release → Run workflow
- release-channel: beta (or v2.1, etc.)
- build-number: (empty)
```

### Local Testing

**Android AAB:**
```powershell
flutter clean
flutter pub get
flutter build appbundle --release `
  --dart-define=RC_API_KEY_ANDROID="..." `
  --dart-define=RC_API_KEY_IOS="..."
```

**iOS (macOS only):**
```bash
flutter clean
flutter pub get
cd ios && pod install && cd ..
flutter build ios --release
```

### Version Bump Checklist

- [ ] Edit `pubspec.yaml` version (e.g., 2.0.0 → 2.1.0)
- [ ] Commit with message: `chore: bump version to X.Y.Z`
- [ ] Push to `main`
- [ ] Trigger Android workflow (uses 2.1)
- [ ] Trigger iOS workflow (uses 2.1)
- [ ] Verify builds in Play Console & TestFlight
- [ ] Tag release: `git tag v2.1.0 && git push --tags`

### Secret Management

**List secrets (GitHub CLI):**
```powershell
gh secret list --env play-store
gh secret list --env app-store
```

**Set secret:**
```powershell
gh secret set SECRET_NAME --env play-store --body "value"
```

**Set secret from file:**
```powershell
gh secret set PLAY_CONSOLE_SERVICE_ACCOUNT --env play-store `
  < service-account.json
```

---

## Additional Resources

- **Detailed iOS workflow mechanics:** [ios-release-workflow.md](./ios-release-workflow.md)
- **Flutter build documentation:** https://docs.flutter.dev/deployment
- **Fastlane supply (Android):** https://docs.fastlane.tools/actions/supply/
- **Fastlane pilot (iOS):** https://docs.fastlane.tools/actions/pilot/
- **RevenueCat setup:** https://www.revenuecat.com/docs
- **App Store Connect API:** https://developer.apple.com/documentation/appstoreconnectapi

---

## Workflow Status Badges

Add these to `README.md` to monitor workflow health:

```markdown
![Android Release](https://github.com/yourusername/fermentacraft/workflows/Android%20Release%20(Play%20Console)/badge.svg)
![iOS Release](https://github.com/yourusername/fermentacraft/workflows/iOS%20Release%20(App%20Store/TestFlight)/badge.svg)
```

---

## Support

**Workflow issues:** Check Actions tab logs, review troubleshooting section above.

**Store upload issues:** Verify API credentials, check Play Console / App Store Connect dashboards.

**Build failures:** Review step logs in GitHub Actions, check signing certificates and provisioning profiles.

---

*Last updated: 2024 for Flutter 3.35.4 and Xcode 16.2*
