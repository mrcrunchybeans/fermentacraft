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

# Function to find and patch all Swift files with a specific import pattern
find_and_patch_all() {
  local base_dir="$1"
  local pattern="$2"
  local replacement="$3"
  local description="$4"
  
  log_message "🔍 Searching for all files with $pattern in $base_dir..."
  
  # Find all Swift files that contain the pattern
  local files=$(grep -l "$pattern" "$base_dir"/*.swift "$base_dir"/*/*.swift "$base_dir"/*/*/*.swift "$base_dir"/*/*/*/*.swift 2>/dev/null || echo "")
  
  if [ -z "$files" ]; then
    log_message "ℹ️ No files found containing '$pattern'"
    return 0
  fi
  
  log_message "🔍 Found $(echo "$files" | wc -w | xargs) files with '$pattern'"
  
  # Loop through each file and apply the patch
  local success=true
  for file in $files; do
    if ! patch_file "$file" "$pattern" "$replacement" "$description in $(basename "$file")"; then
      success=false
      log_message "⚠️ Failed to patch $file"
    fi
  done
  
  if [ "$success" = true ]; then
    log_message "✅ Successfully patched all files containing '$pattern'"
    return 0
  else
    log_message "⚠️ Some files with '$pattern' could not be patched"
    return 1
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
AUTH_APNS_FILE="ios/Pods/FirebaseAuth/FirebaseAuth/Sources/Swift/SystemService/AuthAPNSTokenManager.swift"
AUTH_BACKEND_RPC_FILE="ios/Pods/FirebaseAuth/FirebaseAuth/Sources/Swift/Backend/AuthBackendRPCIssuer.swift"

# Array of specific file patches to apply - format: [file, old_import, new_import, description]
declare -a SPECIFIC_PATCHES=(
  "$FUNCTIONS_FILE|import GTMSessionFetcherCore|import GTMSessionFetcher|GTMSessionFetcherCore in FirebaseFunctions"
  "$AUTH_FILE|import GoogleUtilities_AppDelegateSwizzler|import GoogleUtilities|GoogleUtilities_AppDelegateSwizzler in Auth.swift"
  "$AUTH_FILE|import GoogleUtilities_Environment|import GoogleUtilities|GoogleUtilities_Environment in Auth.swift"
  "$AUTH_BACKEND_FILE|import GTMSessionFetcherCore|import GTMSessionFetcher|GTMSessionFetcherCore in AuthBackend.swift"
  "$AUTH_APNS_FILE|import GoogleUtilities_Environment|import GoogleUtilities|GoogleUtilities_Environment in AuthAPNSTokenManager.swift"
  "$AUTH_BACKEND_RPC_FILE|@preconcurrency import GTMSessionFetcherCore|@preconcurrency import GTMSessionFetcher|@preconcurrency GTMSessionFetcherCore in AuthBackendRPCIssuer.swift"
)

# Apply all specific patches first
SUCCESS=true
for patch_info in "${SPECIFIC_PATCHES[@]}"; do
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

# Now search for any other instances of problematic imports in the Firebase directories
log_message "🔍 Searching for any additional problematic imports in the entire Pods directory..."

# Firebase Pods directory
FIREBASE_DIR="ios/Pods"
if [ -d "$FIREBASE_DIR" ]; then
  # Search and patch all GTMSessionFetcherCore imports (both regular and @preconcurrency)
  find_and_patch_all "$FIREBASE_DIR" "import GTMSessionFetcherCore" "import GTMSessionFetcher" "GTMSessionFetcherCore import"
  find_and_patch_all "$FIREBASE_DIR" "@preconcurrency import GTMSessionFetcherCore" "@preconcurrency import GTMSessionFetcher" "@preconcurrency GTMSessionFetcherCore import"
  
  # Search and patch all GoogleUtilities_AppDelegateSwizzler imports (both regular and @preconcurrency)
  find_and_patch_all "$FIREBASE_DIR" "import GoogleUtilities_AppDelegateSwizzler" "import GoogleUtilities" "GoogleUtilities_AppDelegateSwizzler import"
  find_and_patch_all "$FIREBASE_DIR" "@preconcurrency import GoogleUtilities_AppDelegateSwizzler" "@preconcurrency import GoogleUtilities" "@preconcurrency GoogleUtilities_AppDelegateSwizzler import"
  
  # Search and patch all GoogleUtilities_Environment imports (both regular and @preconcurrency)
  find_and_patch_all "$FIREBASE_DIR" "import GoogleUtilities_Environment" "import GoogleUtilities" "GoogleUtilities_Environment import"
  find_and_patch_all "$FIREBASE_DIR" "@preconcurrency import GoogleUtilities_Environment" "@preconcurrency import GoogleUtilities" "@preconcurrency GoogleUtilities_Environment import"
  
  # Additional searches for any other known problematic imports
  find_and_patch_all "$FIREBASE_DIR" "import GoogleUtilities_Logger" "import GoogleUtilities" "GoogleUtilities_Logger import"
  find_and_patch_all "$FIREBASE_DIR" "@preconcurrency import GoogleUtilities_Logger" "@preconcurrency import GoogleUtilities" "@preconcurrency GoogleUtilities_Logger import"
  find_and_patch_all "$FIREBASE_DIR" "import GoogleUtilities_Network" "import GoogleUtilities" "GoogleUtilities_Network import"
  find_and_patch_all "$FIREBASE_DIR" "@preconcurrency import GoogleUtilities_Network" "@preconcurrency import GoogleUtilities" "@preconcurrency GoogleUtilities_Network import"
  find_and_patch_all "$FIREBASE_DIR" "import GoogleUtilities_Reachability" "import GoogleUtilities" "GoogleUtilities_Reachability import"
  find_and_patch_all "$FIREBASE_DIR" "@preconcurrency import GoogleUtilities_Reachability" "@preconcurrency import GoogleUtilities" "@preconcurrency GoogleUtilities_Reachability import"
  find_and_patch_all "$FIREBASE_DIR" "import GoogleUtilities_UserDefaults" "import GoogleUtilities" "GoogleUtilities_UserDefaults import"
  find_and_patch_all "$FIREBASE_DIR" "@preconcurrency import GoogleUtilities_UserDefaults" "@preconcurrency import GoogleUtilities" "@preconcurrency GoogleUtilities_UserDefaults import"
else
  log_message "⚠️ Firebase Pods directory not found at $FIREBASE_DIR"
fi

# Final verification
log_message "🔍 Final verification of patched files..."

# Function to verify imports (checks both regular and @preconcurrency imports)
verify_imports() {
  local file="$1"
  local bad_pattern="$2"
  local description="$3"
  
  if [ -f "$file" ]; then
    if grep -q "$bad_pattern" "$file" || grep -q "@preconcurrency $bad_pattern" "$file"; then
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
verify_imports "$AUTH_APNS_FILE" "GoogleUtilities_Environment" "GoogleUtilities_Environment import"
verify_imports "$AUTH_BACKEND_RPC_FILE" "GTMSessionFetcherCore" "GTMSessionFetcherCore import"

# Store current import states for reference
IMPORTS_FILE="${SCRIPT_DIR}/firebase_imports.txt"
echo "===== Firebase Import Statements After Patching =====" > "$IMPORTS_FILE"

for FILE in "$FUNCTIONS_FILE" "$AUTH_FILE" "$AUTH_BACKEND_FILE" "$AUTH_APNS_FILE" "$AUTH_BACKEND_RPC_FILE"; do
  if [ -f "$FILE" ]; then
    echo -e "\n--- $FILE ---" >> "$IMPORTS_FILE"
    grep "import " "$FILE" >> "$IMPORTS_FILE" 2>/dev/null || echo "No imports found" >> "$IMPORTS_FILE"
  fi
done

log_message "📄 Import statements saved to $IMPORTS_FILE"

# Search for any remaining problematic imports for reporting
REMAINING_GTM=$(find ios -name "*.swift" -type f \( -exec grep -l "import GTMSessionFetcherCore" {} \; -o -exec grep -l "@preconcurrency import GTMSessionFetcherCore" {} \; \) 2>/dev/null | sort | uniq || echo "")
REMAINING_GU=$(find ios -name "*.swift" -type f \( -exec grep -l "import GoogleUtilities_" {} \; -o -exec grep -l "@preconcurrency import GoogleUtilities_" {} \; \) 2>/dev/null | sort | uniq || echo "")

# Final status message
log_message "===== Firebase Import Fix Summary ====="
log_message "Checked specific files:"
for patch_info in "${SPECIFIC_PATCHES[@]}"; do
  IFS="|" read -r file old_import new_import description <<< "$patch_info"
  log_message " - $file"
done

log_message "Also searched entire Pods directory for problematic imports"

if [ -n "$REMAINING_GTM" ] || [ -n "$REMAINING_GU" ]; then
  SUCCESS=false
  log_message "⚠️ Found remaining problematic imports:"
  
  if [ -n "$REMAINING_GTM" ]; then
    log_message "Files still containing GTMSessionFetcherCore imports:"
    echo "$REMAINING_GTM" | while read -r file; do
      log_message " - $file"
    done
  fi
  
  if [ -n "$REMAINING_GU" ]; then
    log_message "Files still containing GoogleUtilities_ imports:"
    echo "$REMAINING_GU" | while read -r file; do
      log_message " - $file"
    done
  fi
fi

if [ "$SUCCESS" = true ]; then
  log_message "✅ Firebase import fixes completed successfully"
  exit 0
else
  log_message "⚠️ Some Firebase import fixes may have failed, check the log at $LOG_FILE"
  exit 1
fi