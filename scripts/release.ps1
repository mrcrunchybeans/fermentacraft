# FermentaCraft Full Release Script
# This script automates the entire release process including:
# - Version increment
# - Building all platforms (Android AAB/APKs, Windows EXE/MSIX)
# - Generating changelog
# - Creating GitHub release with artifacts
# - Triggering iOS release workflow

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("patch", "minor", "major")]
    [string]$VersionBump = "patch",
    
    [Parameter(Mandatory=$false)]
    [string]$ReleaseNotes = "",
    
    [switch]$SkipAndroid,
    [switch]$SkipWindows,
    [switch]$SkipGitHub,
    [switch]$SkipIOS,
    [switch]$DryRun,
    
    [Parameter(Mandatory=$false)]
    [string]$GitHubToken = $env:GITHUB_TOKEN
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

Write-Step "FermentaCraft Release Automation"

if ($DryRun) {
    Write-Info "DRY RUN MODE - No changes will be committed or pushed"
}

# ============================================
# 1. Load secrets
# ============================================
Write-Step "Loading secrets and environment"

$envFile = Join-Path $repoRoot '.secrets\.env'
if (Test-Path $envFile) {
    Write-Info "Loading secrets from .secrets\.env"
    foreach ($line in Get-Content $envFile) {
        if ($line -match '^\s*#' -or $line -match '^\s*$') { continue }
        $kv = $line -split '=', 2
        $key = $kv[0].Trim()
        $value = $kv[1].Trim(' ', '"', "'")
        [Environment]::SetEnvironmentVariable($key, $value, 'Process')
    }
} else {
    Write-ErrorMsg "Warning: .secrets\.env not found. Some features may not work."
}

# Check required secrets
if (-not $SkipAndroid -and [string]::IsNullOrWhiteSpace($env:RC_API_KEY_ANDROID)) {
    Write-Info "RC_API_KEY_ANDROID not set. Android build may not have RevenueCat configured."
}

if (-not $SkipGitHub -and [string]::IsNullOrWhiteSpace($GitHubToken)) {
    Write-Info "GITHUB_TOKEN not provided. GitHub release will be skipped."
    $SkipGitHub = $true
}

# ============================================
# 2. Version Management
# ============================================
Write-Step "Managing Version"

$pubspecPath = Join-Path $repoRoot 'pubspec.yaml'
$pubspecContent = Get-Content $pubspecPath -Raw

if ($pubspecContent -match 'version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)') {
    $oldMajor = [int]$Matches[1]
    $oldMinor = [int]$Matches[2]
    $oldPatch = [int]$Matches[3]
    $oldBuild = [int]$Matches[4]
    
    # Calculate new version
    switch ($VersionBump) {
        "major" {
            $newMajor = $oldMajor + 1
            $newMinor = 0
            $newPatch = 0
        }
        "minor" {
            $newMajor = $oldMajor
            $newMinor = $oldMinor + 1
            $newPatch = 0
        }
        "patch" {
            $newMajor = $oldMajor
            $newMinor = $oldMinor
            $newPatch = $oldPatch + 1
        }
    }
    
    $newBuild = $oldBuild + 1
    $oldVersion = "$oldMajor.$oldMinor.$oldPatch+$oldBuild"
    $newVersion = "$newMajor.$newMinor.$newPatch+$newBuild"
    $versionTag = "v$newMajor.$newMinor.$newPatch"
    
    Write-Info "Current version: $oldVersion"
    Write-Info "New version: $newVersion"
    Write-Info "Git tag: $versionTag"
    
    # Update pubspec.yaml
    $newPubspecContent = $pubspecContent -replace 'version:\s*\d+\.\d+\.\d+\+\d+', "version: $newVersion"
    
    # Update MSIX version
    $msixVersion = "$newMajor.$newMinor.$newBuild.0"
    $newPubspecContent = $newPubspecContent -replace 'msix_version:\s*\d+\.\d+\.\d+\.\d+', "msix_version: $msixVersion"
    
    if (-not $DryRun) {
        Set-Content $pubspecPath $newPubspecContent -NoNewline
        Write-Success "Updated pubspec.yaml to version $newVersion"
    }
} else {
    Write-ErrorMsg "Could not parse version from pubspec.yaml"
    exit 1
}

# ============================================
# 3. Generate Changelog
# ============================================
Write-Step "Generating Changelog"

# Get last tag
$lastTag = git describe --tags --abbrev=0 2>$null
if (-not $lastTag) {
    $lastTag = (git rev-list --max-parents=0 HEAD)
    Write-Info "No previous tag found, using initial commit"
}

Write-Info "Generating changelog since $lastTag"

# Get commit messages since last tag
$commits = git log "$lastTag..HEAD" --pretty=format:"- %s" --no-merges

if ([string]::IsNullOrWhiteSpace($commits)) {
    $commits = "- Initial release"
}

# Create changelog content
$changelogHeader = @"
# Release $versionTag ($newVersion)

## What's New

"@

$changelogContent = $changelogHeader + "`n" + $commits

if (-not [string]::IsNullOrWhiteSpace($ReleaseNotes)) {
    $changelogContent = $changelogHeader + $ReleaseNotes + "`n`n## Commits`n`n" + $commits
}

$changelogPath = Join-Path $repoRoot "CHANGELOG.txt"
Set-Content $changelogPath $changelogContent
Write-Success "Changelog generated at CHANGELOG.txt"
Write-Host "`n--- Changelog Preview ---" -ForegroundColor Gray
Write-Host $changelogContent -ForegroundColor Gray
Write-Host "--- End Changelog ---`n" -ForegroundColor Gray

# ============================================
# 4. Clean and prepare
# ============================================
Write-Step "Cleaning and preparing build"

flutter clean
flutter pub get
Write-Success "Flutter clean and pub get completed"

# ============================================
# 5. Build Android
# ============================================
if (-not $SkipAndroid) {
    Write-Step "Building Android Release"
    
    # Check for signing config
    if (-not (Test-Path "android/key.properties")) {
        Write-ErrorMsg "Missing android/key.properties - skipping Android build"
        $SkipAndroid = $true
    } else {
        # Build App Bundle
        $dartDefines = @()
        if ($env:RC_API_KEY_ANDROID) {
            $dartDefines += "--dart-define=RC_API_KEY_ANDROID=$($env:RC_API_KEY_ANDROID)"
        }
        
        Write-Info "Building Android App Bundle..."
        flutter build appbundle --release @dartDefines
        
        $aabPath = "build/app/outputs/bundle/release/app-release.aab"
        if (Test-Path $aabPath) {
            Write-Success "Android App Bundle built: $aabPath"
        } else {
            Write-ErrorMsg "Failed to build Android App Bundle"
            exit 1
        }
        
        # Build separate APKs for direct distribution
        Write-Info "Building split APKs..."
        flutter build apk --split-per-abi --release @dartDefines
        
        $apkDir = "build/app/outputs/flutter-apk"
        if (Test-Path $apkDir) {
            $apks = Get-ChildItem -Path $apkDir -Filter "*.apk"
            foreach ($apk in $apks) {
                Write-Success "Built APK: $($apk.Name)"
            }
        }
    }
} else {
    Write-Info "Skipping Android build"
}

# ============================================
# 6. Build Windows
# ============================================
if (-not $SkipWindows) {
    Write-Step "Building Windows Release"
    
    # Build EXE
    Write-Info "Building Windows EXE..."
    flutter build windows --release
    
    $exePath = "build/windows/x64/runner/Release/fermentacraft.exe"
    if (Test-Path $exePath) {
        Write-Success "Windows EXE built: $exePath"
    } else {
        Write-ErrorMsg "Failed to build Windows EXE"
        exit 1
    }
    
    # Build MSIX
    Write-Info "Building Windows MSIX..."
    flutter pub run msix:create
    
    $msixPath = "build/windows/x64/runner/Release/fermentacraft.msix"
    if (Test-Path $msixPath) {
        Write-Success "Windows MSIX built: $msixPath"
    } else {
        Write-ErrorMsg "Failed to build Windows MSIX"
        exit 1
    }
} else {
    Write-Info "Skipping Windows build"
}

# ============================================
# 7. Commit version changes
# ============================================
if (-not $DryRun) {
    Write-Step "Committing version changes"
    
    git add pubspec.yaml
    git commit -m "chore: bump version to $newVersion"
    git tag -a $versionTag -m "Release $versionTag"
    
    Write-Success "Version committed and tagged as $versionTag"
    
    # Push changes
    Write-Info "Pushing changes to GitHub..."
    git push origin main
    git push origin $versionTag
    Write-Success "Changes pushed to GitHub"
} else {
    Write-Info "[DRY RUN] Would commit version $newVersion and tag as $versionTag"
}

# ============================================
# 8. Create GitHub Release
# ============================================
if (-not $SkipGitHub -and -not $DryRun) {
    Write-Step "Creating GitHub Release"
    
    # Prepare release artifacts
    $releaseDir = Join-Path $repoRoot "release-artifacts"
    if (Test-Path $releaseDir) {
        Remove-Item $releaseDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $releaseDir | Out-Null
    
    # Copy artifacts
    $artifacts = @()
    
    if (-not $SkipAndroid) {
        $aabPath = "build/app/outputs/bundle/release/app-release.aab"
        if (Test-Path $aabPath) {
            Copy-Item $aabPath (Join-Path $releaseDir "fermentacraft-$versionTag.aab")
            $artifacts += Join-Path $releaseDir "fermentacraft-$versionTag.aab"
        }
        
        # Copy APKs
        $apkDir = "build/app/outputs/flutter-apk"
        if (Test-Path $apkDir) {
            $apks = Get-ChildItem -Path $apkDir -Filter "*-release.apk"
            foreach ($apk in $apks) {
                $newName = "fermentacraft-$versionTag-$($apk.Name)"
                Copy-Item $apk.FullName (Join-Path $releaseDir $newName)
                $artifacts += Join-Path $releaseDir $newName
            }
        }
    }
    
    if (-not $SkipWindows) {
        $msixPath = "build/windows/x64/runner/Release/fermentacraft.msix"
        if (Test-Path $msixPath) {
            Copy-Item $msixPath (Join-Path $releaseDir "fermentacraft-$versionTag.msix")
            $artifacts += Join-Path $releaseDir "fermentacraft-$versionTag.msix"
        }
        
        # Include portable version with bundled DLLs
        Write-Info "Creating portable Windows version with bundled DLLs..."
        $portableDir = Join-Path $releaseDir "fermentacraft-$versionTag-portable"
        
        # Build portable package
        & (Join-Path $repoRoot "scripts\build-windows-portable.ps1") -OutputDir $portableDir | Out-Null
        
        if (Test-Path $portableDir) {
            # Create ZIP of portable version
            $portableZip = Join-Path $releaseDir "fermentacraft-$versionTag-portable.zip"
            Compress-Archive -Path "$portableDir/*" -DestinationPath $portableZip -Force
            
            if (Test-Path $portableZip) {
                Write-Success "Portable version packaged: $portableZip"
                $artifacts += $portableZip
            }
        }
    }
    
    # Copy changelog
    Copy-Item $changelogPath (Join-Path $releaseDir "CHANGELOG-$versionTag.txt")
    
    Write-Info "Artifacts prepared in $releaseDir"
    
    # Create GitHub release using gh CLI
    if (Get-Command gh -ErrorAction SilentlyContinue) {
        Write-Info "Creating GitHub release using gh CLI..."
        
        $releaseArgs = @(
            "release", "create", $versionTag,
            "--title", "Release $versionTag",
            "--notes-file", $changelogPath
        )
        
        # Add artifacts
        foreach ($artifact in $artifacts) {
            $releaseArgs += $artifact
        }
        
        & gh @releaseArgs
        
        Write-Success "GitHub release created: https://github.com/yourusername/fermentacraft/releases/tag/$versionTag"
    } else {
        Write-Info "gh CLI not found. Creating release via API..."
        
        # Use GitHub API to create release
        $apiUrl = "https://api.github.com/repos/yourusername/fermentacraft/releases"
        
        $releaseBody = @{
            tag_name = $versionTag
            name = "Release $versionTag"
            body = $changelogContent
            draft = $false
            prerelease = $false
        } | ConvertTo-Json
        
        $headers = @{
            "Authorization" = "token $GitHubToken"
            "Accept" = "application/vnd.github.v3+json"
        }
        
        try {
            $response = Invoke-RestMethod -Uri $apiUrl -Method Post -Headers $headers -Body $releaseBody -ContentType "application/json"
            $uploadUrl = $response.upload_url -replace '\{\?.*\}', ''
            
            Write-Success "GitHub release created"
            
            # Upload artifacts
            foreach ($artifact in $artifacts) {
                $fileName = [System.IO.Path]::GetFileName($artifact)
                $uploadUri = "$uploadUrl?name=$fileName"
                
                Write-Info "Uploading $fileName..."
                
                $fileBytes = [System.IO.File]::ReadAllBytes($artifact)
                Invoke-RestMethod -Uri $uploadUri -Method Post -Headers $headers -Body $fileBytes -ContentType "application/octet-stream" | Out-Null
                
                Write-Success "Uploaded $fileName"
            }
            
            Write-Success "All artifacts uploaded to GitHub release"
        } catch {
            Write-ErrorMsg "Failed to create GitHub release: $_"
            Write-Info "You can manually create the release at: https://github.com/yourusername/fermentacraft/releases/new"
        }
    }
} else {
    if ($DryRun) {
        Write-Info "[DRY RUN] Would create GitHub release with tag $versionTag"
    } else {
        Write-Info "Skipping GitHub release"
    }
}

# ============================================
# 9. Trigger iOS Release Workflow
# ============================================
if (-not $SkipIOS -and -not $DryRun) {
    Write-Step "Triggering iOS Release Workflow"
    
    if (Get-Command gh -ErrorAction SilentlyContinue) {
        Write-Info "Dispatching iOS release workflow..."
        
        gh workflow run ios-release.yml `
            --field "release-channel=$versionTag" `
            --field "build-number=$newBuild"
        
        Write-Success "iOS release workflow triggered"
        Write-Info "Monitor progress at: https://github.com/yourusername/fermentacraft/actions/workflows/ios-release.yml"
    } else {
        Write-Info "gh CLI not found. Triggering via API..."
        
        $apiUrl = "https://api.github.com/repos/yourusername/fermentacraft/actions/workflows/ios-release.yml/dispatches"
        
        $workflowBody = @{
            ref = "main"
            inputs = @{
                "release-channel" = $versionTag
                "build-number" = $newBuild.ToString()
            }
        } | ConvertTo-Json
        
        $headers = @{
            "Authorization" = "token $GitHubToken"
            "Accept" = "application/vnd.github.v3+json"
        }
        
        try {
            Invoke-RestMethod -Uri $apiUrl -Method Post -Headers $headers -Body $workflowBody -ContentType "application/json" | Out-Null
            Write-Success "iOS release workflow triggered via API"
        } catch {
            Write-ErrorMsg "Failed to trigger iOS workflow: $_"
            Write-Info "Manually trigger at: https://github.com/yourusername/fermentacraft/actions/workflows/ios-release.yml"
        }
    }
} else {
    if ($DryRun) {
        Write-Info "[DRY RUN] Would trigger iOS release workflow"
    } else {
        Write-Info "Skipping iOS release workflow"
    }
}

# ============================================
# Summary
# ============================================
Write-Step "Release Complete! 🎉"

Write-Host @"

Release Summary
===============
Version: $newVersion
Tag: $versionTag

Built Artifacts:
"@ -ForegroundColor Green

if (-not $SkipAndroid) {
    Write-Host "  ✓ Android App Bundle (.aab)" -ForegroundColor Green
    Write-Host "  ✓ Android APKs (split per ABI)" -ForegroundColor Green
}

if (-not $SkipWindows) {
    Write-Host "  ✓ Windows MSIX (Recommended)" -ForegroundColor Green
    Write-Host "  ✓ Windows Portable with bundled DLLs (.zip)" -ForegroundColor Green
    Write-Host "  ✓ Installation helpers included" -ForegroundColor Green
}

Write-Host "`nNext Steps:" -ForegroundColor Yellow
Write-Host "  1. Monitor iOS build at: https://github.com/yourusername/fermentacraft/actions" -ForegroundColor Yellow
Write-Host "  2. Upload .aab to Google Play Console" -ForegroundColor Yellow
Write-Host "  3. Windows Distribution:" -ForegroundColor Yellow
Write-Host "     - Recommend users download .msix (MSIX package)" -ForegroundColor Yellow
Write-Host "     - Provide -portable.zip as alternative (for Windows 7/8 or USB)" -ForegroundColor Yellow
Write-Host "     - Optionally submit .msix to Microsoft Store" -ForegroundColor Yellow
Write-Host "  4. Verify GitHub release: https://github.com/yourusername/fermentacraft/releases/tag/$versionTag" -ForegroundColor Yellow
Write-Host "  5. Update Windows install docs: See WINDOWS-RELEASE-INSTRUCTIONS.md" -ForegroundColor Yellow

if ($DryRun) {
    Write-Host "`n⚠ DRY RUN MODE - No changes were made" -ForegroundColor Yellow
}
