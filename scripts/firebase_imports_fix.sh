#!/bin/bash
# firebase_imports_fix.sh
# Script to fix import issues in Firebase Swift files
# For use with Flutter iOS builds in CI environments

# Set up error handling and logging
set -uo pipefail
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LOG_FILE="${SCRIPT_DIR}/firebase_patch_$(date +%s).log"

echo "Firebase import fix script started - $(date)" > "$LOG_FILE"

# Function to log messages to both console and log file
log_message() {
  echo "$1" | tee -a "$LOG_FILE"
}

# Function to patch a file with find/replace
patch_file() {
  local file="$1"
  local pattern="$2" 
  local replacement="$3"
  local description="$4"
  
  if [ ! -f "$file" ]; then
    log_message "⚠️ File not found: $file"
    return 1
  fi
  
  # Make sure the file is writable
  chmod +rw "$file" 2>> "$LOG_FILE" || {
    log_message "⚠️ Could not make file writable, trying with sudo..."
    sudo chmod +rw "$file" 2>> "$LOG_FILE" || {
      log_message "❌ Failed to set write permissions on $file"
      return 1
    }
  }
  
  if grep -q "$pattern" "$file"; then
    log_message "📝 Patching $file to fix $description"
    
    if sed -i '' "s/$pattern/$replacement/g" "$file" 2>> "$LOG_FILE"; then
      log_message "✅ Successfully patched $file"
      
      # Verify the patch worked
      if grep -q "$pattern" "$file"; then
        log_message "❌ ERROR: Failed to patch $file - $pattern still exists"
        return 1
      else
        log_message "✅ Verified patch was successfully applied to $file"
        return 0
      fi
    else
      log_message "⚠️ Sed command failed for $file"
      return 1
    fi
  else
    log_message "✅ $file already patched or doesn't need patching for $pattern"
    return 0
  fi
}

# Main execution
log_message "🔍 Checking iOS directory structure..."

# Check if we're running in the right place
if [ ! -d "ios" ]; then
  log_message "❌ Error: This script must be run from the Flutter project root directory (with ios/ subdirectory)"
  exit 1
fi

# Check if Pods directory exists
if [ ! -d "ios/Pods" ]; then
  log_message "⚠️ Warning: Pods directory not found. Running pod install..."
  (cd ios && pod install) >> "$LOG_FILE" 2>&1
  
  if [ ! -d "ios/Pods" ]; then
    log_message "❌ Error: Failed to create Pods directory. Check CocoaPods installation"
    exit 1
  fi
fi

# Define the files we need to check
FUNCTIONS_FILE="ios/Pods/FirebaseFunctions/FirebaseFunctions/Sources/Functions.swift"
AUTH_FILE="ios/Pods/FirebaseAuth/FirebaseAuth/Sources/Swift/Auth/Auth.swift"
AUTH_BACKEND_FILE="ios/Pods/FirebaseAuth/FirebaseAuth/Sources/Swift/Backend/AuthBackend.swift"

# Array of patches to apply - format: [file, old_import, new_import, description]
declare -a PATCHES=(
  "$FUNCTIONS_FILE|import GTMSessionFetcherCore|import GTMSessionFetcher|GTMSessionFetcherCore in FirebaseFunctions"
  "$AUTH_FILE|import GoogleUtilities_AppDelegateSwizzler|import GoogleUtilities|GoogleUtilities_AppDelegateSwizzler in Auth.swift"
  "$AUTH_FILE|import GoogleUtilities_Environment|import GoogleUtilities|GoogleUtilities_Environment in Auth.swift"
  "$AUTH_BACKEND_FILE|import GTMSessionFetcherCore|import GTMSessionFetcher|GTMSessionFetcherCore in AuthBackend.swift"
)

# Apply all patches
SUCCESS=true
for patch_info in "${PATCHES[@]}"; do
  IFS="|" read -r file old_import new_import description <<< "$patch_info"
  
  if [ -f "$file" ]; then
    log_message "🔍 Checking $file for $description..."
    if ! patch_file "$file" "$old_import" "$new_import" "$description"; then
      SUCCESS=false
      log_message "⚠️ Failed to apply patch for $description"
    fi
  else
    log_message "⚠️ File not found: $file"
    # Try to find similar files
    base_file=$(basename "$file")
    log_message "🔍 Looking for similar files to $base_file..."
    similar_files=$(find ios -name "$base_file" 2>/dev/null || echo "")
    if [ -n "$similar_files" ]; then
      log_message "Found potential matches:"
      log_message "$similar_files"
    else
      log_message "No similar files found"
    fi
  fi
done

# Final verification
log_message "🔍 Final verification of patched files..."

# Function to verify imports
verify_imports() {
  local file="$1"
  local bad_pattern="$2"
  local description="$3"
  
  if [ -f "$file" ]; then
    if grep -q "$bad_pattern" "$file"; then
      log_message "❌ ERROR: $description still present in $file"
      SUCCESS=false
    else
      log_message "✅ $description successfully fixed in $file"
    fi
  fi
}

# Verify all patches
verify_imports "$FUNCTIONS_FILE" "GTMSessionFetcherCore" "GTMSessionFetcherCore import"
verify_imports "$AUTH_FILE" "GoogleUtilities_" "GoogleUtilities_ imports"
verify_imports "$AUTH_BACKEND_FILE" "GTMSessionFetcherCore" "GTMSessionFetcherCore import"

# Store current import states for reference
IMPORTS_FILE="${SCRIPT_DIR}/firebase_imports.txt"
echo "===== Firebase Import Statements After Patching =====" > "$IMPORTS_FILE"

for FILE in "$FUNCTIONS_FILE" "$AUTH_FILE" "$AUTH_BACKEND_FILE"; do
  if [ -f "$FILE" ]; then
    echo -e "\n--- $FILE ---" >> "$IMPORTS_FILE"
    grep "import " "$FILE" >> "$IMPORTS_FILE" 2>/dev/null || echo "No imports found" >> "$IMPORTS_FILE"
  fi
done

log_message "📄 Import statements saved to $IMPORTS_FILE"

# Final status message
if [ "$SUCCESS" = true ]; then
  log_message "✅ Firebase import fixes completed successfully"
  exit 0
else
  log_message "⚠️ Some Firebase import fixes may have failed, check the log at $LOG_FILE"
  exit 1
fi