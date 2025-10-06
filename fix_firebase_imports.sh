#!/bin/bash

echo "Fixing Firebase module import issues..."

# Navigate to iOS directory
cd /Users/user287021/cider-craft/ios

# Fix GoogleUtilities imports
find Pods -name "*.swift" -exec sed -i '' 's/import GoogleUtilities_AppDelegateSwizzler/import GoogleUtilities/g' {} \;
find Pods -name "*.swift" -exec sed -i '' 's/import GoogleUtilities_Environment/import GoogleUtilities/g' {} \;
find Pods -name "*.swift" -exec sed -i '' 's/internal import GoogleUtilities_AppDelegateSwizzler/internal import GoogleUtilities/g' {} \;
find Pods -name "*.swift" -exec sed -i '' 's/internal import GoogleUtilities_Environment/internal import GoogleUtilities/g' {} \;

# Fix GTMSessionFetcher imports
find Pods -name "*.swift" -exec sed -i '' 's/import GTMSessionFetcherCore/import GTMSessionFetcher/g' {} \;

echo "Firebase module imports have been fixed!"