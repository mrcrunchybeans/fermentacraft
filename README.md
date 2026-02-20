# 🍎 Cider-Craft (Codename)














































































































































- Total time: ___________- Store submission time: ___________- Build time: ___________Time taken:___________________________________________________________________________________________________________________________________________________________________________________________________Issues encountered:Release Manager: ___________Version: ___________Date: ___________## Notes   - [ ] Document issue in changelog   - [ ] Notify users via support channels   - [ ] Update GitHub release notes with known issues3. **Communication**   - [ ] Create new release with patch version bump   - [ ] Test thoroughly   - [ ] Fix the issue   - [ ] Create hotfix branch from release tag2. **Fix Actions**   - [ ] Post notice on support channels   - [ ] Mark release as draft on GitHub   - [ ] Halt rollout in Play Console (if gradual rollout)1. **Immediate Actions**If critical issues are discovered:## Rollback Plan (if needed)- [ ] Close milestone/project in GitHub (if using)- [ ] Monitor crash reports and user feedback  - [ ] Email newsletter (if applicable)  - [ ] Discord/Slack  - [ ] Social media  - [ ] GitHub Discussions- [ ] Announce release:- [ ] Update website if needed  - [ ] App Store: https://apps.apple.com/app/fermentacraft (when approved)  - [ ] Microsoft Store: https://apps.microsoft.com/store/search?q=fermentacraft  - [ ] Google Play: https://play.google.com/store/apps/details?id=com.fermentacraft  - [ ] GitHub: https://github.com/[owner]/fermentacraft/releases- [ ] Verify release is live on all platforms:## Post-Release- [ ] Submit for App Store review when ready- [ ] Submit for external testing (optional)- [ ] Test build on iOS device- [ ] Add to TestFlight for internal testing- [ ] Verify build appears in TestFlight- [ ] Navigate to [App Store Connect](https://appstoreconnect.apple.com)### Apple App Store (via TestFlight)- [ ] Monitor certification status- [ ] Submit for certification- [ ] Update store listing if needed- [ ] Copy/paste changelog- [ ] Upload `.msix` file- [ ] Create new submission- [ ] Navigate to [Partner Center](https://partner.microsoft.com/dashboard)### Microsoft Store- [ ] Monitor rollout status- [ ] Submit for review- [ ] Review release- [ ] Fill in release notes (all supported languages)- [ ] Copy/paste changelog from `CHANGELOG-vX.X.X.txt`- [ ] Upload `.aab` file- [ ] Create new production release- [ ] Navigate to [Play Console](https://play.google.com/console)### Google Play Console## Store Submissions- [ ] Tag matches version (vX.X.X)- [ ] Release notes are correct  - [ ] Changelog  - [ ] Windows MSIX  - [ ] Android APKs (3 files)  - [ ] Android App Bundle (.aab)- [ ] All artifacts uploaded:- [ ] Release created at: https://github.com/[owner]/fermentacraft/releases## GitHub Release- [ ] TestFlight upload succeeds- [ ] Build completes successfully- [ ] Monitor workflow at: https://github.com/[owner]/fermentacraft/actions- [ ] GitHub Actions workflow started### iOS- [ ] Test MSIX installation on Windows 10/11- [ ] `fermentacraft-vX.X.X.msix` created- [ ] `fermentacraft.exe` runs without errors### Windows- [ ] Test install APK on physical device- [ ] Split APKs exist (arm64-v8a, armeabi-v7a, x86_64)- [ ] `fermentacraft-vX.X.X.aab` exists### Android## Verify Builds- [ ] Verify all artifacts in `release-artifacts/` directory- [ ] Review generated `CHANGELOG.txt`- [ ] Script completes successfully  ```  .\scripts\release.ps1 -VersionBump patch  # OR for more control    .\quick-release.ps1  # Standard patch release  ```powershell- [ ] Run release script:- [ ] Decide on version bump type (patch/minor/major)## Run Release Script- [ ] Latest changes pulled (`git pull`)- [ ] On `main` branch (`git branch`)- [ ] Git working directory is clean (`git status`)- [ ] `android/key.properties` exists and is valid- [ ] `.secrets/.env` file is configured with all required secrets- [ ] No known critical bugs- [ ] All tests pass locally- [ ] All features for this release are merged to `main`## Pre-ReleaseUse this checklist when creating a new release.**Cider-Craft** is the codename for the **FermentaCraft** source project.  
It’s a Flutter-based app designed for homebrewers who focus on **cider, mead, kombucha, and fruit wines**.  

Think **Brewfather**, but crafted specifically for fruit fermenters.  
Cider-Craft combines recipe design, fermentation tracking, inventory, and tools in a modern, local-first package.

<p align="center">
  <a href="https://play.google.com/store/apps/details?id=com.fermentacraft">
    <img src="https://img.shields.io/badge/Google_Play-Download-brightgreen?logo=googleplay&logoColor=white" alt="Get it on Google Play">
  </a>
  <a href="https://github.com/mrcrunchybeans/FermentaCraft/releases/latest">
    <img src="https://img.shields.io/github/v/release/mrcrunchybeans/FermentaCraft?label=Latest%20Release&color=blue" alt="Latest Release">
  </a>
  <a href="https://github.com/mrcrunchybeans/FermentaCraft/releases/latest">
    <img src="https://img.shields.io/badge/Windows-.exe-blue?logo=windows" alt="Windows Download">
  </a>
  <a href="https://github.com/mrcrunchybeans/cider-craft/issues">
    <img src="https://img.shields.io/badge/Issues-Welcome-orange" alt="Issues Welcome">
  </a>
  <a href="#firebase-ios-build-notes">
    <img src="https://img.shields.io/badge/CI-iOS_Builds-lightblue?logo=apple" alt="iOS CI Build Info">
  </a>
</p>


---

## 🎯 Why Cider-Craft?

Most brewing software focuses on beer. Cider-Craft fills the gap for makers of:

- 🍏 Hard cider  
- 🍯 Mead  
- 🍓 Fruit wines, melomels, cysers, pyments, and blends  
- 🍵 Kombucha and experimental ferments  

It’s built from the ground up with:

- Juice/concentrate/honey/fruit-based fermentables  
- Additive tracking (pectic enzyme, sulfites, nutrients, tannin, etc.)  
- Advanced gravity, pH, acidity, and SO₂ calculators  
- Batch + fermentation chart tracking with FSU metrics  
- Inventory management & event logging  
- Local-first Hive storage with optional cloud sync (planned)

---

## 🧰 Features at a Glance

### 🧪 Recipe Builder
- Ingredients: juice, fruit, concentrate, honey, sugar  
- Additives: pectic enzyme, acid blend, tannin, Campden, nutrients, custom  
- Yeast: select from common strains or define your own  
- Targets: OG, FG, ABV, pH input with **acidity classification**  
- Fermentation profile builder with multi-stage schedules  
- Tagging system to organize recipes (e.g. “sweet”, “session”, “apple-only”)

### 📐 Smart Calculators
- OG, FG, ABV estimator  
- Gravity adjustment (sugar addition or dilution by batch size + sugar type)  
- Hydrometer temperature correction (60 °F baseline)  
- SO₂ dosage estimator by pH & volume (grams or Campden tablets)  
- Acidity classifier (TA/malic acid scale)  
- FSU (Fermentation Speed Units) tracker  

### 📊 Fermentation Charting
- Plot SG and temperature over time  
- Stage overlays (primary, secondary, cold crash, conditioning)  
- Day/date labels, tooltips, and annotations  
- FSU overlay for fermentation speed analysis  

### 🧾 Inventory Management
- Track ingredient amounts, units, and categories  
- Cost-per-unit + purchase history  
- Expiration reminders  
- Notes + adjustments for real-time stock  

### 🧪 Measurement & Batch Tracking
- Record SG, temperature, and notes (each optional)  
- Manage batch-specific yeast, additives, and events  
- Plan vs. actual stages (racking, bottling, conditioning)  
- Clone recipes into new batches  

### ⚙️ Customization
- Settings for temperature (°C/°F), weight/volume units, pH rounding  
- Dark & light themes  
- Persistent settings via Hive  
- Planned: cloud backup + device sync  

---

## 🧪 Tools Suite

The standalone **Tools Page** provides cider-first calculators:

- ✅ ABV Calculator  
- ✅ Gravity Adjustment  
- ✅ SO₂ Estimator by pH  
- ✅ Campden Tablet Converter  
- ✅ Acidity Classifier (TA-based)  
- ✅ Hydrometer Correction (temp-based)  
- ✅ Temperature Converter (°C/°F/K)  
- ✅ Unit Converter (volume + weight)  
- ✅ Bubble Counter (fermentation activity)  

---

## 📸 Screenshots

_(internal only — not included in this repo)_  
UI inspired by Brewfather, with collapsible sections, structured inputs, fermentation charts, and modern theming.

---

## 🛠 Installation

### Prerequisites
- [Flutter 3.x](https://flutter.dev)  
- Dart SDK  
- Android Studio or VS Code  
- Emulator or physical device (iOS + Android)  
- Packages managed via `pubspec.yaml` (Hive, Provider, fl_chart, RevenueCat, Firebase, etc.)

### Setup

```bash
git clone https://github.com/mrcrunchybeans/cider-craft.git
cd cider-craft
flutter pub get
flutter run
````

---

## 📂 Repository Structure

```
/lib
  models/        # Hive-backed data models (Recipe, Batch, Inventory, Tags, etc.)
  pages/         # UI pages (Recipes, Batches, Tools, Inventory, Settings)
  widgets/       # Shared widgets (dialogs, forms, chart components)
  utils/         # Calculation logic (ABV, SG correction, SO₂, acidity, FSU, etc.)
  services/      # Sync, feature gating, Firebase/RevenueCat integrations
```

---

## ✅ Developer Onboarding Checklist

For new developers joining the project:

1. **Clone & install dependencies**

   ```bash
   git clone https://github.com/mrcrunchybeans/cider-craft.git
   cd cider-craft
   flutter pub get
   ```

2. **Flutter environment**

   * Install Flutter 3.x (stable channel).
   * Confirm with `flutter doctor`.

3. **Local configuration**

   * Create a `.env` file (not committed) with any local keys if needed.
   * Example placeholders:

     ```
     FIREBASE_API_KEY=your-key-here
     REVENUECAT_API_KEY=your-key-here
     ```
   * Android/iOS builds will reference Firebase config JSON/Plist (ask repo owner).

4. **Firebase setup**

   * Download `google-services.json` (Android) and `GoogleService-Info.plist` (iOS).
   * Place them in the appropriate `/android/app` and `/ios/Runner` directories.
   * Required for analytics, crash reporting, and optional sync features.

5. **RevenueCat setup**

   * Ensure the correct `REVENUECAT_API_KEY` is in place.
   * Matches in-app purchase setup for FermentaCraft Pro.

6. **Hive & build runner**

   * Run:

     ```bash
     flutter packages pub run build_runner build --delete-conflicting-outputs
     ```
   * Ensures all Hive adapters are generated.

7. **Run the app**

   * On Android: `flutter run`
   * On iOS: open with Xcode or run via `flutter run`

8. **Coding conventions**

   * Use `feature/branch-name` for new features.
   * Commit with clear messages.
   * PR into `main` after review.

---

## 🚀 Release Workflow

### Automated Release (Recommended)

Use the automated release script to build all platforms and create releases:

```powershell
# Quick standard release (patch version bump)
.\quick-release.ps1

# Or use the full script with options
.\scripts\release.ps1 -VersionBump minor
.\scripts\release.ps1 -ReleaseNotes "Major feature update"
.\scripts\release.ps1 -DryRun  # Test without making changes
```

The script automatically:
- ✅ Increments version number in `pubspec.yaml`
- ✅ Generates changelog from git commits
- ✅ Builds Android (AAB + split APKs)
- ✅ Builds Windows (EXE + MSIX)
- ✅ Creates GitHub release with artifacts
- ✅ Triggers iOS TestFlight build

**See [Release Script Guide](docs/release-script-guide.md) for full documentation.**

### Manual Release (Advanced Users)

When preparing a manual release:

1. **Update versioning**

   * Update `pubspec.yaml` with the new version number.
   * Update changelog if needed.

2. **Build Android APKs**

   ```bash
   flutter build apk --release --split-per-abi
   ```

   Produces:

   * `arm64-v8a` (most devices)
   * `armeabi-v7a` (older devices)
   * `x86_64` (emulators/rare Intel devices)

3. **Build Android App Bundle (AAB) for Google Play**

   ```bash
   flutter build appbundle --release
   ```

   Produces:

   * `app-release.aab` in `/build/app/outputs/bundle/release/`
   * Upload this to the **Google Play Console** for Play Store distribution.

4. **Build Windows portable app**

   ```bash
   flutter build windows
   ```

   Then zip the `build/windows/runner/Release` folder into a portable `.exe` package.

5. **Test locally**

   * Install the `.apk` files on a physical Android device.
   * Run the `.exe` on Windows to confirm portable execution.

6. **Publish artifacts**

   * Copy the built `.apk` files, `.aab`, and Windows `.exe` package into the [FermentaCraft public repo releases](https://github.com/mrcrunchybeans/FermentaCraft/releases).
   * Draft a new release with proper version tag (`vX.Y.Z`).
   * Attach the binaries.

7. **Verify Play Store build**

   * Upload the `.aab` to the Google Play Console.
   * Ensure version codes match and rollout completes.

### Android Play upload (signed)

If you’re shipping to Play, you must have the upload keystore and `key.properties` locally:

1) Copy `android/key.properties.example` to `android/key.properties` (do **not** commit) and fill in your keystore info. The `storeFile` path is relative to the repo root.
2) Place your upload keystore at the path referenced by `storeFile`.
3) Ensure `play_api_key.json` (Play service account with Release Manager/Admin) is in the repo root for fastlane uploads.
4) Build (and optionally upload) from Windows PowerShell:

```pwsh
pwsh scripts/build_android_release.ps1             # builds signed AAB
pwsh scripts/build_android_release.ps1 -UploadToPlay -Track internal  # build + upload (requires fastlane + play_api_key.json)
```

Common blockers:
- Missing/incorrect keystore → Play rejects because the signature differs from previous uploads.
- Service account lacks permission → “caller does not have permission”; grant Release Manager/Admin in Play Console.
- Version code clash → bump `version`/build number in `pubspec.yaml` before rebuilding.

---

## 👥 Contributing

This repository is private and invite-only.
If you’re on the dev team:

* Use feature branches (`feature/xyz`)
* Open pull requests for review before merging
* Keep commits scoped and descriptive

Bug reports, ideas, and feature discussions happen in Issues and project boards.

---

## 📜 License

**Cider-Craft (codename)**
© 2025 Brian Petry. All rights reserved.

This repository contains the **private source code** for FermentaCraft.
The software is not open-source. Distribution, copying, or modification without explicit permission is prohibited.

---

## 📝 Build Cheat Sheet

For quick builds without scrolling the full workflow:

```bash
# Split APKs for each ABI (arm64, armeabi-v7a, x86_64)
flutter build apk --release --split-per-abi

# Android App Bundle for Play Store
flutter build appbundle --release

# Windows portable executable
flutter build windows
```

## Firebase iOS Build Notes

### Known Firebase Dependency Issues

When building for iOS using Flutter 3.35.4 with Firebase 12.0.0, several import issues can occur in the generated Swift files. These issues typically appear in CI environments and need to be patched during the build process (handled in our GitHub Actions workflow):

1. **GTMSessionFetcherCore → GTMSessionFetcher**:
   - Affected files:
     - `ios/Pods/FirebaseFunctions/FirebaseFunctions/Sources/Functions.swift`
     - `ios/Pods/FirebaseAuth/FirebaseAuth/Sources/Swift/Backend/AuthBackend.swift`
   - Error: `import GTMSessionFetcherCore` not found
   - Fix: Replace with `import GTMSessionFetcher`

2. **GoogleUtilities Split Package Imports → GoogleUtilities**:
   - Affected file: `ios/Pods/FirebaseAuth/FirebaseAuth/Sources/Swift/Auth/Auth.swift`
   - Errors:
     - `import GoogleUtilities_AppDelegateSwizzler` not found
     - `import GoogleUtilities_Environment` not found
   - Fix: Replace both with `import GoogleUtilities`

### Automated Fix

A unified patch script is available in the repository to fix all these issues:

```bash
./scripts/firebase_imports_fix.sh
```

This script should be run after `pod install` and before Flutter builds the iOS app. The script:

1. Identifies all affected Swift files
2. Applies the necessary import replacements
3. Verifies that patches were applied correctly
4. Logs all actions for diagnostic purposes

### CI Integration

Our GitHub Actions workflow has been updated to:

1. Automatically apply these patches
2. Capture detailed diagnostic information
3. Verify patch success before building
4. Provide robust error reporting if issues persist

### Manual Fix

If building locally, you may encounter these issues. To fix them manually:

```bash
cd ios
pod install
sed -i '' 's/import GTMSessionFetcherCore/import GTMSessionFetcher/g' Pods/FirebaseFunctions/FirebaseFunctions/Sources/Functions.swift
sed -i '' 's/import GoogleUtilities_AppDelegateSwizzler/import GoogleUtilities/g' Pods/FirebaseAuth/FirebaseAuth/Sources/Swift/Auth/Auth.swift
sed -i '' 's/import GoogleUtilities_Environment/import GoogleUtilities/g' Pods/FirebaseAuth/FirebaseAuth/Sources/Swift/Auth/Auth.swift
sed -i '' 's/import GTMSessionFetcherCore/import GTMSessionFetcher/g' Pods/FirebaseAuth/FirebaseAuth/Sources/Swift/Backend/AuthBackend.swift
```

### Additional Resources

Individual patch files for each issue are also available:
- `fix_use_measured_og_v2.patch`: Fixes Functions.swift
- `fix_google_utilities_auth.patch`: Fixes Auth.swift
- `fix_auth_backend.patch`: Fixes AuthBackend.swift


🚀 *Codename: Cider-Craft → Public app name: FermentaCraft*

