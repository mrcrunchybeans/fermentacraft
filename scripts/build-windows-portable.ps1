# Build Windows Portable Release with Bundled DLLs
# This script creates a standalone Windows executable with all required dependencies bundled

param(
    [Parameter(Mandatory = $false)]
    [string]$OutputDir = "release-artifacts/windows-portable",

    [switch]$ZipOutput,

    [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host $Message -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Success {
    param([string]$Message)
    Write-Host "✓ $Message" -ForegroundColor Green
}

function Write-Info {
    param([string]$Message)
    Write-Host "ℹ $Message" -ForegroundColor Yellow
}

function Write-Warn {
    param([string]$Message)
    Write-Host "⚠ $Message" -ForegroundColor DarkYellow
}

function Write-ErrorMsg {
    param([string]$Message)
    Write-Host "✗ $Message" -ForegroundColor Red
}

function Resolve-RepoRoot {
    if ($env:GITHUB_WORKSPACE -and (Test-Path $env:GITHUB_WORKSPACE)) {
        return (Resolve-Path $env:GITHUB_WORKSPACE).Path
    }
    return (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}

$repoRoot = Resolve-RepoRoot
Set-Location $repoRoot

Write-Step "Building Windows Portable Release"
Write-Info "Repo root: $repoRoot"

$releaseDir = Join-Path $repoRoot "build/windows/x64/runner/Release"
$exePath = Join-Path $releaseDir "fermentacraft.exe"

if (-not $SkipBuild) {
    Write-Info "Building Windows release binary..."
    & flutter build windows --release
} else {
    Write-Info "Skipping flutter build; packaging existing release output"
}

if (-not (Test-Path $exePath)) {
    Write-ErrorMsg "Executable not found: $exePath"
    exit 1
}

Write-Success "Windows executable ready"

if ([System.IO.Path]::IsPathRooted($OutputDir)) {
    $resolvedOutputDir = $OutputDir
} else {
    $resolvedOutputDir = Join-Path $repoRoot $OutputDir
}

if (Test-Path $resolvedOutputDir) {
    Remove-Item $resolvedOutputDir -Recurse -Force
}
New-Item -ItemType Directory -Path $resolvedOutputDir | Out-Null
Write-Success "Created output directory: $resolvedOutputDir"

Copy-Item $exePath (Join-Path $resolvedOutputDir "fermentacraft.exe")
Write-Success "Copied executable"

Write-Info "Copying runtime files..."

$excludeDllPatterns = @(
    '^D3D',
    '^dxgi',
    '^d3d11'
)

$releaseFiles = Get-ChildItem -Path $releaseDir -File

foreach ($file in $releaseFiles) {
    $shouldSkip = $false

    if ($file.Extension -ieq ".dll") {
        foreach ($pattern in $excludeDllPatterns) {
            if ($file.Name -match $pattern) {
                $shouldSkip = $true
                break
            }
        }
    }

    if (-not $shouldSkip) {
        Copy-Item $file.FullName (Join-Path $resolvedOutputDir $file.Name) -Force
        Write-Info "  $($file.Name)"
    }
}

$readmeContent = @"
FermentaCraft Portable Release

Contents
- fermentacraft.exe : Main application executable
- *.dll             : Required runtime libraries

Installation
No installer is required. Keep all files together in one folder and run:
fermentacraft.exe

Troubleshooting

Missing DLL errors
- Make sure all DLL files remain in the same folder as fermentacraft.exe
- Install the Microsoft Visual C++ Redistributable if needed:
  https://support.microsoft.com/en-us/help/2977003/

Windows version
- This build requires Windows 10 or later

Support
- https://github.com/mrcrunchybeans/fermentacraft/issues
"@

Set-Content -Path (Join-Path $resolvedOutputDir "README.txt") -Value $readmeContent -Encoding UTF8
Write-Success "Created README.txt"

if ($ZipOutput) {
    $zipPath = "$resolvedOutputDir.zip"
    Write-Info "Creating ZIP archive..."

    if (Test-Path $zipPath) {
        Remove-Item $zipPath -Force
    }

    Compress-Archive -Path (Join-Path $resolvedOutputDir '*') -DestinationPath $zipPath
    Write-Success "Created ZIP archive: $zipPath"
}

Write-Step "Portable Release Ready"
Write-Host "Location: $resolvedOutputDir"
Write-Host "Executable: $(Join-Path $resolvedOutputDir 'fermentacraft.exe')"
Write-Host "DLLs: Included"
Write-Host ""
Write-Host "Recommended distribution:"
Write-Host "- MSIX for most users"
Write-Host "- Portable folder/ZIP for advanced users"
Write-Host ""

Write-Success "Windows portable release built successfully!"