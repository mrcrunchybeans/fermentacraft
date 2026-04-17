# Release Script Documentation

## Quick Start

To create a new release with all platforms:

```powershell
.\scripts\release.ps1
```

## Usage Examples

### Patch Release (default)
```powershell
# Increments patch version: 2.0.0 -> 2.0.1
.\scripts\release.ps1
```

### Minor Release
```powershell
# Increments minor version: 2.0.1 -> 2.1.0
.\scripts\release.ps1 -VersionBump minor
```

### Major Release
```powershell
# Increments major version: 2.1.0 -> 3.0.0
.\scripts\release.ps1 -VersionBump major
```

### With Custom Release Notes
```powershell
.\scripts\release.ps1 -ReleaseNotes "This release includes major bug fixes and new features"
```

### Dry Run (Test Without Making Changes)
```powershell
.\scripts\release.ps1 -DryRun
```

### Skip Specific Platforms
```powershell
# Skip Android build
.\scripts\release.ps1 -SkipAndroid

# Skip Windows build
.\scripts\release.ps1 -SkipWindows

# Skip GitHub release
.\scripts\release.ps1 -SkipGitHub

# Skip iOS workflow trigger
.\scripts\release.ps1 -SkipIOS

# Build only Windows
.\scripts\release.ps1 -SkipAndroid -SkipIOS -SkipGitHub
```

## What the Script Does

The release script automates the following steps:

1. **Version Management**
   - Reads current version from `pubspec.yaml`
   - Increments version based on `-VersionBump` parameter
   - Updates both Flutter version and MSIX version
   - Commits changes and creates git tag

2. **Changelog Generation**
   - Pulls all commits since last tag
   - Formats as markdown
   - Includes custom release notes if provided
   - Saves to `CHANGELOG.txt`

3. **Android Build**
   - Builds App Bundle (.aab) for Play Store
   - Builds split APKs for direct distribution (arm64-v8a, armeabi-v7a, x86_64)
   - Includes RevenueCat API keys

4. **Windows Build**
   - Builds release EXE
   - Builds MSIX package for Microsoft Store
   - Includes Google OAuth secrets

5. **GitHub Release**
   - Creates release with version tag
   - Uploads all build artifacts
   - Includes generated changelog
   - Uses either `gh` CLI or GitHub API

6. **iOS Workflow**
   - Triggers GitHub Actions workflow for iOS build
   - Passes version and build number
   - Uploads to TestFlight automatically

## Prerequisites

### Required

1. **Flutter SDK** - Properly installed and in PATH
2. **Git** - For version control and tagging
3. **Secrets File** - `.secrets/.env` with required API keys:
   ```
   GOOGLE_DESKTOP_CLIENT_SECRET=your_secret
   RC_API_KEY_ANDROID=your_key
   RC_API_KEY_IOS=your_key
   GA_MEASUREMENT_ID=your_id
   GA_API_SECRET=your_secret
   ```

4. **Android Signing** - `android/key.properties` file configured

### Optional (for GitHub features)

5. **GitHub CLI** (`gh`) - For easier GitHub integration
   - Install: `winget install GitHub.cli`
   - Or manually create releases via web UI

6. **GitHub Token** - Set `GITHUB_TOKEN` environment variable
   - Generate at: https://github.com/settings/tokens
   - Needs `repo` scope

## Environment Setup

### First-Time Setup

1. Copy `.secrets/.env.example` to `.secrets/.env`
2. Fill in all required API keys and secrets
3. Ensure `android/key.properties` exists and is configured
4. Install GitHub CLI (optional): `winget install GitHub.cli`
5. Authenticate with GitHub: `gh auth login`

### Before Each Release

1. Ensure all changes are committed
2. Ensure you're on the `main` branch
3. Pull latest changes: `git pull`
4. Run the release script

## Output Files

The script creates the following:

```
release-artifacts/
├── fermentacraft-v2.0.1.aab                    # Android App Bundle
├── fermentacraft-v2.0.1-arm64-v8a-release.apk  # Android APK (64-bit ARM)
├── fermentacraft-v2.0.1-armeabi-v7a-release.apk # Android APK (32-bit ARM)
├── fermentacraft-v2.0.1-x86_64-release.apk     # Android APK (64-bit x86)
├── fermentacraft-v2.0.1.msix                   # Windows MSIX
└── CHANGELOG-v2.0.1.txt                        # Release notes

build/windows/x64/runner/Release/
└── fermentacraft.exe                           # Windows EXE (not in release dir)
```

## Post-Release Steps

### Google Play Store

1. Go to [Google Play Console](https://play.google.com/console)
2. Select FermentaCraft
3. Navigate to Production → Releases
4. Create new release
5. Upload the `.aab` file from `release-artifacts/`
6. Copy changelog from `CHANGELOG-v*.txt`
7. Submit for review

### Microsoft Store

1. Go to [Partner Center](https://partner.microsoft.com/dashboard)
2. Select FermentaCraft
3. Create new submission
4. Upload the `.msix` file from `release-artifacts/`
5. Copy changelog from `CHANGELOG-v*.txt`
6. Submit for certification

### iOS TestFlight

The iOS build is automatic! Just monitor:
- GitHub Actions: https://github.com/yourusername/fermentacraft/actions
- App Store Connect: https://appstoreconnect.apple.com

### GitHub Release

The release is created automatically, but verify:
- Release page: https://github.com/yourusername/fermentacraft/releases
- All artifacts are attached
- Changelog is formatted correctly

## Troubleshooting

### "Missing android/key.properties"
- Copy `android/key.properties.example` to `android/key.properties`
- Fill in your keystore details

### "GOOGLE_DESKTOP_CLIENT_SECRET not set"
- Check `.secrets/.env` file exists
- Ensure the secret is on its own line: `GOOGLE_DESKTOP_CLIENT_SECRET=your_secret`

### "gh CLI not found"
- Install: `winget install GitHub.cli`
- Or use the API fallback (requires GITHUB_TOKEN)
- Or create releases manually

### GitHub API errors
- Check your GITHUB_TOKEN is valid
- Ensure it has `repo` scope
- Update the repository owner/name in the script

### Windows build fails
- Ensure Visual Studio 2022 is installed
- Run `flutter doctor` to check setup
- Try building manually first: `flutter build windows`

### Android build fails
- Check `android/key.properties` is valid
- Ensure keystore file path is correct
- Run `flutter doctor --android-licenses`

## Advanced Usage

### Custom Version String
If you need a specific version (not recommended):

```powershell
# Manually edit pubspec.yaml first
# Then run with -DryRun to verify
.\scripts\release.ps1 -DryRun
```

### Build Only (No Release)
```powershell
.\scripts\release.ps1 -SkipGitHub -SkipIOS -DryRun
```

### Release Without Building
Not supported - use manual GitHub release instead.

## Script Maintenance

### Updating Repository Name
Edit `scripts/release.ps1` and replace:
- `yourusername/fermentacraft` with your actual repo path

### Adding New Platforms
Add new build steps in the script following the existing patterns:
1. Add parameter to skip the platform
2. Add build step with error handling
3. Add artifacts to release directory
4. Update documentation

## Support

For issues with the release script:
1. Check this README
2. Run with `-DryRun` to test
3. Check individual build scripts in `scripts/` directory
4. Review GitHub Actions logs for iOS builds
