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

# Build WITH the secret
flutter build windows --release `
  --dart-define=GOOGLE_DESKTOP_CLIENT_SECRET=$env:GOOGLE_DESKTOP_CLIENT_SECRET

Write-Host "FermentaCraft Windows Release Generated"

# Package WITHOUT rebuilding (critical)
dart run msix:create --build-windows=false --store

Write-Host "FermentaCraft MSIX Release Generated"

# Build Web
flutter build web --release --base-href /

Write-Host "FermentaCraft Web Release Generated"

# Build App Bundle for Play Store
flutter build appbundle

Write-Host "FermentaCraft AppBundle Generated"

# Build APKS for Github Release
flutter build apk --release --split-per-abi

Write-Host "FermentaCraft APK Release Files Generated"
Write-Host "Export Completed!"