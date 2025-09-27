// lib/services/platform/platform_services.dart
/// iOS Platform Services Module
/// 
/// This module provides platform-specific implementations for iOS
/// that integrate with the repository pattern and service locator
/// architecture established in Sprint 2A.
/// 
/// Services included:
/// - IOSAuthService: iOS-specific Firebase Auth and Google Sign-in
/// - IOSFileService: iOS document handling and file operations
/// - IOSRevenueCatService: iOS App Store subscription management
/// - PlatformAdapter: Automatic platform-appropriate service selection

export 'ios_auth_service.dart';
export 'ios_file_service.dart';
export 'ios_revenuecat_service.dart';
export 'platform_adapter.dart';