# Windows Release Instructions for Users

## 🚀 Install FermentaCraft on Windows

### 🎯 Recommended: MSIX Package

**Best for:** Most Windows users (easiest installation)

1. Download `fermentacraft-X.Y.Z.msix` from releases
2. Double-click the file OR right-click → Install
3. Windows installs the application
4. Open Start Menu and search for "FermentaCraft"
5. Click to launch

**Requires:** Windows 10 (Build 19041+) or Windows 11

---

### 📦 Alternative: Portable Package (No Installation)

**Best for:** Users who prefer portable apps, USB distribution, or older Windows

1. Download `fermentacraft-X.Y.Z-portable.zip` from releases
2. Extract to any folder (e.g., `C:\FermentaCraft`)
3. Double-click `fermentacraft.exe`
4. Application runs immediately

**No installation needed** - all DLLs are included in the folder

**Works on:** Windows 10, Windows 11

---

## ❌ Troubleshooting Missing DLL Errors

### If You See "Missing DLL" Errors:

✓ **Use the MSIX file** - automatically includes all DLLs  
✓ **Use the portable ZIP** - all DLLs included in folder  
✗ **Don't use standalone EXE** - missing dependencies

See detailed guide: [WINDOWS-DLL-TROUBLESHOOTING.md](WINDOWS-DLL-TROUBLESHOOTING.md)

---

## 📋 System Requirements

- Windows 10 (Build 19041+) or Windows 11
- x64 processor (64-bit)
- 200 MB free disk space
- (Visual C++ Redistributable - usually already installed)

---

## ❓ Which Should I Choose?

| Need | Option |
|------|--------|
| Easiest installation | MSIX (.msix) ⭐ |
| No installation needed | Portable (.zip) |
| Portable/USB ready | Portable (.zip) |
| App Store style | MSIX (.msix) |

---

## 🔗 Learn More

- [Detailed Windows Installation Guide](windows-distribution-guide.md)
- [DLL Troubleshooting Guide](WINDOWS-DLL-TROUBLESHOOTING.md)
- [Report Issues](https://github.com/mrcrunchybeans/fermentacraft/issues)

---

**Note:** If you downloaded an older version and encountered DLL errors, try the MSIX file - it includes all necessary dependencies!
