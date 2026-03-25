#!/bin/bash
# FermentaCraft Release Script (Linux/macOS)
# Usage: ./release.sh [patch|minor|major] [--dry-run] [--skip-android] [--skip-windows] [--skip-github] [--skip-ios]

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Defaults
VERSION_BUMP="patch"
SKIP_ANDROID=false
SKIP_WINDOWS=false
SKIP_GITHUB=false
SKIP_IOS=false
DRY_RUN=false
RELEASE_NOTES=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        patch|minor|major)
            VERSION_BUMP="$1"
            shift
            ;;
        --skip-android)
            SKIP_ANDROID=true
            shift
            ;;
        --skip-windows)
            SKIP_WINDOWS=true
            shift
            ;;
        --skip-github)
            SKIP_GITHUB=true
            shift
            ;;
        --skip-ios)
            SKIP_IOS=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --notes)
            RELEASE_NOTES="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Helper functions
step() {
    echo -e "\n${CYAN}========================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}========================================${NC}\n"
}

info() {
    echo -e "${YELLOW}ℹ $1${NC}"
}

success() {
    echo -e "${GREEN}✓ $1${NC}"
}

error() {
    echo -e "${RED}✗ $1${NC}"
}

# Navigate to repo root
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

step "FermentaCraft Release Automation"

if $DRY_RUN; then
    info "DRY RUN MODE - No changes will be committed or pushed"
fi

# ============================================
# 1. Load secrets
# ============================================
step "Loading secrets and environment"

ENV_FILE="$REPO_ROOT/.secrets/.env"
if [ -f "$ENV_FILE" ]; then
    info "Loading secrets from .secrets/.env"
    # Export variables from .env (skip comments and empty lines)
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$line" ]] && continue
        key="${line%%=*}"
        value="${line#*=}"
        value="${value#\"}"
        value="${value%\"}"
        export "$key"="$value"
    done < "$ENV_FILE"
else
    error "Warning: .secrets/.env not found. Some features may not work."
fi

# Check required secrets
if [ -z "$RC_API_KEY_ANDROID" ] && [ "$SKIP_ANDROID" = false ]; then
    info "RC_API_KEY_ANDROID not set. Android build may not have RevenueCat configured."
fi

GITHUB_TOKEN="${GITHUB_TOKEN:-}"
if [ -z "$GITHUB_TOKEN" ] && [ "$SKIP_GITHUB" = false ]; then
    info "GITHUB_TOKEN not provided. GitHub release will be skipped."
    SKIP_GITHUB=true
fi

# ============================================
# 2. Version Management
# ============================================
step "Managing Version"

PUBSPEC_PATH="$REPO_ROOT/pubspec.yaml"
PUBSPEC_CONTENT=$(cat "$PUBSPEC_PATH")

# Parse version using grep and sed
VERSION_LINE=$(grep -oP 'version:\s*\K\d+\.\d+\.\d+\+\d+' "$PUBSPEC_PATH")
IFS='+' read -r old_version build_number <<< "$VERSION_LINE"
IFS='.' read -r old_major old_minor old_patch <<< "$old_version"

# Calculate new version
case "$VERSION_BUMP" in
    major)
        new_major=$((old_major + 1))
        new_minor=0
        new_patch=0
        ;;
    minor)
        new_major=$old_major
        new_minor=$((old_minor + 1))
        new_patch=0
        ;;
    patch)
        new_major=$old_major
        new_minor=$old_minor
        new_patch=$((old_patch + 1))
        ;;
esac

new_build=$((build_number + 1))
old_full_version="$old_major.$old_minor.$old_patch+$build_number"
new_full_version="$new_major.$new_minor.$new_patch+$new_build"
version_tag="v$new_major.$new_minor.$new_patch"

info "Current version: $old_full_version"
info "New version: $new_full_version"
info "Git tag: $version_tag"

# Update pubspec.yaml
if [ "$DRY_RUN" = false ]; then
    # Use word boundaries to prevent double-replacement
    sed -i "s/\(version:\s*\)[0-9]\+\.[0-9]\+\.[0-9]\+[+][0-9]\+/\1$new_full_version/" "$PUBSPEC_PATH"

    # Update MSIX version
    msix_version="$new_major.$new_minor.$new_build.0"
    sed -i "s/\(msix_version:\s*\)[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+/\1$msix_version/" "$PUBSPEC_PATH"

    success "Updated pubspec.yaml to version $new_full_version"
fi

# ============================================
# 3. Generate Changelog
# ============================================
step "Generating Changelog"

# Get last tag
last_tag=$(git describe --tags --abbrev=0 2>/dev/null || true)
if [ -z "$last_tag" ]; then
    last_tag=$(git rev-list --max-parents=0 HEAD)
    info "No previous tag found, using initial commit"
fi

info "Generating changelog since $last_tag"

# Get commit messages since last tag
commits=$(git log "$last_tag..HEAD" --pretty=format:"- %s" --no-merges 2>/dev/null || true)

if [ -z "$commits" ]; then
    commits="- Initial release"
fi

# Create changelog content
changelog_header="# Release $version_tag ($new_full_version)

## What's New

"

changelog_content="$changelog_header$commits"

if [ -n "$RELEASE_NOTES" ]; then
    changelog_content="$changelog_header$RELEASE_NOTES

## Commits

$commits"
fi

CHANGELOG_PATH="$REPO_ROOT/CHANGELOG.txt"
echo "$changelog_content" > "$CHANGELOG_PATH"
success "Changelog generated at CHANGELOG.txt"
echo -e "\n--- Changelog Preview ---"
cat "$CHANGELOG_PATH"
echo -e "--- End Changelog ---\n"

# ============================================
# 4. Clean and prepare
# ============================================
step "Cleaning and preparing build"

flutter clean
flutter pub get
success "Flutter clean and pub get completed"

# ============================================
# 5. Build Android
# ============================================
if [ "$SKIP_ANDROID" = false ]; then
    step "Building Android Release"

    if [ ! -f "android/key.properties" ]; then
        error "Missing android/key.properties - skipping Android build"
        SKIP_ANDROID=true
    else
        # Build App Bundle
        dart_defines=""
        if [ -n "$RC_API_KEY_ANDROID" ]; then
            dart_defines="--dart-define=RC_API_KEY_ANDROID=$RC_API_KEY_ANDROID"
        fi

        info "Building Android App Bundle..."
        flutter build appbundle --release $dart_defines

        aab_path="build/app/outputs/bundle/release/app-release.aab"
        if [ -f "$aab_path" ]; then
            success "Android App Bundle built: $aab_path"
        else
            error "Failed to build Android App Bundle"
            exit 1
        fi

        # Build separate APKs for direct distribution
        info "Building split APKs..."
        flutter build apk --split-per-abi --release $dart_defines

        apk_dir="build/app/outputs/flutter-apk"
        if [ -d "$apk_dir" ]; then
            for apk in "$apk_dir"/*-release.apk; do
                if [ -f "$apk" ]; then
                    success "Built APK: $(basename "$apk")"
                fi
            done
        fi
    fi
else
    info "Skipping Android build"
fi

# ============================================
# 6. Build Windows
# ============================================
if [ "$SKIP_WINDOWS" = false ]; then
    step "Building Windows Release"

    # Build EXE
    info "Building Windows EXE..."
    flutter build windows --release

    exe_path="build/windows/x64/runner/Release/fermentacraft.exe"
    if [ -f "$exe_path" ]; then
        success "Windows EXE built: $exe_path"
    else
        error "Failed to build Windows EXE"
        exit 1
    fi

    # Build MSIX
    info "Building Windows MSIX..."
    flutter pub run msix:create

    msix_path="build/windows/x64/runner/Release/fermentacraft.msix"
    if [ -f "$msix_path" ]; then
        success "Windows MSIX built: $msix_path"
    else
        error "Failed to build Windows MSIX"
        exit 1
    fi
else
    info "Skipping Windows build"
fi

# ============================================
# 7. Commit version changes
# ============================================
if [ "$DRY_RUN" = false ]; then
    step "Committing version changes"

    git add pubspec.yaml
    git commit -m "chore: bump version to $new_full_version"
    git tag -a "$version_tag" -m "Release $version_tag"

    success "Version committed and tagged as $version_tag"

    # Push changes
    info "Pushing changes to GitHub..."
    git push origin main
    git push origin "$version_tag"
    success "Changes pushed to GitHub"
else
    info "[DRY RUN] Would commit version $new_full_version and tag as $version_tag"
fi

# ============================================
# 8. Create GitHub Release
# ============================================
if [ "$SKIP_GITHUB" = false ] && [ "$DRY_RUN" = false ]; then
    step "Creating GitHub Release"

    # Prepare release artifacts
    release_dir="$REPO_ROOT/release-artifacts"
    if [ -d "$release_dir" ]; then
        rm -rf "$release_dir"
    fi
    mkdir -p "$release_dir"

    artifacts=()

    if [ "$SKIP_ANDROID" = false ]; then
        aab_path="build/app/outputs/bundle/release/app-release.aab"
        if [ -f "$aab_path" ]; then
            cp "$aab_path" "$release_dir/fermentacraft-$version_tag.aab"
            artifacts+=("$release_dir/fermentacraft-$version_tag.aab")
        fi

        # Copy APKs
        apk_dir="build/app/outputs/flutter-apk"
        if [ -d "$apk_dir" ]; then
            for apk in "$apk_dir"/*-release.apk; do
                if [ -f "$apk" ]; then
                    new_name="fermentacraft-$version_tag-$(basename "$apk")"
                    cp "$apk" "$release_dir/$new_name"
                    artifacts+=("$release_dir/$new_name")
                fi
            done
        fi
    fi

    if [ "$SKIP_WINDOWS" = false ]; then
        msix_path="build/windows/x64/runner/Release/fermentacraft.msix"
        if [ -f "$msix_path" ]; then
            cp "$msix_path" "$release_dir/fermentacraft-$version_tag.msix"
            artifacts+=("$release_dir/fermentacraft-$version_tag.msix")
        fi
    fi

    # Copy changelog
    cp "$CHANGELOG_PATH" "$release_dir/CHANGELOG-$version_tag.txt"

    info "Artifacts prepared in $release_dir"

    # Create GitHub release using gh CLI
    if command -v gh &> /dev/null; then
        info "Creating GitHub release using gh CLI..."

        # Get repo info
        repo_slug=$(git remote get-url origin | sed 's/.*github.com[/:]//' | sed 's/\.git//')

        release_args=("release" "create" "$version_tag" "--title" "Release $version_tag" "--notes-file" "$CHANGELOG_PATH")

        # Add artifacts
        for artifact in "${artifacts[@]}"; do
            release_args+=("$artifact")
        done

        gh "${release_args[@]}"

        success "GitHub release created: https://github.com/$repo_slug/releases/tag/$version_tag"
    else
        info "gh CLI not found. Please create the release manually at: https://github.com/mrcrunchybeans/fermentacraft/releases/new"
    fi
else
    if $DRY_RUN; then
        info "[DRY RUN] Would create GitHub release with tag $version_tag"
    else
        info "Skipping GitHub release"
    fi
fi

# ============================================
# 9. Trigger iOS Release Workflow
# ============================================
if [ "$SKIP_IOS" = false ] && [ "$DRY_RUN" = false ]; then
    step "Triggering iOS Release Workflow"

    if command -v gh &> /dev/null; then
        info "Dispatching iOS release workflow..."

        gh workflow run ios-release.yml \
            --field "release-channel=$version_tag" \
            --field "build-number=$new_build"

        success "iOS release workflow triggered"
    else
        info "gh CLI not found. Please trigger manually at: https://github.com/mrcrunchybeans/fermentacraft/actions/workflows/ios-release.yml"
    fi
else
    if $DRY_RUN; then
        info "[DRY RUN] Would trigger iOS release workflow"
    else
        info "Skipping iOS release workflow"
    fi
fi

# ============================================
# Summary
# ============================================
step "Release Complete!"

echo -e "${GREEN}
Release Summary
===============
Version: $new_full_version
Tag: $version_tag

Built Artifacts:
${NC}"

if [ "$SKIP_ANDROID" = false ]; then
    echo -e "${GREEN}  ✓ Android App Bundle (.aab)${NC}"
    echo -e "${GREEN}  ✓ Android APKs (split per ABI)${NC}"
fi

if [ "$SKIP_WINDOWS" = false ]; then
    echo -e "${GREEN}  ✓ Windows MSIX (Recommended)${NC}"
fi

echo -e "\n${YELLOW}Next Steps:${NC}"
echo -e "${YELLOW}  1. Monitor iOS build at: https://github.com/mrcrunchybeans/fermentacraft/actions${NC}"
echo -e "${YELLOW}  2. Upload .aab to Google Play Console${NC}"
echo -e "${YELLOW}  3. Verify GitHub release: https://github.com/mrcrunchybeans/fermentacraft/releases/tag/$version_tag${NC}"

if $DRY_RUN; then
    echo -e "\n${YELLOW}⚠ DRY RUN MODE - No changes were made${NC}"
fi
