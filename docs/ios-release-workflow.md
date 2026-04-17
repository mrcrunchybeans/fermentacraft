# iOS Release Workflow Guide

This guide explains how the workflow in `.github/workflows/ios-release.yml` works, what not to change, and how to troubleshoot common issues.

## Overview
- Builds and signs a Flutter iOS IPA on GitHub macOS-15 runners with Xcode 16.
- Uploads to TestFlight using Fastlane Pilot with App Store Connect API keys.
- Adds guard steps to auto-fix missing platform runtimes and entitlements.

## Required secrets (environment: app-store)
- `IOS_DISTRIBUTION_CERT_P12`: Base64 of your Apple Distribution .p12
- `IOS_CERT_PASSWORD`: Password for the .p12
- `APP_STORE_CONNECT_API_KEY_ID`: App Store Connect API key ID
- `APP_STORE_CONNECT_API_ISSUER_ID`: ASC issuer ID
- `APP_STORE_CONNECT_API_PRIVATE_KEY`: Contents of the .p8 API key
- `RC_API_KEY_IOS`, `RC_API_KEY_ANDROID`: RevenueCat API keys

## Versioning contract
- Marketing version = `X.Y.Z`:
  - `X.Y` from `pubspec.yaml` (any `+build` or `-pre` parts stripped)
  - `Z` (patch) = `GITHUB_RUN_NUMBER * 100 + GITHUB_RUN_ATTEMPT`
- Build number (CFBundleVersion) = same `GITHUB_RUN_NUMBER * 100 + GITHUB_RUN_ATTEMPT`
- Rationale: Always strictly increases on re-runs and across runs. Do not change unless you maintain monotonicity.

## Guard steps you should not remove
- Ensure iOS platform SDK installed + destination preflight: fixes “iOS 18.x is not installed” before archiving.
- Provisioning profile selection with Sign in with Apple: ensures export uses SIWA-enabled profile to avoid ExportArchive errors.
- ExportOptions.plist teamID injection: ensures correct team at export.
- IPA discovery: dynamically finds newest `.ipa` to upload, since filename can vary.

## Safe edit guidelines
- Keep Xcode within 16.x (or verify macos-15 images include the SDKs you need).
- If you alter build-name/build-number logic, keep `X.Y.Z` patch monotonic and aligned with build-number.
- Don’t hardcode `Runner.ipa`; keep glob `build/ios/ipa/*.ipa` and newest-file selection.
- Simulator build is non-blocking and guarded by an SDK probe; don’t remove the guard or it will download 8+ GB runtimes on runners.
- If switching to manual signing, provide a complete `provisioningProfiles` map in `exportOptions.plist` and ensure the chosen profile has the SIWA entitlement for the bundle ID.

## Common issues and fixes
- Destination not found / iOS 18.x not installed:
  - The preflight step will attempt `xcodebuild -downloadPlatform iOS`. If it still fails, check `xcodebuild -showsdks` output in logs.
- ExportArchive entitlement error (SIWA):
  - Recreate the App Store profile for `com.fermentacraft` with “Sign in with Apple” capability enabled on the App ID, then rerun.
- Upload step can’t find IPA:
  - Check the step’s printed directory listing. Ensure the archive/export succeeded and produced an `.ipa` under `build/ios/ipa`.

## How to bump versions intentionally
- Update `version:` in `pubspec.yaml` to change `X.Y`.
- The workflow will handle `Z` and build-number automatically based on run/attempt.

## Running the workflow
- Use the “Run workflow” button on GitHub → choose release channel (optional) and build-number (optional). If you set a build-number manually, ensure it’s higher than previous submissions.

## Contact
If this workflow starts failing due to runner image changes or Xcode updates, search logs for the “Preflight” and “Available SDKs” sections and adapt the Xcode version accordingly.
