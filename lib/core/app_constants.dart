// Copyright 2024 Brian Henson
// SPDX-License-Identifier: AGPL-3.0-or-later

/// Application-wide constants
/// 
/// This file centralizes all magic numbers and hardcoded values
/// to improve maintainability and make values easier to adjust.
library;

class AppConstants {
  // Private constructor to prevent instantiation
  AppConstants._();
  
  // ============================================================================
  // Timing Constants
  // ============================================================================
  
  /// Debounce delay for search input (milliseconds)
  static const searchDebounceMs = 300;
  
  /// Debounce delay for general input fields (milliseconds)
  static const inputDebounceMs = 400;
  
  /// Auto-save delay after changes (milliseconds)
  static const autoSaveDelayMs = 1000;
  
  /// Default animation duration (milliseconds)
  static const defaultAnimationDurationMs = 200;
  
  /// Loading indicator delay before showing (milliseconds)
  static const loadingIndicatorDelayMs = 250;
  
  /// Toast/Snackbar display duration (milliseconds)
  static const snackbarDurationMs = 3000;
  
  /// Error message display duration (milliseconds)
  static const errorMessageDurationMs = 5000;
  
  // ============================================================================
  // Memory & Performance
  // ============================================================================
  
  /// Memory warning threshold (megabytes)
  static const memoryWarningThresholdMB = 450.0;
  
  /// Critical memory threshold (megabytes)
  static const memoryCriticalThresholdMB = 500.0;
  
  /// Maximum cached images
  static const maxCachedImages = 50;
  
  /// Maximum chart data points (before aggregation)
  static const maxChartDataPoints = 1000;
  
  /// Chart aggregation bucket limit
  static const chartAggregationBuckets = 150;
  
  /// Maximum points to show dots on chart
  static const chartDotsVisibilityThreshold = 50;
  
  // ============================================================================
  // Pagination & Lists
  // ============================================================================
  
  /// Default page size for paginated lists
  static const defaultPageSize = 20;
  
  /// Maximum search results to show
  static const maxSearchResults = 100;
  
  /// Batch list page size
  static const batchListPageSize = 25;
  
  /// Recipe list page size
  static const recipeListPageSize = 30;
  
  // ============================================================================
  // Validation Limits
  // ============================================================================
  
  /// Minimum password length
  static const minPasswordLength = 8;
  
  /// Maximum batch name length
  static const maxBatchNameLength = 100;
  
  /// Maximum recipe name length
  static const maxRecipeNameLength = 100;
  
  /// Maximum notes length
  static const maxNotesLength = 5000;
  
  /// Minimum valid specific gravity
  static const minSpecificGravity = 0.950;
  
  /// Maximum valid specific gravity
  static const maxSpecificGravity = 1.200;
  
  /// Minimum valid Brix
  static const minBrix = 0.0;
  
  /// Maximum valid Brix
  static const maxBrix = 50.0;
  
  /// Minimum valid brewing temperature (Celsius)
  static const minBrewingTempC = -5.0;
  
  /// Maximum valid brewing temperature (Celsius)
  static const maxBrewingTempC = 100.0;
  
  /// Minimum valid fermentation temperature (Celsius)
  static const minFermentationTempC = 0.0;
  
  /// Maximum valid fermentation temperature (Celsius)
  static const maxFermentationTempC = 40.0;
  
  // ============================================================================
  // UI Dimensions
  // ============================================================================
  
  /// Standard padding (pixels)
  static const standardPadding = 16.0;
  
  /// Small padding (pixels)
  static const smallPadding = 8.0;
  
  /// Large padding (pixels)
  static const largePadding = 24.0;
  
  /// Card elevation
  static const cardElevation = 2.0;
  
  /// Dialog max width (pixels)
  static const dialogMaxWidth = 600.0;
  
  /// Bottom sheet max height ratio
  static const bottomSheetMaxHeightRatio = 0.9;
  
  /// Minimum tap target size (pixels, for accessibility)
  static const minTapTargetSize = 48.0;
  
  // ============================================================================
  // Chart Settings
  // ============================================================================
  
  /// Default chart height (pixels)
  static const defaultChartHeight = 320.0;
  
  /// Chart line width (pixels)
  static const chartLineWidth = 2.5;
  
  /// Chart dot radius (pixels)
  static const chartDotRadius = 3.0;
  
  /// Chart axis font size (pixels)
  static const chartAxisFontSize = 10.0;
  
  /// Chart legend font size (pixels)
  static const chartLegendFontSize = 13.0;
  
  // ============================================================================
  // Fermentation Constants
  // ============================================================================
  
  /// Points threshold for "fermentation active" (pt/day)
  static const fermentationActiveThreshold = 1.0;
  
  /// Points threshold for "fermentation slowing" (pt/day)
  static const fermentationSlowingThreshold = 0.5;
  
  /// Points threshold for "fermentation complete" (pt/day)
  static const fermentationCompleteThreshold = 0.1;
  
  /// Days to consider fermentation stuck if no change
  static const fermentationStuckDays = 3;
  
  // ============================================================================
  // Sync & Network
  // ============================================================================
  
  /// Network request timeout (seconds)
  static const networkTimeoutSeconds = 30;
  
  /// Retry attempts for failed network requests
  static const maxNetworkRetries = 3;
  
  /// Delay between retry attempts (milliseconds)
  static const retryDelayMs = 1000;
  
  /// Batch size for Firestore sync
  static const firestoreSyncBatchSize = 50;
  
  /// Maximum age of cached data (hours)
  static const maxCacheAgeHours = 24;
  
  // ============================================================================
  // File Operations
  // ============================================================================
  
  /// Maximum file upload size (megabytes)
  static const maxFileUploadSizeMB = 10.0;
  
  /// Maximum image dimension (pixels)
  static const maxImageDimension = 2048;
  
  /// Image compression quality (0-100)
  static const imageCompressionQuality = 85;
  
  // ============================================================================
  // Feature Flags
  // ============================================================================
  
  /// Enable experimental features in debug mode
  static const enableExperimentalFeatures = true;
  
  /// Enable verbose logging
  static const enableVerboseLogging = false;
  
  /// Enable performance monitoring
  static const enablePerformanceMonitoring = true;
  
  // ============================================================================
  // Subscription & Premium
  // ============================================================================
  
  /// Maximum batches for free tier
  static const freeTierMaxBatches = 5;
  
  /// Maximum recipes for free tier
  static const freeTierMaxRecipes = 10;
  
  /// Trial period duration (days)
  static const trialPeriodDays = 7;
  
  // ============================================================================
  // Data Retention
  // ============================================================================
  
  /// Days to keep completed batches before archiving
  static const batchArchiveAfterDays = 365;
  
  /// Days to keep old measurements for inactive batches
  static const measurementRetentionDays = 180;
  
  /// Maximum undo history entries
  static const maxUndoHistorySize = 20;
}
