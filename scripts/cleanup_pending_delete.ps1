# scripts/cleanup_pending_delete.ps1
param(
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '..')
Set-Location $root

$pending = Join-Path $root 'pending_delete'
if (-not (Test-Path $pending)) { New-Item -ItemType Directory -Path $pending | Out-Null }

function Move-PathSafe {
  param(
    [Parameter(Mandatory=$true)][string]$Path,
    [Parameter(Mandatory=$true)][string]$DestSubdir
  )
  if (Test-Path -LiteralPath $Path) {
    $dest = Join-Path $pending $DestSubdir
    if (-not (Test-Path $dest)) { New-Item -ItemType Directory -Path $dest | Out-Null }
    if ($DryRun) {
      Write-Host "[DRYRUN] Would move $Path -> $dest"
    } else {
      Write-Host "Moving $Path -> $dest"
      Move-Item -LiteralPath $Path -Destination $dest -Force
    }
  }
}

# High-churn build artifacts/logs
Move-PathSafe 'build' '.'
# Appcircle logs folder -> appcircle/logs
Move-PathSafe 'appcirclelogs' 'appcircle/logs'

# IDE/cache and misc root artifacts
Move-PathSafe 'CppProperties.json' 'ide'
Get-ChildItem -Path $root -Filter '*.iml' -File -ErrorAction SilentlyContinue | ForEach-Object { Move-PathSafe $_.FullName 'ide' }
Get-ChildItem -Path $root -Filter 'Default-Configuration-*.yaml' -File -ErrorAction SilentlyContinue | ForEach-Object { Move-PathSafe $_.FullName 'ide' }

# Zips at root
Get-ChildItem -Path $root -Filter '*.zip' -File -ErrorAction SilentlyContinue | ForEach-Object { Move-PathSafe $_.FullName 'zips' }

# Android IDE metadata
Move-PathSafe 'android/fermentacraft_android.iml' 'ide/android'
Move-PathSafe 'android/flutter_application_1_android.iml' 'ide/android'

# FermentaCraft website temporary/duplicates
Move-PathSafe 'fermentacraftcom/fermentacraftcom.zip' 'zips'
Move-PathSafe 'fermentacraftcom/index.html.new' 'fermentacraftcom'
Move-PathSafe 'fermentacraftcom/index.html.old' 'fermentacraftcom'

# Appcircle configs and iOS logs
Move-PathSafe 'appcircle.yml' 'appcircle'
Move-PathSafe 'APPCIRCLE_SETUP_GUIDE.md' 'appcircle'
Move-PathSafe 'PR-GPT3.yml' 'appcircle'
Move-PathSafe 'ios/7am.yml' 'appcircle/ios'
# iOS Appcircle build logs
Get-ChildItem -Path (Join-Path $root 'ios') -Filter '*build-logs-*.txt' -File -ErrorAction SilentlyContinue | ForEach-Object { Move-PathSafe $_.FullName 'appcircle/ios/logs' }

Write-Host 'Cleanup complete. Review pending_delete before committing or deleting.'
