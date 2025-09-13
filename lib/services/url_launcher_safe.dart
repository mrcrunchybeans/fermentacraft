// lib/services/url_launcher_safe.dart
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

class UrlLauncherSafe {
  UrlLauncherSafe._();
  static final instance = UrlLauncherSafe._();

  Future<bool> openExternal(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        // Prefer external app first
        if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          return true;
        }
        // Fallback to in-app browser
        if (await launchUrl(uri, mode: LaunchMode.inAppBrowserView)) {
          return true;
        }
      }
    } catch (e) {
      debugPrint('UrlLauncherSafe failed for "$url": $e');
    }
    return false;
  }
}
