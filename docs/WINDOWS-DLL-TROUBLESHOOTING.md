# FermentaCraft Windows - DLL Troubleshooting Guide

## Quick Fix for "Missing DLL" Errors

If you're seeing errors like:
- "The code execution cannot proceed because X.dll was not found"
- Missing: connectivity_plus_plugin.dll
- Missing: file_selector_windows_plugin.dll
- Missing: share_plus_plugin.dll
- Missing: url_launcher_windows_plugin.dll

### Solution 1: Install Using MSIX (Recommended)

The MSIX package includes all required DLLs automatically:

1. **Download** the file ending in `.msix`
2. **Right-click** the file
3. Select **Install** (or double-click)
4. Windows will install FermentaCraft with all dependencies
5. **Done!** Search for FermentaCraft in Start Menu

This is the easiest and most reliable method.

### Solution 2: Use Portable Version

If MSIX doesn't work (e.g., older Windows):

1. **Download** the file ending in `-portable.zip`
2. **Extract** to any folder (e.g., `C:\FermentaCraft`)
3. **Ensure all .dll files** are in the same folder as fermentacraft.exe
4. **Run** fermentacraft.exe

All DLLs must stay together in the same folder.

### Solution 3: Manual DLL Installation

If you have a standalone EXE and need the DLLs:

1. **Create a new folder** (e.g., `C:\FermentaCraft`)
2. **Move fermentacraft.exe** into that folder
3. **Download the portable version** (see above)
4. **Copy all .dll files** from portable version to same folder as .exe
5. **Run** fermentacraft.exe

Required DLLs:
- connectivity_plus_plugin.dll
- file_selector_windows_plugin.dll
- share_plus_plugin.dll
- url_launcher_windows_plugin.dll
- (And other Flutter runtime DLLs)

## System Requirements

- **Windows 10** (Build 19041 or later) OR **Windows 11**
- **x64 processor** (64-bit)
- **200 MB** free disk space
- **Visual C++ Redistributable** (usually installed on modern Windows)

## Additional Troubleshooting

### "I still get DLL errors after following steps above"

1. **Verify Windows version** (Settings > System > About)
   - Need Windows 10 Build 19041+ or Windows 11
   
2. **Install Visual C++ Redistributable**
   - Visit: https://support.microsoft.com/en-us/help/2977003/
   - Download and install the latest version
   - Restart your computer
   
3. **Disable antivirus temporarily**
   - Your antivirus may be blocking DLL loading
   - Try disabling temporarily during app start
   
4. **Check folder permissions**
   - Right-click folder > Properties > Security
   - Ensure your user account has full control
   
5. **Reinstall the application**
   - Uninstall (see below)
   - Download fresh MSIX or portable version
   - Reinstall

### "MSIX Installation Failed"

**"This app can't run on your device"**
- Windows 10 Build 19041+ is required
- Update Windows: Settings > Update & Security > Windows Update

**"Do you want to install this application?"**
- Click Yes to proceed
- This is normal and expected

**"Installation was unsuccessful"**
- Try running as Administrator (right-click)
- Disable antivirus temporarily
- Try portable version as alternative

### "Application won't start after installation"

1. **Restart your computer**
   - Sometimes required after installation
   
2. **Clear application cache**
   ```
   - Press Windows + R
   - Type: %LOCALAPPDATA%\FermentaCraft
   - Delete the folder
   - Restart the app
   ```

3. **Reinstall Visual C++ Redistributable**
   - The app may need updated runtime libraries
   - https://support.microsoft.com/en-us/help/2977003/

4. **Check Event Viewer for errors**
   - Press Windows + R
   - Type: eventvwr
   - Look for errors from FermentaCraft
   - Report errors at: https://github.com/mrcrunchybeans/fermentacraft/issues

### "Application crashes after startup"

1. **Collect error details**
   - Note what action causes crash
   - Check Windows Event Viewer (eventvwr)
   - Save any error messages
   
2. **Check for insufficient disk space**
   - C: drive needs at least 500 MB free
   
3. **Update Windows**
   - Check for Windows Updates
   - Install all updates
   - Restart
   
4. **Report the error**
   - Visit: https://github.com/mrcrunchybeans/fermentacraft/issues
   - Include your Windows version, error message, and steps to reproduce

## Uninstalling FermentaCraft

### If you used MSIX:
1. **Settings** > **Apps** > **Apps & Features**
2. Search for **FermentaCraft**
3. Click it, then click **Uninstall**
4. Confirm

### If you used Portable Version:
1. Simply **delete the folder** you extracted
2. No system cleanup needed (no registry changes)

## Need More Help?

- **GitHub Issues:** https://github.com/mrcrunchybeans/fermentacraft/issues
- **Windows Support:** https://support.microsoft.com/
- **Flutter Windows Docs:** https://docs.flutter.dev/deployment/windows

## What is MSIX?

MSIX is Microsoft's modern app packaging format that:
- ✓ Automatically includes all dependencies
- ✓ Prevents DLL conflict issues
- ✓ Provides clean installation/uninstallation
- ✓ Improves security with isolation
- ✓ Enables automatic updates
- ✓ Can be distributed via Microsoft Store

## Summary

| Issue | Solution |
|-------|----------|
| Missing DLLs | Use MSIX or portable version |
| Installation fails | Run as Admin, update Windows |
| App won't start | Restart PC, clear cache, reinstall |
| Crashes | Check disk space, reinstall dependencies |

**Best Option:** Use the MSIX file (.msix) - it handles everything automatically!
