# Quick Release Script - Simple wrapper for common release scenarios
# Run this for standard patch releases

param(
    [switch]$Help
)

if ($Help) {
    Write-Host @"
Quick Release Script
====================

This is a simplified wrapper around the full release script for common scenarios.

Usage:
  .\quick-release.ps1           # Standard patch release (2.0.0 -> 2.0.1)
  .\quick-release.ps1 -Help     # Show this help

For advanced options, use the full script:
  .\scripts\release.ps1 -VersionBump minor     # Minor version bump
  .\scripts\release.ps1 -VersionBump major     # Major version bump
  .\scripts\release.ps1 -DryRun                # Test without changes
  .\scripts\release.ps1 -SkipAndroid           # Skip Android build
  .\scripts\release.ps1 -SkipWindows           # Skip Windows build
  .\scripts\release.ps1 -SkipIOS               # Skip iOS trigger
  .\scripts\release.ps1 -SkipGitHub            # Skip GitHub release

See docs/release-script-guide.md for full documentation.
"@
    exit 0
}

Write-Host "Starting standard patch release..." -ForegroundColor Cyan
Write-Host "This will:"
Write-Host "  - Increment patch version (e.g., 2.0.0 -> 2.0.1)"
Write-Host "  - Build Android (AAB + APKs)"
Write-Host "  - Build Windows (EXE + MSIX)"
Write-Host "  - Create GitHub release with artifacts"
Write-Host "  - Trigger iOS build workflow"
Write-Host ""

$response = Read-Host "Continue? (y/N)"
if ($response -ne 'y' -and $response -ne 'Y') {
    Write-Host "Cancelled." -ForegroundColor Yellow
    exit 0
}

# Run the full release script with default settings
& "$PSScriptRoot\scripts\release.ps1" -VersionBump patch
