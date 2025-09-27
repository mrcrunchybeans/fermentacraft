# scripts/build_windows_release.ps1
$envFile = Join-Path $PSScriptRoot '..\.secrets\.env'
if (Test-Path $envFile) {
  foreach ($line in Get-Content $envFile) {
    if ($line -match '^\s*#' -or $line -match '^\s*$') { continue }
    $kv = $line -split '=', 2
    [Environment]::SetEnvironmentVariable($kv[0].Trim(), $kv[1].Trim(' ', '"', "'"), 'Process')
  }
} else {
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

# Build WITH the secret
flutter build windows --release `
  --dart-define=GOOGLE_DESKTOP_CLIENT_SECRET=$env:GOOGLE_DESKTOP_CLIENT_SECRET

Write-Host "FermentaCraft Windows Release Generated"

# Package WITHOUT rebuilding (critical)
dart run msix:create --build-windows=false --store

Write-Host "FermentaCraft MSIX Release Generated"

# Build Web with WebAssembly
flutter build web --release --base-href / --wasm

Write-Host "FermentaCraft Web Release Generated"

# Build App Bundle for Play Store
flutter build appbundle

Write-Host "FermentaCraft AppBundle Generated"

# Build APKS for Github Release
flutter build apk --release --split-per-abi

Write-Host "FermentaCraft APK Release Files Generated"
Write-Host "Export Completed!"