# scripts/build_windows_release.ps1
param(
  [switch]$NonInteractive,
  [switch]$KillRunning
)

# Fail fast on errors
$ErrorActionPreference = 'Stop'

# Ensure we run from repo root for all subsequent commands
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $repoRoot

# Secret sourcing: prefer existing env var, then .secrets/.env, else prompt (unless -NonInteractive)
$envFile = Join-Path $PSScriptRoot '..\.secrets\.env'
if (-not [string]::IsNullOrWhiteSpace($env:GOOGLE_DESKTOP_CLIENT_SECRET)) {
  Write-Host "Using GOOGLE_DESKTOP_CLIENT_SECRET from environment."
} elseif (Test-Path $envFile) {
  Write-Host "Loading environment from $envFile"
  foreach ($line in Get-Content $envFile) {
    if ($line -match '^\s*#' -or $line -match '^\s*$') { continue }
    $kv = $line -split '=', 2
    [Environment]::SetEnvironmentVariable($kv[0].Trim(), $kv[1].Trim(' ', '"', "'"), 'Process')
  }
  if ([string]::IsNullOrWhiteSpace($env:GOOGLE_DESKTOP_CLIENT_SECRET)) {
    if ($NonInteractive) {
      throw "GOOGLE_DESKTOP_CLIENT_SECRET is missing in $envFile. Provide it or pre-set the environment variable."
    }
    $sec = Read-Host "Enter GOOGLE_DESKTOP_CLIENT_SECRET" -AsSecureString
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
    $secret = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    if (-not $secret) { Write-Error "Secret is required."; exit 1 }
    $env:GOOGLE_DESKTOP_CLIENT_SECRET = $secret
  }
} else {
  if ($NonInteractive) {
    throw "GOOGLE_DESKTOP_CLIENT_SECRET not provided and $envFile not found. Create the file or set the env var, or re-run without -NonInteractive to be prompted."
  }
  $sec = Read-Host "Enter GOOGLE_DESKTOP_CLIENT_SECRET" -AsSecureString
  $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
  $secret = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
  if (-not $secret) { Write-Error "Secret is required."; exit 1 }
  $env:GOOGLE_DESKTOP_CLIENT_SECRET = $secret
}

flutter clean
flutter pub get

# Auto-increment version in pubspec.yaml
$pubspecPath = Join-Path $PSScriptRoot '..\pubspec.yaml'
$pubspecContent = Get-Content $pubspecPath -Raw
if ($pubspecContent -match 'version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)') {
    $majorVersion = [int]$Matches[1]
    $minorVersion = [int]$Matches[2]
    $patchVersion = [int]$Matches[3]
    $buildNumber = [int]$Matches[4]
    
    # Increment build number
    $newBuildNumber = $buildNumber + 1
    $newVersion = "$majorVersion.$minorVersion.$patchVersion+$newBuildNumber"
    
    # Update app version
    $newPubspecContent = $pubspecContent -replace 'version:\s*\d+\.\d+\.\d+\+\d+', "version: $newVersion"
    
    # Update MSIX version for Store compliance (major.minor.build.0 - revision must be 0)
    $msixVersion = "$majorVersion.$minorVersion.$newBuildNumber.0"
    $newPubspecContent = $newPubspecContent -replace 'msix_version:\s*\d+\.\d+\.\d+\.\d+', "msix_version: $msixVersion"
    
    Set-Content $pubspecPath $newPubspecContent -NoNewline
    
    Write-Host "Version incremented from $majorVersion.$minorVersion.$patchVersion+$buildNumber to $newVersion"
    Write-Host "MSIX version updated to $msixVersion"
} else {
    Write-Warning "Could not parse version from pubspec.yaml"
}

# Optionally terminate running app instances that might lock build files
if ($KillRunning) {
  Write-Host "Attempting to stop running FermentaCraft processes (optional)..."
  foreach ($p in @('fermentacraft')) {
    try { Get-Process -Name $p -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue } catch {}
  }
}

# Remove any stale EXE to avoid false positives
$exePath = Join-Path $repoRoot 'build/windows/x64/runner/Release/fermentacraft.exe'
if (Test-Path $exePath) {
  try { Remove-Item $exePath -Force -ErrorAction SilentlyContinue } catch {}
}

# Build WITH the secret
$buildStart = Get-Date
flutter build windows --release `
  --dart-define=GOOGLE_DESKTOP_CLIENT_SECRET=$env:GOOGLE_DESKTOP_CLIENT_SECRET `
  --dart-define=GA_MEASUREMENT_ID=$env:GA_MEASUREMENT_ID `
  --dart-define=GA_API_SECRET=$env:GA_API_SECRET

# Validate build succeeded: non-zero exit OR missing/old exe => fail
if ($LASTEXITCODE -ne 0) {
  throw "Flutter Windows build failed with exit code $LASTEXITCODE"
}

if (-not (Test-Path $exePath)) {
  throw "Windows build did not produce $exePath"
}

$exeInfo = Get-Item $exePath -ErrorAction SilentlyContinue
if ($null -eq $exeInfo -or $exeInfo.LastWriteTime -lt $buildStart) {
  throw "Windows build produced a stale EXE (timestamp older than build start)."
}

Write-Host "FermentaCraft Windows Release Generated"

# Package WITHOUT rebuilding (critical)
dart run msix:create --build-windows=false --store

Write-Host "FermentaCraft MSIX Release Generated"

# Build Web
# Default to JS (no Wasm) because some transitive deps import dart:js which is unsupported on Wasm.
# Opt back into Wasm by setting FORCE_WEB_WASM=true in .secrets/.env or environment.
$useWasm = ($env:FORCE_WEB_WASM -and $env:FORCE_WEB_WASM.ToString().ToLower() -eq 'true')
if ($useWasm) {
  Write-Host "Building Web with Wasm as FORCE_WEB_WASM=true"
  flutter build web --release --base-href / --wasm
} else {
  Write-Host "Building Web with JS (no Wasm)"
  flutter build web --release --base-href /
}

Write-Host "FermentaCraft Web Release Generated"

# Build App Bundle for Play Store
flutter build appbundle

Write-Host "FermentaCraft AppBundle Generated"

# Build APKS for Github Release
flutter build apk --release --split-per-abi

Write-Host "FermentaCraft APK Release Files Generated"
Write-Host "Export Completed!"