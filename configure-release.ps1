# Configure Release Script
# Run this once to set your GitHub repository information

param(
    [Parameter(Mandatory=$true)]
    [string]$GitHubRepo
)

$ErrorActionPreference = "Stop"

if ($GitHubRepo -notmatch '^[a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+$') {
    Write-Host "Error: Repository must be in format 'owner/repo'" -ForegroundColor Red
    Write-Host "Example: myusername/fermentacraft" -ForegroundColor Yellow
    exit 1
}

$releaseScript = Join-Path $PSScriptRoot "scripts\release.ps1"

if (-not (Test-Path $releaseScript)) {
    Write-Host "Error: Cannot find release script at $releaseScript" -ForegroundColor Red
    exit 1
}

Write-Host "Updating release script with repository: $GitHubRepo" -ForegroundColor Cyan

$content = Get-Content $releaseScript -Raw
$content = $content -replace 'yourusername/fermentacraft', $GitHubRepo

Set-Content $releaseScript $content -NoNewline

Write-Host "✓ Release script updated successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "GitHub repository set to: $GitHubRepo" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. Ensure .secrets/.env is configured" -ForegroundColor Yellow
Write-Host "2. Run: .\quick-release.ps1" -ForegroundColor Yellow
