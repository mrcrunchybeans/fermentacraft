// lib/services/review_prompter.dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

enum ReviewTrigger { firstBatchCompleted, tools3Days, measurements5 }

extension _Key on ReviewTrigger {
  String get key => switch (this) {
        ReviewTrigger.firstBatchCompleted => 'first_batch_completed',
        ReviewTrigger.tools3Days => 'tools_3_days',
        ReviewTrigger.measurements5 => 'measurements_5',
      };
}

class ReviewPrompter {
  ReviewPrompter._();
  static final ReviewPrompter instance = ReviewPrompter._();

  // Pref keys
  static const _kHasReviewed = 'rp_has_reviewed';
  static const _kOptedOut = 'rp_opted_out';
  static const _kConsumedTriggers = 'rp_consumed_triggers'; // List<String> of trigger keys
  static const _kToolsDays = 'rp_tools_days';               // List<String> yyyy-mm-dd
  static const _kMeasurementCount = 'rp_measurement_count'; // int

  Future<SharedPreferences> get _prefs async => SharedPreferences.getInstance();

  // ---- Public trigger entrypoints ----

  Future<void> fireFirstBatchCompleted(BuildContext context) =>
      _maybePrompt(context, ReviewTrigger.firstBatchCompleted);

  /// Call once per day when Tools page is visited/used.
  Future<void> fireToolsUsedToday(BuildContext context) async {
    final p = await _prefs;
    final now = DateTime.now();
    final keyDate =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final days = (p.getStringList(_kToolsDays) ?? <String>[]);
    if (!days.contains(keyDate)) {
      days.add(keyDate);
      await p.setStringList(_kToolsDays, days);
    }

    if (days.length >= 3) {
      // ✅ Don’t use context across the awaits above without guarding:
      if (!context.mounted) return;
      await _maybePrompt(context, ReviewTrigger.tools3Days);
    }
  }


  /// Call whenever a measurement is persisted.
  Future<void> fireMeasurementLogged(BuildContext context) async {
    final p = await _prefs;
    final next = (p.getInt(_kMeasurementCount) ?? 0) + 1;
    await p.setInt(_kMeasurementCount, next);

    if (next >= 6) {
      // ✅ Guard before using context after awaits above:
      if (!context.mounted) return;
      await _maybePrompt(context, ReviewTrigger.measurements5);
    }
  }

  /// Android-only manual entry point for Settings/About
  Future<void> openRateFromSettings() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    final ir = InAppReview.instance;
    await ir.openStoreListing();
  }

  // ---- Core logic ----

  Future<void> _maybePrompt(BuildContext context, ReviewTrigger trigger) async {
    final p = await _prefs;

    if (p.getBool(_kHasReviewed) == true) return;
    if (p.getBool(_kOptedOut) == true) return;

    final consumed = p.getStringList(_kConsumedTriggers) ?? <String>[];
    if (consumed.contains(trigger.key)) return; // never repeat the same trigger

    if (!context.mounted) return;
    final result = await _showSoftAsk(context, trigger);

    // Mark this trigger as "consumed" so we only ask once per trigger.
    final updated = {...consumed, trigger.key}.toList();
    await p.setStringList(_kConsumedTriggers, updated);

    switch (result) {
      case _SoftAskResult.yesReview:
        await _requestOSReview();               // OS handles quotas/cooldowns
        await p.setBool(_kHasReviewed, true);   // never ask again in-app
        break;
      case _SoftAskResult.notReallyFeedback:
        await _sendFeedbackEmail();
        break;
      case _SoftAskResult.notNow:
      case _SoftAskResult.dismissed:
        // Do nothing; we’ll wait for the next distinct trigger.
        break;
      case _SoftAskResult.noThanks:
        await p.setBool(_kOptedOut, true);      // opt out permanently
        break;
    }
  }

  Future<void> _requestOSReview() async {
    final ir = InAppReview.instance;
    final available = await ir.isAvailable();
    if (available) {
      await ir.requestReview();
    } else {
      await ir.openStoreListing();
    }
  }

  Future<void> _sendFeedbackEmail() async {
    final uri = Uri(
      scheme: 'mailto',
      path: 'developer@fermentacraft.com',
      queryParameters: {'subject': 'FermentaCraft feedback'},
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  // ---- UI ----

  Future<_SoftAskResult> _showSoftAsk(BuildContext context, ReviewTrigger t) async {
    final subtitle = switch (t) {
      ReviewTrigger.firstBatchCompleted =>
        'Congrats on completing your first batch! If FermentaCraft helped, a quick review really helps others find it.',
      ReviewTrigger.tools3Days =>
        'Looks like the Tools tab is useful—would you mind leaving a quick review?',
      ReviewTrigger.measurements5 =>
        'Thanks for logging your progress. If you’re finding value, a short review would be awesome.',
    };

    final res = await showModalBottomSheet<_SoftAskResult>(
      context: context,
      useSafeArea: true,
      isScrollControlled: false,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enjoying FermentaCraft?',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(subtitle, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(ctx).pop(_SoftAskResult.notNow),
                    child: const Text('Not now'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(ctx).pop(_SoftAskResult.yesReview),
                    child: const Text('Yes'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(_SoftAskResult.notReallyFeedback),
              child: const Text('Not really — send feedback'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(_SoftAskResult.noThanks),
              child: const Text('No thanks (don’t ask again)'),
            ),
          ],
        ),
      ),
    );

    return res ?? _SoftAskResult.dismissed;
  }
}

enum _SoftAskResult { yesReview, notReallyFeedback, notNow, noThanks, dismissed }
