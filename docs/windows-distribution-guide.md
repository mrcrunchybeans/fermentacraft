# FermentaCraft Windows Distribution Guide

## Overview

This guide explains how to properly distribute FermentaCraft for Windows without missing DLL errors.

## Problem

The issue "Executable is throwing errors in Windows 11 when executed #1" was caused by:
- Standalone EXE files missing required Flutter plugin DLLs at runtime
- Missing DLLs: connectivity_plus_plugin.dll, file_selector_windows_plugin.dll, share_plus_plugin.dll, url_launcher_windows_plugin.dll

## Solution Approaches

### Approach 1: MSIX Package (RECOMMENDED) ⭐

**Best for:** Most users, Microsoft Store distribution

**What is MSIX?**
- Microsoft's modern app packaging format
- Automatically handles all dependencies
- Provides clean installation/uninstallation
- Enables automatic updates
- Better security with app isolation

**How to Build:**
```powershell
cd scripts
.\build-windows-installer.ps1
```

**How Users Install:**
1. Download the .msix file
2. Double-click or right-click → Install
3. Application appears in Start Menu

**Advantages:**
- ✓ All dependencies included automatically
- ✓ No DLL errors
- ✓ Professional installer experience
- ✓ Easier uninstallation
- ✓ Can be submitted to Microsoft Store

**Disadvantages:**
- ✗ Requires Windows 10 Build 19041+
- ✗ Users unfamiliar with .msix format

### Approach 2: Portable Version with Bundled DLLs

**Best for:** Advanced users, offline distribution

**How to Build:**
```powershell
cd scripts
.\build-windows-portable.ps1
```

**What You Get:**
- Single folder with fermentacraft.exe + all required DLLs
- No installation needed
- Can run from USB drive
- Can run from network share

**How Users Use:**
1. Download and extract fermentacraft-portable.zip
2. Run fermentacraft.exe from the folder
3. All DLLs must stay in same directory

**Advantages:**
- ✓ No installation required
- ✓ Portable across Windows systems
- ✓ Works on older Windows versions (10, 7)
- ✓ Can be shared on USB/network

**Disadvantages:**
- ✗ Larger file size (DLLs included)
- ✗ No automatic updates
- ✗ Less professional appearance

### Approach 3: Windows Installer Scripts

**Best for:** Distribution with helper scripts

**How to Build:**
```powershell
cd scripts
.\build-windows-installer.ps1
```

**What You Get:**
- MSIX package
- Batch installer (Install-FermentaCraft.bat)
- PowerShell installer (Install-FermentaCraft.ps1)
- Installation guide

**How Users Install:**
1. Extract installer package
2. Run Install-FermentaCraft.bat (or .ps1)
3. Follow prompts
4. Application installs and launches

**Advantages:**
- ✓ User-friendly bat/ps1 wrappers
- ✓ Clear error messages
- ✓ Troubleshooting included
- ✓ Professional documentation

**Disadvantages:**
- ✗ Requires Windows 10 Build 19041+
- ✗ More files to distribute

## Recommended Distribution Strategy

### For GitHub Releases:
1. **Primary Release:** Include MSIX (.msix file)
   - Best user experience
   - Recommended for most users

2. **Alternative Release:** Include Portable ZIP (.zip with exe + DLLs)
   - For Windows 7/8 users
   - For portable/USB scenarios

3. **Optional:** Include Installer Package
   - If you want helper scripts

### Release Structure Example:
```
v2.0.5/
├── fermentacraft-2.0.5.msix                     (MSIX - Recommended)
├── fermentacraft-2.0.5-portable.zip            (Portable with DLLs)
├── fermentacraft-2.0.5-installer-package.zip   (With helper scripts)
├── CHANGELOG.txt
└── WINDOWS-INSTALLATION.txt                     (User guide)
```

## Update Release Script

The `release.ps1` script has been updated to automatically:

1. Build MSIX package
2. Create portable version with bundled DLLs
3. Package both for release distribution
4. Include all necessary documentation

**New Usage:**
```powershell
cd scripts
.\release.ps1  # Builds all platforms + both Windows versions
```

## Documentation for Users

Create a clear README on GitHub:

```markdown
## Windows Installation

### Recommended (MSIX)
1. Download `fermentacraft-X.Y.Z.msix`
2. Double-click or right-click → Install
3. Search for FermentaCraft in Start Menu

### Alternative (Portable - No Installation)
1. Download `fermentacraft-X.Y.Z-portable.zip`
2. Extract to any folder
3. Double-click `fermentacraft.exe`

### Troubleshooting

**"Missing DLL" errors** → Use MSIX or portable version
**"Install button greyed out"** → Run as Administrator
**"Can't run on this device"** → Need Windows 10 Build 19041+
```

## Testing

### Test MSIX Installation:
1. Create clean Windows VM or test machine
2. Download .msix file
3. Install and test application
4. Verify all features work (file picking, sharing, etc.)
5. Test uninstallation

### Test Portable Version:
1. Extract .zip to folder
2. Verify all .dll files present
3. Run .exe
4. Test all features requiring plugins
5. Move folder to different location
6. Verify still works

## CI/CD Integration

The release script already handles both versions. For CI/CD:

```yaml
# Example GitHub Actions
- name: Build Windows Release
  run: |
    cd scripts
    .\release.ps1 -SkipAndroid -SkipIOS
```

## Troubleshooting

### Users Still Getting "Missing DLL" Errors

**Possible Causes:**
1. User downloaded raw EXE from build artifacts
2. User extracted MSIX without proper tools
3. Portable ZIP missing DLL files

**Solutions:**
1. Clearly mark MSIX as recommended
2. Provide portable ZIP alternative
3. Direct users to issue tracker for help
4. Consider removing raw EXE from releases

### DLLs Not Included in Portable

If portable package missing DLLs:
1. Rebuild with: `.\build-windows-portable.ps1`
2. Check that all DLLs copied: `ls -recurse *.dll | select -first 10`
3. Verify pubspec.yaml has all dependencies

## Future Improvements

1. **Windows Store:** Submit MSIX to Microsoft Store
2. **Auto-Updates:** Implement app update mechanism
3. **Code Signing:** Sign MSIX with certificate
4. **Windows 7 Support:** Create separate MSI installer for Windows 7
5. **Installer Customization:** Use NSIS or WiX for advanced installer

## References

- [Flutter Windows Deployment](https://docs.flutter.dev/deployment/windows)
- [MSIX Documentation](https://docs.microsoft.com/en-us/windows/msix/)
- [Flutter msix Package](https://pub.dev/packages/msix)

## Summary

✓ Use MSIX for recommended distribution  
✓ Provide Portable ZIP as alternative  
✓ Include installation guide  
✓ Test both versions before release  
✓ Keep DLL troubleshooting guide accessible  
