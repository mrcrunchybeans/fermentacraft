# Reset-BuildWindows.ps1
# Hard-resets Flutter Windows build artifacts and rebuilds desktop runner.
# Run from your Flutter project root.

[CmdletBinding()]
param(
  [switch]$NoRun    # add -NoRun to only configure/build without launching
)

$ErrorActionPreference = "Stop"

function Write-Section($t){ Write-Host "`n=== $t ===" -ForegroundColor Cyan }

# 0) Basic sanity check
Write-Section "Sanity check"
if (-not (Test-Path ".\pubspec.yaml")) { throw "Not in a Flutter project (pubspec.yaml missing)" }
if (-not (Test-Path ".\windows\CMakeLists.txt")) { throw "Windows runner not configured (windows/CMakeLists.txt missing)" }

# 1) Kill stray runner if open
Write-Section "Closing any running app instances"
Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like "*fermentacraft*" -or $_.ProcessName -like "*Runner*" } |
  ForEach-Object { try { $_ | Stop-Process -Force -ErrorAction Stop } catch {} }

# 2) Clear stale env that can confuse CMake
Write-Section "Clearing stale environment variables"
foreach ($v in "CMAKE_GENERATOR","CMAKE_GENERATOR_INSTANCE","VSINSTALLDIR") {
  if (Test-Path Env:\$v) {
    Remove-Item Env:\$v -ErrorAction SilentlyContinue
    Write-Host "Cleared $v"
  }
}

# 3) Prefer stable VS instance if found (optional but helpful)
$vsCommunity = "C:\Program Files\Microsoft Visual Studio\2022\Community"
if (Test-Path $vsCommunity) {
  # Let CMake pick this instance if multiple VS installs exist
  $env:CMAKE_GENERATOR_INSTANCE = $vsCommunity
  Write-Host "Using CMAKE_GENERATOR_INSTANCE = $vsCommunity"
}

# 4) Flutter clean + nuke build caches
Write-Section "flutter clean"
flutter clean

Write-Section "Removing build caches"
$paths = @(
  ".\build",
  ".\.dart_tool",
  ".\windows\flutter\ephemeral"
)
foreach ($p in $paths) {
  if (Test-Path $p) {
    Remove-Item -Recurse -Force $p
    Write-Host "Removed $p"
  }
}

# 5) Doctor + deps
Write-Section "flutter doctor -v"
flutter doctor -v

Write-Section "flutter pub get"
flutter pub get

# 6) Regenerate Windows build files explicitly
Write-Section "Regenerating Windows build files with CMake"
# flutter run will do this anyway, but an explicit configure gives clearer errors
# (Flutter uses the VS 17 2022 generator by default)
$cmakeExe = "$vsCommunity\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
if (-not (Test-Path $cmakeExe)) {
  # Fallback to cmake on PATH if VS one isn't found
  $cmakeExe = "cmake"
}
& $cmakeExe -S .\windows -B .\build\windows\x64 -G "Visual Studio 17 2022" -A x64 -DFLUTTER_TARGET_PLATFORM=windows-x64

# 7) Build + (optionally) run
if ($NoRun) {
  Write-Section "Building Windows (no run)"
  flutter build windows -v
  Write-Host "`nDone. Launch EXE at: .\build\windows\x64\runner\Release\fermentacraft.exe"
} else {
  Write-Section "Running Windows app"
  flutter run -d windows -v
}
