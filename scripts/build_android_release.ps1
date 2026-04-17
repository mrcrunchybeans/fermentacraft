param(
    [switch]$SkipClean,
    [switch]$UploadToPlay,
    [string]$Track = "internal"
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

# Ensure signing config exists
if (-not (Test-Path "android/key.properties")) {
    throw "Missing android/key.properties. Copy android/key.properties.example and fill in your keystore info."
}

# Try to hydrate RC key from .secrets/.env if not already set
if (-not $env:RC_API_KEY_ANDROID -and (Test-Path ".secrets/.env")) {
    $rcLine = Get-Content .secrets/.env | Where-Object { $_ -match '^RC_API_KEY_ANDROID=' }
    if ($rcLine) {
        $env:RC_API_KEY_ANDROID = $rcLine.Split('=')[1].Trim()
    }
}

if (-not $env:RC_API_KEY_ANDROID) {
    Write-Warning "RC_API_KEY_ANDROID not set; build will proceed but paywall may not work."
}

if (-not $SkipClean) {
    flutter clean
}

flutter pub get

$dartDefines = @()
if ($env:RC_API_KEY_ANDROID) {
    $dartDefines += "--dart-define=RC_API_KEY_ANDROID=$($env:RC_API_KEY_ANDROID)"
}

flutter build appbundle --release @dartDefines

$aabPath = "build/app/outputs/bundle/release/app-release.aab"
if (-not (Test-Path $aabPath)) {
    throw "AAB not found at $aabPath"
}

Write-Host "Built AAB: $aabPath" -ForegroundColor Green

if ($UploadToPlay) {
    if (-not (Test-Path "play_api_key.json")) {
        throw "Upload requested but play_api_key.json is missing in repo root."
    }

    $fastlaneCmd = if (Get-Command fastlane -ErrorAction SilentlyContinue) { "fastlane" } else { $null }
    if (-not $fastlaneCmd) {
        throw "fastlane is not installed or not in PATH. Install Ruby + fastlane or use Play Console to upload manually."
    }

    & $fastlaneCmd supply `
        --aab $aabPath `
        --json_key play_api_key.json `
        --package_name com.fermentacraft `
        --track $Track
}
