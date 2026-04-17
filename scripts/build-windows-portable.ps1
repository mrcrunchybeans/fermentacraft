# Build Windows Portable Release with Bundled DLLs
# This script creates a standalone Windows executable with all required dependencies bundled

param(
    [Parameter(Mandatory=$false)]
    [string]$OutputDir = "release-artifacts/windows-portable",
    
    [switch]$ZipOutput
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

Write-Step "Building Windows Portable Release"

# Step 1: Build Windows Release
Write-Info "Building Windows release binary..."
flutter build windows --release

$exePath = "build/windows/x64/runner/Release/fermentacraft.exe"
$dllSourceDir = "build/windows/x64/runner/Release"

if (-not (Test-Path $exePath)) {
    Write-ErrorMsg "Failed to build Windows executable"
    exit 1
}

Write-Success "Windows executable built"

# Step 2: Create output directory
if (Test-Path $OutputDir) {
    Remove-Item $OutputDir -Recurse -Force
}
New-Item -ItemType Directory -Path $OutputDir | Out-Null
Write-Success "Created output directory: $OutputDir"

# Step 3: Copy executable
Copy-Item $exePath (Join-Path $OutputDir "fermentacraft.exe")
Write-Success "Copied executable to output directory"

# Step 4: Copy required DLLs
Write-Info "Copying plugin DLLs..."

$requiredDlls = @(
    "connectivity_plus_plugin.dll",
    "file_selector_windows_plugin.dll",
    "share_plus_plugin.dll",
    "url_launcher_windows_plugin.dll"
)

# Find and copy DLLs from build output
$allDlls = Get-ChildItem -Path $dllSourceDir -Filter "*.dll" -Recurse

foreach ($dll in $requiredDlls) {
    $foundDll = $allDlls | Where-Object { $_.Name -eq $dll } | Select-Object -First 1
    
    if ($foundDll) {
        Copy-Item $foundDll.FullName (Join-Path $OutputDir $dll)
        Write-Success "Copied $dll"
    } else {
        Write-Info "Warning: $dll not found in build output (may be optional)"
    }
}

# Copy all DLLs from the Release folder to ensure we have everything
Write-Info "Copying all runtime DLLs..."
$releaseDlls = Get-ChildItem -Path $dllSourceDir -Filter "*.dll" -File | Where-Object { $_.Name -notmatch "^(D3D|dxgi|d3d11)" }
foreach ($dll in $releaseDlls) {
    $dllDest = Join-Path $OutputDir $dll.Name
    if (-not (Test-Path $dllDest)) {
        Copy-Item $dll.FullName $dllDest
        Write-Info "  $($dll.Name)"
    }
}

# Step 5: Create README for portable version
$readmeContent = @"
# FermentaCraft Portable Release

## Contents
- fermentacraft.exe - Main application executable
- *.dll - Required runtime libraries

## Installation (Portable)
No installation required! Simply run fermentacraft.exe

## Troubleshooting

### Missing DLL Errors
If you see errors about missing DLLs when running the application:
1. Ensure all .dll files are in the same folder as fermentacraft.exe
2. Install Visual C++ Redistributable if needed:
   https://support.microsoft.com/en-us/help/2977003/

### The application requires a newer version of Windows
This application requires Windows 10 or later. Please update your Windows installation.

## Support
For issues, visit: https://github.com/mrcrunchybeans/fermentacraft/issues
"@

Set-Content -Path (Join-Path $OutputDir "README.txt") -Value $readmeContent
Write-Success "Created README.txt"

# Step 6: Optionally create ZIP archive
if ($ZipOutput) {
    $zipPath = "$OutputDir.zip"
    Write-Info "Creating ZIP archive..."
    
    if (Test-Path $zipPath) {
        Remove-Item $zipPath -Force
    }
    
    Compress-Archive -Path "$OutputDir/*" -DestinationPath $zipPath
    Write-Success "Created portable ZIP: $zipPath"
}

# Step 7: Summary
Write-Step "Portable Release Ready"

Write-Host @"
✓ Location: $OutputDir
✓ Executable: fermentacraft.exe
✓ DLLs: Included and ready to use

Next Steps:
1. Test the executable with all DLLs present
2. Consider running: `$OutputDir\fermentacraft.exe
3. Distribute the entire folder to users

Recommended Distribution:
- For most users: Use fermentacraft.msix (preferred, easier installation)
- For advanced users: Use this portable version

"@

Write-Success "Windows portable release built successfully!"
