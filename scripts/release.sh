#!/usr/bin/env bash
# FermentaCraft Release Script
# Expected location: scripts/release.sh

set -Eeuo pipefail

# =========================
# Defaults
# =========================
VERSION_BUMP="patch"
DRY_RUN=false

SKIP_ANDROID=false
SKIP_WINDOWS_LOCAL=false
SKIP_LINUX_LOCAL=false
SKIP_GITHUB_RELEASE=false
SKIP_IOS_CI=false
SKIP_WINDOWS_CI=false
SKIP_LINUX_CI=false

ALLOW_DIRTY=false
ENFORCE_BRANCH=true
RELEASE_BRANCH="main"
RELEASE_NOTES=""

# rollback state
SNAPSHOT_CREATED=false
COMMIT_CREATED=false
ORIGINAL_PUBSPEC=""
ORIGINAL_CHANGELOG_EXISTS=false
ORIGINAL_CHANGELOG=""

# =========================
# Colors
# =========================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# =========================
# Logging
# =========================
step() {
  echo -e "\n${CYAN}========================================${NC}"
  echo -e "${CYAN}$1${NC}"
  echo -e "${CYAN}========================================${NC}\n"
}

info()    { echo -e "${YELLOW}ℹ $1${NC}"; }
success() { echo -e "${GREEN}✓ $1${NC}"; }
warn()    { echo -e "${YELLOW}⚠ $1${NC}"; }
error()   { echo -e "${RED}✗ $1${NC}" >&2; }

die() {
  error "$1"
  exit 1
}

# =========================
# Path resolution
# =========================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PUBSPEC_PATH="$REPO_ROOT/pubspec.yaml"
CHANGELOG_PATH="$REPO_ROOT/CHANGELOG.txt"
ENV_FILE="$REPO_ROOT/.secrets/.env"
RELEASE_DIR="$REPO_ROOT/release-artifacts"
ANDROID_KEY_PROPERTIES="$REPO_ROOT/android/key.properties"

cd "$REPO_ROOT"

# =========================
# OS detection
# =========================
OS_NAME="$(uname -s 2>/dev/null || echo unknown)"
IS_LINUX=false
IS_MAC=false
IS_WINDOWS=false

case "$OS_NAME" in
  Linux*) IS_LINUX=true ;;
  Darwin*) IS_MAC=true ;;
  MINGW*|MSYS*|CYGWIN*) IS_WINDOWS=true ;;
esac

# Auto-skip local builds that don't match host
$IS_WINDOWS || SKIP_WINDOWS_LOCAL=true
$IS_LINUX   || SKIP_LINUX_LOCAL=true

# =========================
# Cleanup / rollback
# =========================
restore_files() {
  $DRY_RUN && return 0
  $COMMIT_CREATED && return 0
  $SNAPSHOT_CREATED || return 0

  printf '%s' "$ORIGINAL_PUBSPEC" > "$PUBSPEC_PATH"

  if $ORIGINAL_CHANGELOG_EXISTS; then
    printf '%s' "$ORIGINAL_CHANGELOG" > "$CHANGELOG_PATH"
  else
    rm -f "$CHANGELOG_PATH"
  fi
}

on_error() {
  local line="$1"
  error "Release script failed at line $line"
  restore_files
}

trap 'on_error $LINENO' ERR

# =========================
# Helpers
# =========================
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

require_command() {
  command_exists "$1" || die "Required command not found: $1"
}

run_cmd() {
  if $DRY_RUN; then
    info "[DRY RUN] $*"
  else
    "$@"
  fi
}

safe_sed_inplace() {
  local expr="$1"
  local file="$2"

  if $IS_MAC; then
    sed -i '' -E "$expr" "$file"
  else
    sed -i -E "$expr" "$file"
  fi
}

snapshot_files() {
  ORIGINAL_PUBSPEC="$(cat "$PUBSPEC_PATH")"

  if [[ -f "$CHANGELOG_PATH" ]]; then
    ORIGINAL_CHANGELOG_EXISTS=true
    ORIGINAL_CHANGELOG="$(cat "$CHANGELOG_PATH")"
  else
    ORIGINAL_CHANGELOG_EXISTS=false
    ORIGINAL_CHANGELOG=""
  fi

  SNAPSHOT_CREATED=true
}

load_env_file() {
  local file="$1"
  [[ -f "$file" ]] || return 0

  info "Loading environment from $file"

  # shellcheck disable=SC2163
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] || continue

    local key="${line%%=*}"
    local value="${line#*=}"

    if [[ "$value" =~ ^\".*\"$ ]]; then
      value="${value:1:${#value}-2}"
    elif [[ "$value" =~ ^\'.*\'$ ]]; then
      value="${value:1:${#value}-2}"
    fi

    export "$key=$value"
  done < "$file"
}

git_repo_slug() {
  local remote_url
  remote_url="$(git remote get-url origin 2>/dev/null || true)"
  [[ -n "$remote_url" ]] || { echo ""; return; }

  remote_url="${remote_url%.git}"
  remote_url="${remote_url#git@github.com:}"
  remote_url="${remote_url#https://github.com/}"
  echo "$remote_url"
}

current_branch() {
  git rev-parse --abbrev-ref HEAD
}

ensure_clean_git() {
  if $ALLOW_DIRTY; then
    warn "Proceeding with dirty working tree because --allow-dirty was used"
    return 0
  fi

  [[ -z "$(git status --porcelain)" ]] || die "Git working tree is not clean. Commit/stash/remove changes or use --allow-dirty."
}

enforce_branch_rule() {
  local branch="$1"

  $ENFORCE_BRANCH || {
    warn "Branch enforcement disabled"
    return 0
  }

  [[ "$branch" == "$RELEASE_BRANCH" ]] || die "Releases must be run from '$RELEASE_BRANCH' (current: $branch)"
}

read_pubspec_version() {
  local version_line
  version_line="$(awk '/^version:/ {print $2; exit}' "$PUBSPEC_PATH" | tr -d '\r')"
  [[ -n "$version_line" ]] || die "Could not find version in pubspec.yaml"
  echo "$version_line"
}

bump_version() {
  local full_version="$1"

  local semver build major minor patch
  IFS='+' read -r semver build <<< "$full_version"
  IFS='.' read -r major minor patch <<< "$semver"

  [[ -n "$major" && -n "$minor" && -n "$patch" && -n "$build" ]] || die "Invalid version format in pubspec.yaml: $full_version"

  case "$VERSION_BUMP" in
    major)
      major=$((major + 1))
      minor=0
      patch=0
      ;;
    minor)
      minor=$((minor + 1))
      patch=0
      ;;
    patch)
      patch=$((patch + 1))
      ;;
    *)
      die "Invalid version bump: $VERSION_BUMP"
      ;;
  esac

  build=$((build + 1))

  NEW_SEMVER="${major}.${minor}.${patch}"
  NEW_BUILD="$build"
  NEW_FULL_VERSION="${NEW_SEMVER}+${NEW_BUILD}"
  VERSION_TAG="v${NEW_SEMVER}"
  MSIX_VERSION="${major}.${minor}.${build}.0"
}

ensure_tag_does_not_exist() {
  local tag="$1"
  if git rev-parse "$tag" >/dev/null 2>&1; then
    die "Git tag already exists: $tag"
  fi
}

update_pubspec() {
  safe_sed_inplace \
    "s/^version:[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+/version: ${NEW_FULL_VERSION}/" \
    "$PUBSPEC_PATH"

  if grep -q '^msix_version:' "$PUBSPEC_PATH"; then
    safe_sed_inplace \
      "s/^msix_version:[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/msix_version: ${MSIX_VERSION}/" \
      "$PUBSPEC_PATH"
  else
    warn "No msix_version found in pubspec.yaml; skipped MSIX version update"
  fi
}

last_tag_or_initial_commit() {
  local last_tag
  last_tag="$(git describe --tags --abbrev=0 2>/dev/null || true)"
  if [[ -n "$last_tag" ]]; then
    echo "$last_tag"
  else
    git rev-list --max-parents=0 HEAD | tail -n 1
  fi
}

generate_changelog() {
  local base_ref="$1"
  local commits

  commits="$(git log "${base_ref}..HEAD" --pretty=format:"- %s" --no-merges 2>/dev/null || true)"
  [[ -n "$commits" ]] || commits="- Initial release"

  {
    echo "# Release ${VERSION_TAG} (${NEW_FULL_VERSION})"
    echo
    echo "## What's New"
    echo

    if [[ -n "$RELEASE_NOTES" ]]; then
      echo "$RELEASE_NOTES"
      echo
      echo "## Commits"
      echo
    fi

    echo "$commits"
  } > "$CHANGELOG_PATH"
}

collect_dart_defines() {
  local platform="$1"
  local defines=()

  case "$platform" in
    android)
      [[ -n "${RC_API_KEY_ANDROID:-}" ]] && defines+=("--dart-define=RC_API_KEY_ANDROID=${RC_API_KEY_ANDROID}")
      [[ -n "${GA_MEASUREMENT_ID:-}" ]] && defines+=("--dart-define=GA_MEASUREMENT_ID=${GA_MEASUREMENT_ID}")
      [[ -n "${GA_API_SECRET:-}" ]] && defines+=("--dart-define=GA_API_SECRET=${GA_API_SECRET}")
      ;;
    windows)
      [[ -n "${GOOGLE_DESKTOP_CLIENT_SECRET:-}" ]] && defines+=("--dart-define=GOOGLE_DESKTOP_CLIENT_SECRET=${GOOGLE_DESKTOP_CLIENT_SECRET}")
      [[ -n "${GA_MEASUREMENT_ID:-}" ]] && defines+=("--dart-define=GA_MEASUREMENT_ID=${GA_MEASUREMENT_ID}")
      [[ -n "${GA_API_SECRET:-}" ]] && defines+=("--dart-define=GA_API_SECRET=${GA_API_SECRET}")
      ;;
    linux)
      [[ -n "${GA_MEASUREMENT_ID:-}" ]] && defines+=("--dart-define=GA_MEASUREMENT_ID=${GA_MEASUREMENT_ID}")
      [[ -n "${GA_API_SECRET:-}" ]] && defines+=("--dart-define=GA_API_SECRET=${GA_API_SECRET}")
      ;;
  esac

  printf '%s\n' "${defines[@]}"
}

prepare_release_dir() {
  rm -rf "$RELEASE_DIR"
  mkdir -p "$RELEASE_DIR"
}

# =========================
# Args
# =========================
while [[ $# -gt 0 ]]; do
  case "$1" in
    patch|minor|major)
      VERSION_BUMP="$1"
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --skip-android)
      SKIP_ANDROID=true
      shift
      ;;
    --skip-windows)
      SKIP_WINDOWS_LOCAL=true
      shift
      ;;
    --skip-linux)
      SKIP_LINUX_LOCAL=true
      shift
      ;;
    --skip-github)
      SKIP_GITHUB_RELEASE=true
      shift
      ;;
    --skip-ios)
      SKIP_IOS_CI=true
      shift
      ;;
    --skip-win-ci)
      SKIP_WINDOWS_CI=true
      shift
      ;;
    --skip-linux-ci)
      SKIP_LINUX_CI=true
      shift
      ;;
    --allow-dirty)
      ALLOW_DIRTY=true
      shift
      ;;
    --no-branch-check)
      ENFORCE_BRANCH=false
      shift
      ;;
    --allow-branch)
      [[ $# -ge 2 ]] || die "--allow-branch requires a branch name"
      RELEASE_BRANCH="$2"
      shift 2
      ;;
    --notes)
      [[ $# -ge 2 ]] || die "--notes requires a value"
      RELEASE_NOTES="$2"
      shift 2
      ;;
    *)
      die "Unknown option: $1"
      ;;
  esac
done

# =========================
# Start
# =========================
step "FermentaCraft Release Automation"

info "Script dir: $SCRIPT_DIR"
info "Repo root: $REPO_ROOT"
info "Detected OS: $OS_NAME"

$DRY_RUN && warn "DRY RUN MODE enabled"
$SKIP_WINDOWS_LOCAL && info "Local Windows build will be skipped"
$SKIP_LINUX_LOCAL && info "Local Linux build will be skipped"

[[ -f "$PUBSPEC_PATH" ]] || die "pubspec.yaml not found at $PUBSPEC_PATH"

require_command git
require_command awk
require_command sed
require_command grep

if [[ "$SKIP_ANDROID" = false || "$SKIP_WINDOWS_LOCAL" = false || "$SKIP_LINUX_LOCAL" = false ]]; then
  require_command flutter
fi

step "Loading environment"
load_env_file "$ENV_FILE"

if [[ -z "${RC_API_KEY_ANDROID:-}" && "$SKIP_ANDROID" = false ]]; then
  warn "RC_API_KEY_ANDROID is not set. Android build may not have RevenueCat configured."
fi

if [[ -z "${RC_API_KEY_IOS:-}" && "$SKIP_IOS_CI" = false ]]; then
  warn "RC_API_KEY_IOS is not set. iOS workflow may not have RevenueCat configured."
fi

if [[ -z "${GOOGLE_DESKTOP_CLIENT_SECRET:-}" && "$SKIP_WINDOWS_LOCAL" = false ]]; then
  warn "GOOGLE_DESKTOP_CLIENT_SECRET is not set. Windows OAuth may not work."
fi

step "Checking git state"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "This is not a git repository"

CURRENT_BRANCH="$(current_branch)"
REPO_SLUG="$(git_repo_slug)"

info "Current branch: $CURRENT_BRANCH"
[[ -n "$REPO_SLUG" ]] && info "GitHub repo: $REPO_SLUG" || warn "Could not detect GitHub repo slug from origin remote"

enforce_branch_rule "$CURRENT_BRANCH"
ensure_clean_git

step "Managing version"

CURRENT_FULL_VERSION="$(read_pubspec_version)"
bump_version "$CURRENT_FULL_VERSION"
ensure_tag_does_not_exist "$VERSION_TAG"

info "Current version: $CURRENT_FULL_VERSION"
info "New version: $NEW_FULL_VERSION"
info "Version tag: $VERSION_TAG"
info "MSIX version: $MSIX_VERSION"

if ! $DRY_RUN; then
  snapshot_files
  update_pubspec
  success "Updated pubspec.yaml"
else
  info "[DRY RUN] Would update pubspec.yaml to $NEW_FULL_VERSION"
fi

step "Generating changelog"

BASE_REF="$(last_tag_or_initial_commit)"
info "Generating changelog since: $BASE_REF"

if ! $DRY_RUN; then
  generate_changelog "$BASE_REF"
  success "Changelog written to $CHANGELOG_PATH"
else
  info "[DRY RUN] Would write changelog to $CHANGELOG_PATH"
fi

if [[ -f "$CHANGELOG_PATH" ]]; then
  echo -e "\n--- Changelog Preview ---"
  cat "$CHANGELOG_PATH"
  echo -e "\n--- End Changelog ---\n"
fi

if [[ "$SKIP_ANDROID" = false || "$SKIP_WINDOWS_LOCAL" = false || "$SKIP_LINUX_LOCAL" = false ]]; then
  step "Preparing Flutter"
  run_cmd flutter clean
  run_cmd flutter pub get
  success "Flutter preparation complete"
fi

if [[ "$SKIP_ANDROID" = false ]]; then
  step "Building Android release"

  if [[ ! -f "$ANDROID_KEY_PROPERTIES" ]]; then
    warn "Missing android/key.properties - skipping Android build"
    SKIP_ANDROID=true
  else
    mapfile -t ANDROID_DEFINES < <(collect_dart_defines android)

    if ! $DRY_RUN; then
      flutter build appbundle --release "${ANDROID_DEFINES[@]}"
      flutter build apk --split-per-abi --release "${ANDROID_DEFINES[@]}"
    else
      info "[DRY RUN] flutter build appbundle --release ${ANDROID_DEFINES[*]}"
      info "[DRY RUN] flutter build apk --split-per-abi --release ${ANDROID_DEFINES[*]}"
    fi

    if ! $DRY_RUN; then
      AAB_PATH="$REPO_ROOT/build/app/outputs/bundle/release/app-release.aab"
      [[ -f "$AAB_PATH" ]] || die "Android App Bundle not found after build"
      success "Android App Bundle built: $AAB_PATH"

      APK_DIR="$REPO_ROOT/build/app/outputs/flutter-apk"
      if [[ -d "$APK_DIR" ]]; then
        shopt -s nullglob
        for apk in "$APK_DIR"/*-release.apk; do
          success "Built APK: $(basename "$apk")"
        done
        shopt -u nullglob
      fi
    fi
  fi
else
  info "Skipping Android build"
fi

if [[ "$SKIP_WINDOWS_LOCAL" = false ]]; then
  step "Building Windows release"

  mapfile -t WINDOWS_DEFINES < <(collect_dart_defines windows)

  if ! $DRY_RUN; then
    flutter build windows --release "${WINDOWS_DEFINES[@]}"
  else
    info "[DRY RUN] flutter build windows --release ${WINDOWS_DEFINES[*]}"
  fi

  if ! $DRY_RUN; then
    WINDOWS_EXE="$REPO_ROOT/build/windows/x64/runner/Release/fermentacraft.exe"
    [[ -f "$WINDOWS_EXE" ]] || die "Windows EXE not found after build"
    success "Windows EXE built: $WINDOWS_EXE"
  fi

  if grep -q 'msix:' "$PUBSPEC_PATH" || grep -q '^msix_version:' "$PUBSPEC_PATH"; then
    if ! $DRY_RUN; then
      flutter pub run msix:create
    else
      info "[DRY RUN] flutter pub run msix:create"
    fi

    if ! $DRY_RUN; then
      WINDOWS_MSIX="$REPO_ROOT/build/windows/x64/runner/Release/fermentacraft.msix"
      if [[ -f "$WINDOWS_MSIX" ]]; then
        success "Windows MSIX built: $WINDOWS_MSIX"
      else
        warn "Windows MSIX not found after build. Verify plugin output path."
      fi
    fi
  else
    warn "No MSIX config found in pubspec.yaml; skipping MSIX packaging"
  fi
else
  info "Skipping local Windows build"
fi

if [[ "$SKIP_LINUX_LOCAL" = false ]]; then
  step "Building Linux release"

  mapfile -t LINUX_DEFINES < <(collect_dart_defines linux)

  if ! $DRY_RUN; then
    flutter build linux --release "${LINUX_DEFINES[@]}"
  else
    info "[DRY RUN] flutter build linux --release ${LINUX_DEFINES[*]}"
  fi

  if ! $DRY_RUN; then
    LINUX_BUNDLE="$REPO_ROOT/build/linux/x64/release/bundle"
    [[ -d "$LINUX_BUNDLE" ]] || die "Linux bundle not found after build"
    success "Linux bundle built: $LINUX_BUNDLE"
  fi
else
  info "Skipping local Linux build"
fi

step "Committing version changes"

if ! $DRY_RUN; then
  git add "$PUBSPEC_PATH"
  [[ -f "$CHANGELOG_PATH" ]] && git add "$CHANGELOG_PATH"

  git diff --cached --quiet && die "No staged changes to commit"

  git commit -m "chore: bump version to $NEW_FULL_VERSION"
  COMMIT_CREATED=true
  success "Committed version bump"

  git tag -a "$VERSION_TAG" -m "Release $VERSION_TAG"
  success "Created tag: $VERSION_TAG"

  git push origin "$CURRENT_BRANCH"
  git push origin "$VERSION_TAG"
  success "Pushed commit and tag"
else
  info "[DRY RUN] Would commit version bump and create tag $VERSION_TAG"
fi

if [[ "$SKIP_GITHUB_RELEASE" = false ]]; then
  step "Creating GitHub release"

  if ! $DRY_RUN; then
    prepare_release_dir
    declare -a ARTIFACTS=()

    if [[ "$SKIP_ANDROID" = false ]]; then
      AAB_PATH="$REPO_ROOT/build/app/outputs/bundle/release/app-release.aab"
      if [[ -f "$AAB_PATH" ]]; then
        cp "$AAB_PATH" "$RELEASE_DIR/fermentacraft-$VERSION_TAG.aab"
        ARTIFACTS+=("$RELEASE_DIR/fermentacraft-$VERSION_TAG.aab")
      fi

      APK_DIR="$REPO_ROOT/build/app/outputs/flutter-apk"
      if [[ -d "$APK_DIR" ]]; then
        shopt -s nullglob
        for apk in "$APK_DIR"/*-release.apk; do
          NEW_NAME="fermentacraft-$VERSION_TAG-$(basename "$apk")"
          cp "$apk" "$RELEASE_DIR/$NEW_NAME"
          ARTIFACTS+=("$RELEASE_DIR/$NEW_NAME")
        done
        shopt -u nullglob
      fi
    fi

    if [[ "$SKIP_WINDOWS_LOCAL" = false ]]; then
      WINDOWS_MSIX="$REPO_ROOT/build/windows/x64/runner/Release/fermentacraft.msix"
      [[ -f "$WINDOWS_MSIX" ]] && {
        cp "$WINDOWS_MSIX" "$RELEASE_DIR/fermentacraft-$VERSION_TAG.msix"
        ARTIFACTS+=("$RELEASE_DIR/fermentacraft-$VERSION_TAG.msix")
      }
    fi

    if [[ "$SKIP_LINUX_LOCAL" = false ]]; then
      LINUX_BUNDLE="$REPO_ROOT/build/linux/x64/release/bundle"
      if [[ -d "$LINUX_BUNDLE" ]]; then
        LINUX_ARCHIVE="$REPO_ROOT/release-artifacts/fermentacraft-$VERSION_TAG-linux.tar.gz"
        tar -czf "$LINUX_ARCHIVE" -C "$LINUX_BUNDLE" .
        ARTIFACTS+=("$LINUX_ARCHIVE")
      fi
    fi

    cp "$CHANGELOG_PATH" "$RELEASE_DIR/CHANGELOG-$VERSION_TAG.txt"

    if command_exists gh; then
      if gh release view "$VERSION_TAG" >/dev/null 2>&1; then
        warn "GitHub release $VERSION_TAG already exists. Skipping creation."
      else
        gh release create "$VERSION_TAG" \
          --title "Release $VERSION_TAG" \
          --notes-file "$CHANGELOG_PATH" \
          "${ARTIFACTS[@]}"
        success "GitHub release created"
      fi
    else
      warn "gh CLI not found. Create the GitHub release manually."
    fi
  else
    info "[DRY RUN] Would create GitHub release for $VERSION_TAG"
  fi
else
  info "Skipping GitHub release"
fi

if [[ "$SKIP_IOS_CI" = false ]]; then
  step "Triggering iOS workflow"
  if ! $DRY_RUN; then
    if command_exists gh; then
      gh workflow run ios-release.yml --field release-channel="$VERSION_TAG" --field build-number="$NEW_BUILD"
      success "Triggered ios-release.yml"
    else
      warn "gh CLI not found. Trigger iOS workflow manually."
    fi
  else
    info "[DRY RUN] Would trigger ios-release.yml with release-channel=$VERSION_TAG build-number=$NEW_BUILD"
  fi
else
  info "Skipping iOS workflow trigger"
fi

if [[ "$SKIP_WINDOWS_CI" = false ]]; then
  step "Triggering Windows workflow"
  if ! $DRY_RUN; then
    if command_exists gh; then
      gh workflow run windows-release.yml --field release-channel="$VERSION_TAG"
      success "Triggered windows-release.yml"
    else
      warn "gh CLI not found. Trigger Windows workflow manually."
    fi
  else
    info "[DRY RUN] Would trigger windows-release.yml with release-channel=$VERSION_TAG"
  fi
else
  info "Skipping Windows workflow trigger"
fi

if [[ "$SKIP_LINUX_CI" = false ]]; then
  step "Triggering Linux workflow"
  if ! $DRY_RUN; then
    if command_exists gh; then
      gh workflow run linux-release.yml --field release-channel="$VERSION_TAG"
      success "Triggered linux-release.yml"
    else
      warn "gh CLI not found. Trigger Linux workflow manually."
    fi
  else
    info "[DRY RUN] Would trigger linux-release.yml with release-channel=$VERSION_TAG"
  fi
else
  info "Skipping Linux workflow trigger"
fi

step "Release complete"

echo -e "${GREEN}Release Summary${NC}"
echo -e "${GREEN}===============${NC}"
echo "Version: $NEW_FULL_VERSION"
echo "Tag:     $VERSION_TAG"
echo

echo "Built artifacts:"
[[ "$SKIP_ANDROID" = false ]] && echo "  ✓ Android App Bundle and split APKs"
[[ "$SKIP_WINDOWS_LOCAL" = false ]] && echo "  ✓ Windows EXE / MSIX"
[[ "$SKIP_LINUX_LOCAL" = false ]] && echo "  ✓ Linux bundle"
echo

echo "Next steps:"
echo "  1. Verify GitHub Actions runs"
echo "  2. Upload Android .aab to Google Play Console"
echo "  3. Verify GitHub release and artifacts"

if [[ -n "$REPO_SLUG" ]]; then
  echo "  4. Review releases: https://github.com/$REPO_SLUG/releases"
  echo "  5. Review actions:  https://github.com/$REPO_SLUG/actions"
fi

$DRY_RUN && echo && echo "⚠ DRY RUN MODE - no git or publishing changes were made"