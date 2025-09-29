#!/bin/bash
# fix_firebase_ios.sh
# Script to fix Firebase import issues when developing on macOS
# Run this after flutter clean and pod install

set -uo pipefail
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

echo "🔄 Running Flutter pub get..."
flutter pub get

echo "🔄 Installing pods..."
cd ios
pod install

# Reuse the unified fix script if it exists
if [ -f "$SCRIPT_DIR/scripts/firebase_imports_fix.sh" ]; then
  echo "🔧 Running unified Firebase import fix script..."
  cd "$SCRIPT_DIR"
  bash "$SCRIPT_DIR/scripts/firebase_imports_fix.sh"
  exit $?
fi

# Fallback to direct patching if the script doesn't exist
echo "🔧 Applying Firebase import fixes manually..."
cd "$SCRIPT_DIR/ios"

# Fix Functions.swift
FUNCTIONS_FILE="Pods/FirebaseFunctions/FirebaseFunctions/Sources/Functions.swift"
if [ -f "$FUNCTIONS_FILE" ]; then
  if grep -q "import GTMSessionFetcherCore" "$FUNCTIONS_FILE"; then
    echo "📝 Patching $FUNCTIONS_FILE..."
    sed -i '' 's/import GTMSessionFetcherCore/import GTMSessionFetcher/g' "$FUNCTIONS_FILE"
    echo "✅ $FUNCTIONS_FILE patched"
  else
    echo "✅ $FUNCTIONS_FILE already patched or doesn't need patching"
  fi
else
  echo "⚠️ $FUNCTIONS_FILE not found"
fi

# Fix Auth.swift
AUTH_FILE="Pods/FirebaseAuth/FirebaseAuth/Sources/Swift/Auth/Auth.swift"
if [ -f "$AUTH_FILE" ]; then
  NEEDS_PATCH=0
  
  if grep -q "import GoogleUtilities_AppDelegateSwizzler" "$AUTH_FILE"; then
    echo "📝 Patching GoogleUtilities_AppDelegateSwizzler in $AUTH_FILE..."
    sed -i '' 's/import GoogleUtilities_AppDelegateSwizzler/import GoogleUtilities/g' "$AUTH_FILE"
    NEEDS_PATCH=1
  fi
  
  if grep -q "import GoogleUtilities_Environment" "$AUTH_FILE"; then
    echo "📝 Patching GoogleUtilities_Environment in $AUTH_FILE..."
    sed -i '' 's/import GoogleUtilities_Environment/import GoogleUtilities/g' "$AUTH_FILE"
    NEEDS_PATCH=1
  fi
  
  if [ $NEEDS_PATCH -eq 1 ]; then
    echo "✅ $AUTH_FILE patched"
  else
    echo "✅ $AUTH_FILE already patched or doesn't need patching"
  fi
else
  echo "⚠️ $AUTH_FILE not found"
fi

# Fix AuthBackend.swift
AUTH_BACKEND_FILE="Pods/FirebaseAuth/FirebaseAuth/Sources/Swift/Backend/AuthBackend.swift"
if [ -f "$AUTH_BACKEND_FILE" ]; then
  if grep -q "import GTMSessionFetcherCore" "$AUTH_BACKEND_FILE"; then
    echo "📝 Patching $AUTH_BACKEND_FILE..."
    sed -i '' 's/import GTMSessionFetcherCore/import GTMSessionFetcher/g' "$AUTH_BACKEND_FILE"
    echo "✅ $AUTH_BACKEND_FILE patched"
  else
    echo "✅ $AUTH_BACKEND_FILE already patched or doesn't need patching"
  fi
else
  echo "⚠️ $AUTH_BACKEND_FILE not found"
fi

echo "✅ All Firebase import fixes applied"

# Return to project root
cd "$SCRIPT_DIR"
echo "🚀 Ready to build for iOS!"