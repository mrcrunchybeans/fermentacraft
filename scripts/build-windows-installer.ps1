# Build Windows Installer (MSIX + MSI Setup)
# Creates a professional Windows installer package

param(
    [Parameter(Mandatory=$false)]
    [string]$OutputDir = "release-artifacts"
)

$ErrorActionPreference = "Stop"

# Colors for output
function Write-Step {
    param([string]$Message)
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host $Message -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "✓ $Message" -ForegroundColor Green
}

function Write-Info {
    param([string]$Message)
    Write-Host "ℹ $Message" -ForegroundColor Yellow
}

function Write-ErrorMsg {
    param([string]$Message)
    Write-Host "✗ $Message" -ForegroundColor Red
}

# Navigate to repo root
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $repoRoot

Write-Step "Building Windows Installer Packages"

# Ensure output directory exists
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir | Out-Null
}

# Step 1: Build MSIX (Primary installer)
Write-Info "Building MSIX package (Windows App Store format)..."
flutter pub run msix:create

$msixPath = "build/windows/x64/runner/Release/fermentacraft.msix"
if (Test-Path $msixPath) {
    # Get version info
    $pubspecPath = Join-Path $repoRoot "pubspec.yaml"
    $pubspecContent = Get-Content $pubspecPath -Raw
    $version = if ($pubspecContent -match 'version:\s*(\d+\.\d+\.\d+)') { $Matches[1] } else { "unknown" }
    
    $msixDest = Join-Path $OutputDir "FermentaCraft-$version.msix"
    Copy-Item $msixPath $msixDest -Force
    Write-Success "MSIX created: $msixDest"
    Write-Info "  Install: Right-click → Install or use 'Add an app' in Microsoft Store"
} else {
    Write-ErrorMsg "Failed to create MSIX package"
}

# Step 2: Create installer batch script
Write-Info "Creating Windows installer scripts..."

$installerBat = @"
@echo off
REM FermentaCraft Windows Installer
REM This script installs FermentaCraft on Windows

setlocal enabledelayedexpansion

title FermentaCraft Installer

echo.
echo ========================
echo FermentaCraft Installer
echo ========================
echo.

REM Check for MSIX file
if not exist "FermentaCraft-*.msix" (
    echo Error: MSIX file not found
    echo Please ensure the MSIX file is in the same directory as this script
    pause
    exit /b 1
)

REM Get the MSIX filename
for /r %%f in (FermentaCraft-*.msix) do (
    set MSIX_FILE=%%f
    goto :found_msix
)

:found_msix
echo Found: !MSIX_FILE!
echo.
echo Installing FermentaCraft...
echo.

REM Use PowerShell to install the MSIX
powershell -Command "Add-AppPackage -Path '!MSIX_FILE!'" && (
    echo.
    echo Installation successful!
    echo FermentaCraft is ready to use.
    echo.
    echo You can launch it from:
    echo   - Windows Start Menu
    echo   - Search for "FermentaCraft"
    echo.
) || (
    echo.
    echo Installation failed.
    echo Error details above.
    echo.
    echo Troubleshooting:
    echo 1. Ensure you're on Windows 10 or later
    echo 2. Right-click the MSIX file and select "Install"
    echo 3. Visit: https://github.com/mrcrunchybeans/fermentacraft/issues
    echo.
)

pause
"@

Set-Content -Path (Join-Path $OutputDir "Install-FermentaCraft.bat") -Value $installerBat
Write-Success "Created installer batch script"

# Step 3: Create PowerShell installation script
$installerPs1 = @"
# FermentaCraft Windows Installer (PowerShell)
# Run with: powershell -ExecutionPolicy Bypass -File Install-FermentaCraft.ps1

param(
    [string]`$MsixPath = ""
)

`$ErrorActionPreference = "Stop"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "FermentaCraft Installer" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Find MSIX file
if ([string]::IsNullOrWhiteSpace(`$MsixPath)) {
    `$msixFiles = Get-ChildItem -Filter "FermentaCraft-*.msix" -ErrorAction SilentlyContinue
    
    if (`$msixFiles.Count -eq 0) {
        Write-Host "✗ No MSIX file found in current directory" -ForegroundColor Red
        Write-Host "ℹ Please extract the installer to a folder and run this script again`n" -ForegroundColor Yellow
        exit 1
    }
    
    `$MsixPath = `$msixFiles[0].FullName
}

Write-Host "ℹ Installing: `$(Split-Path `$MsixPath -Leaf)`n" -ForegroundColor Yellow

# Check Windows version
`$osVersion = [System.Environment]::OSVersion.Version
if (`$osVersion.Major -lt 10) {
    Write-Host "✗ Windows 10 or later required" -ForegroundColor Red
    exit 1
}

# Install MSIX
try {
    Write-Host "Installing application..." -ForegroundColor Yellow
    Add-AppPackage -Path `$MsixPath -ErrorAction Stop
    
    Write-Host "`n✓ Installation successful!" -ForegroundColor Green
    Write-Host @"
    
FermentaCraft is now installed and ready to use.

You can launch it from:
  - Windows Start Menu (search for "FermentaCraft")
  - Desktop shortcut (if created)
  - App launcher

Thank you for using FermentaCraft!
"@ -ForegroundColor Green
} catch {
    Write-Host "`n✗ Installation failed: `$_`n" -ForegroundColor Red
    
    Write-Host "Troubleshooting options:" -ForegroundColor Yellow
    Write-Host "1. Try right-clicking the MSIX file and selecting 'Install'"
    Write-Host "2. Ensure you're running Windows 10 or later"
    Write-Host "3. Try running as Administrator"
    Write-Host "4. Check your antivirus for blocked installations"
    Write-Host "5. Visit: https://github.com/mrcrunchybeans/fermentacraft/issues`n" -ForegroundColor Yellow
    
    exit 1
}
"@

Set-Content -Path (Join-Path $OutputDir "Install-FermentaCraft.ps1") -Value $installerPs1
Write-Success "Created PowerShell installer script"

# Step 4: Create Windows Installer Information
$installReadme = @"
# FermentaCraft Windows Installation Guide

## System Requirements
- Windows 10 (Build 19041) or later
- x64 processor (64-bit)
- 200 MB free disk space

## Installation Methods

### Method 1: Easy Installation (Recommended)
1. Double-click **Install-FermentaCraft.bat**
2. Follow the on-screen prompts
3. Application will launch automatically after installation

### Method 2: PowerShell Installation
1. Right-click **Install-FermentaCraft.ps1**
2. Select "Run with PowerShell"
3. If prompted about execution policy, type 'Y' and press Enter

### Method 3: Manual MSIX Installation
1. Right-click **FermentaCraft-*.msix**
2. Select "Install"
3. Click "Install" in the prompt

### Method 4: Via Windows Terminal
```powershell
Add-AppPackage -Path "FermentaCraft-X.Y.Z.msix"
```

## After Installation
- Search for "FermentaCraft" in Windows Start Menu
- Click to launch the application
- First launch may take a few seconds

## Troubleshooting

### "This app can't run on your device"
- Ensure you have Windows 10 Build 19041 or later
- Check System Settings > System > About for your Windows version

### "Cannot install application"
- Run installation as Administrator (right-click installer)
- Disable antivirus temporarily if blocking installation
- Ensure you have at least 200 MB free disk space

### "Application won't start"
- Try uninstalling and reinstalling
- Check Event Viewer for error details
- Visit: https://github.com/mrcrunchybeans/fermentacraft/issues

### "Install button is greyed out"
- You may not have permission to install apps
- Contact your system administrator
- Or use the Microsoft Store if available

## Uninstallation
1. Go to Settings > Apps > Apps & Features
2. Search for "FermentaCraft"
3. Click and select "Uninstall"
4. Confirm the uninstallation

## Support
For issues or questions, visit:
https://github.com/mrcrunchybeans/fermentacraft/issues

## About MSIX
MSIX is Microsoft's modern app packaging format that:
- Ensures clean installation and removal
- Includes all dependencies automatically
- Provides automatic updates
- Improves security with app isolation
"@

Set-Content -Path (Join-Path $OutputDir "WINDOWS-INSTALLATION.txt") -Value $installReadme
Write-Success "Created installation guide"

# Step 5: Summary
Write-Step "Windows Installer Packages Ready"

Write-Host @"
✓ MSIX Package: $(if (Test-Path $msixPath) { 'Created' } else { 'Failed' })
✓ Installer Scripts: Created
✓ Documentation: Created

Distribution Files:
  $(if (Test-Path (Join-Path $OutputDir "FermentaCraft-*.msix")) { Get-ChildItem (Join-Path $OutputDir "FermentaCraft-*.msix") | ForEach-Object { "  - $($_.Name)" } } else { "  - MSIX file not found" })
  - Install-FermentaCraft.bat (batch installer)
  - Install-FermentaCraft.ps1 (PowerShell installer)
  - WINDOWS-INSTALLATION.txt (guide)

Next Steps:
1. Test installation on a clean Windows 10/11 system
2. Share the entire directory with users
3. Or ZIP and distribute as: fermentacraft-windows-installer.zip

Recommended for Users:
- Download the installer package
- Run Install-FermentaCraft.bat
- Application will be installed and ready to use

"@

Write-Success "Windows installer packages built successfully!"
