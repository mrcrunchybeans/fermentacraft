# Windows Build Scripts - Quick Reference

## Overview

Three PowerShell scripts handle Windows releases to fix missing DLL issues:

| Script | Purpose | Output |
|--------|---------|--------|
| `build-windows-portable.ps1` | Portable EXE + DLLs | Single folder + ZIP |
| `build-windows-installer.ps1` | MSIX + installers | MSIX + bat/ps1 helpers |
| `release.ps1` | Full multi-platform release | All artifacts for all platforms |

## Running the Scripts

### Option 1: Full Release (Recommended)

Builds everything automatically:

```powershell
cd scripts
.\release.ps1
```

Outputs:
- `release-artifacts/fermentacraft-v2.0.5.msix` (MSIX)
- `release-artifacts/fermentacraft-v2.0.5-portable.zip` (Portable)
- All Android, iOS prep artifacts
- All changelog and documentation

### Option 2: Windows Only

Just Windows packages:

```powershell
cd scripts
.\release.ps1 -SkipAndroid -SkipIOS
```

### Option 3: Individual Scripts

Build just what you need:

```powershell
# Portable version only
cd scripts
.\build-windows-portable.ps1 -OutputDir "my-portable"

# MSIX + installers only
cd scripts
.\build-windows-installer.ps1 -OutputDir "release-artifacts"
```

## Output Structure

### From `build-windows-portable.ps1`:

```
release-artifacts/
  fermentacraft-v2.0.5-portable/
    ├── fermentacraft.exe
    ├── connectivity_plus_plugin.dll
    ├── file_selector_windows_plugin.dll
    ├── share_plus_plugin.dll
    ├── url_launcher_windows_plugin.dll
    ├── (other runtime DLLs)
    └── README.txt
```

### From `build-windows-installer.ps1`:

```
release-artifacts/
  ├── FermentaCraft-2.0.5.msix
  ├── Install-FermentaCraft.bat
  ├── Install-FermentaCraft.ps1
  └── WINDOWS-INSTALLATION.txt
```

### From `release.ps1`:

```
release-artifacts/
  ├── fermentacraft-v2.0.5.msix
  ├── fermentacraft-v2.0.5-portable.zip
  ├── fermentacraft-v2.0.5.aab (Android)
  ├── fermentacraft-v2.0.5-arm64-v8a-release.apk (Android)
  ├── fermentacraft-v2.0.5-armeabi-v7a-release.apk (Android)
  └── CHANGELOG-v2.0.5.txt
```

## Parameters

### `build-windows-portable.ps1`

```powershell
# Custom output directory
.\build-windows-portable.ps1 -OutputDir "C:\custom\path"

# Create ZIP archive
.\build-windows-portable.ps1 -OutputDir "out" -ZipOutput
```

### `build-windows-installer.ps1`

```powershell
# Custom output directory
.\build-windows-installer.ps1 -OutputDir "installers"
```

### `release.ps1`

```powershell
# Skip platforms
.\release.ps1 -SkipAndroid -SkipWindows -SkipIOS

# Dry run (no commits/tags)
.\release.ps1 -DryRun

# Version bump: patch (default), minor, major
.\release.ps1 -VersionBump "minor"

# Custom GitHub token
.\release.ps1 -GitHubToken "your_token"
```

## Common Tasks

### "I just want to test portable build"

```powershell
cd scripts
.\build-windows-portable.ps1 -OutputDir "test-portable"
# Test with: test-portable\fermentacraft.exe
```

### "I want to test MSIX installation"

```powershell
cd scripts
.\build-windows-installer.ps1
# Double-click: FermentaCraft-2.0.5.msix
```

### "I need to create a release"

```powershell
cd scripts
.\release.ps1  # Builds everything
# Then publish release-artifacts/* to GitHub
```

### "I want dry-run before real release"

```powershell
cd scripts
.\release.ps1 -DryRun
# Checks what would happen, doesn't commit/tag
```

### "I'm on Windows 7, I need portable"

```powershell
cd scripts
.\build-windows-portable.ps1
# Use the portable version - it works on Windows 7+
```

## Distribution Guide

### For GitHub Release:

1. Run full release: `.\release.ps1`
2. Upload artifacts to GitHub:
   - `fermentacraft-v2.0.5.msix` → **For most users** ⭐
   - `fermentacraft-v2.0.5-portable.zip` → **For USB/portable**
3. Add release notes with download links
4. Link to `WINDOWS-RELEASE-INSTRUCTIONS.md`

### Release Notes Template:

```markdown
## Windows

**Recommended:** Download `fermentacraft-v2.0.5.msix`
- Right-click → Install
- All dependencies included
- Works on Windows 10/11

**Alternative:** Download `fermentacraft-v2.0.5-portable.zip`
- No installation needed
- Extract and run
- For older Windows or USB

[Installation Help](WINDOWS-RELEASE-INSTRUCTIONS.md)
```

## Troubleshooting

### "Script not found"

```powershell
# Make sure you're in scripts directory
cd scripts

# If still not found, check file exists
ls build-windows-portable.ps1
```

### "Execution policy error"

```powershell
# Run as Administrator, then:
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# Then run script
.\build-windows-portable.ps1
```

### "flutter command not found"

```powershell
# Make sure Flutter is in PATH
flutter --version

# If not, add to PATH or run from Flutter installation:
"$env:FLUTTER_HOME\bin\flutter" build windows --release
```

### "MSIX creation failed"

```powershell
# MSIX requires:
# 1. Windows 10 (Build 19041+)
# 2. .NET SDK installed
# 3. Visual C++ Build Tools

# Try portable version as alternative:
.\build-windows-portable.ps1
```

### "Missing plugin DLLs in portable"

```powershell
# Check build output directory:
dir "build/windows/x64/runner/Release" | findstr ".dll"

# If missing, run:
flutter clean
flutter pub get
flutter build windows --release

# Then rebuild portable:
.\build-windows-portable.ps1
```

## Script Features

### `build-windows-portable.ps1`

✓ Builds Windows release  
✓ Finds all plugin DLLs  
✓ Copies to output folder  
✓ Creates README.txt  
✓ Optional ZIP packaging  
✓ Clear error messages  

### `build-windows-installer.ps1`

✓ Builds MSIX package  
✓ Creates .bat installer  
✓ Creates .ps1 installer  
✓ Generates installation guide  
✓ Colorized output  
✓ Comprehensive help text  

### `release.ps1` (Updated)

✓ Builds MSIX  
✓ Builds portable version  
✓ Packages both together  
✓ Handles all platforms  
✓ Creates GitHub release  
✓ Triggers iOS workflow  
✓ Better output formatting  

## Next Steps

1. **Run a full release:** `.\release.ps1`
2. **Verify artifacts:** Check `release-artifacts/`
3. **Test installation:** Try both MSIX and portable
4. **Create GitHub release:** Upload artifacts
5. **Update documentation:** Reference installation guides

---

**Questions?** Check:
- [Windows Distribution Guide](../docs/windows-distribution-guide.md)
- [Windows DLL Troubleshooting](../docs/WINDOWS-DLL-TROUBLESHOOTING.md)
- [Windows Release Instructions](../WINDOWS-RELEASE-INSTRUCTIONS.md)
