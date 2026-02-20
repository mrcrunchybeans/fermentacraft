// lib/services/review_prompter.dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

enum ReviewTrigger {
  firstBatchCompleted,
  tools3Days,
  measurements5,
  recipeShared,
  syncSuccess,
  calculatorUsed,
}

extension _Key on ReviewTrigger {
  String get key => switch (this) {
        ReviewTrigger.firstBatchCompleted => 'first_batch_completed',
        ReviewTrigger.tools3Days => 'tools_3_days',
        ReviewTrigger.measurements5 => 'measurements_5',
        ReviewTrigger.recipeShared => 'recipe_shared',
        ReviewTrigger.syncSuccess => 'sync_success',
        ReviewTrigger.calculatorUsed => 'calculator_used',
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
  static const _kLastPromptDate = 'rp_last_prompt_date';   // ISO8601 string

  /// Minimum days between any review prompts (cooldown)
  static const int _cooldownDays = 30;

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

  /// Call when a recipe is shared externally
  Future<void> fireRecipeShared(BuildContext context) =>
      _maybePrompt(context, ReviewTrigger.recipeShared);

  /// Call when data syncs successfully
  Future<void> fireSyncSuccess(BuildContext context) =>
      _maybePrompt(context, ReviewTrigger.syncSuccess);

  /// Call when a calculator tool is used
  Future<void> fireCalculatorUsed(BuildContext context) =>
      _maybePrompt(context, ReviewTrigger.calculatorUsed);

  /// Store IDs for direct links
  static const _iosAppId = '6477420432'; // FermentaCraft iOS App Store ID
  static const _androidPackage = 'com.fermentacraft';

  /// Open store review page - works on both iOS and Android
  Future<void> openStoreReview() async {
    if (kIsWeb) return;

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      // Open App Store review page
      final uri = Uri.parse('https://apps.apple.com/app/id$_iosAppId?action=write-review');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      // Open Play Store review page
      final ir = InAppReview.instance;
      await ir.openStoreListing();
    }
  }

  /// Open feedback email
  Future<void> sendFeedback() async {
    final uri = Uri(
      scheme: 'mailto',
      path: 'developer@fermentacraft.com',
      queryParameters: {'subject': 'FermentaCraft feedback'},
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  // ---- Core logic ----

  Future<void> _maybePrompt(BuildContext context, ReviewTrigger trigger) async {
    final p = await _prefs;

    if (p.getBool(_kHasReviewed) == true) return;
    if (p.getBool(_kOptedOut) == true) return;

    // Check global cooldown - don't prompt if within 30 days of last prompt
    final lastPromptStr = p.getString(_kLastPromptDate);
    if (lastPromptStr != null) {
      final lastPrompt = DateTime.tryParse(lastPromptStr);
      if (lastPrompt != null) {
        final daysSinceLastPrompt = DateTime.now().difference(lastPrompt).inDays;
        if (daysSinceLastPrompt < _cooldownDays) return;
      }
    }

    final consumed = p.getStringList(_kConsumedTriggers) ?? <String>[];
    if (consumed.contains(trigger.key)) return; // never repeat the same trigger

    if (!context.mounted) return;
    final result = await _showSoftAsk(context, trigger);

    // Mark this trigger as "consumed" so we only ask once per trigger.
    final updated = {...consumed, trigger.key}.toList();
    await p.setStringList(_kConsumedTriggers, updated);

    // Update last prompt date
    await p.setString(_kLastPromptDate, DateTime.now().toIso8601String());

    switch (result) {
      case _SoftAskResult.yesReview:
        await _requestOSReview();               // OS handles quotas/cooldowns
        await p.setBool(_kHasReviewed, true);   // never ask again in-app
        break;
      case _SoftAskResult.notReallyFeedback:
        if (context.mounted) await _showFeedbackForm(context);
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

  /// Show in-app feedback form (replaces email)
  Future<void> _showFeedbackForm(BuildContext context) async {
    int? rating; // 1 = thumbs down, 2 = thumbs up
    final controller = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Send Feedback'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Was this helpful?'),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: () => setState(() => rating = 1),
                    icon: Icon(
                      Icons.thumb_down,
                      color: rating == 1 ? Colors.red : Colors.grey,
                    ),
                  ),
                  IconButton(
                    onPressed: () => setState(() => rating = 2),
                    icon: Icon(
                      Icons.thumb_up,
                      color: rating == 2 ? Colors.green : Colors.grey,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Tell us more (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: rating != null
                  ? () => Navigator.pop(ctx, true)
                  : null,
              child: const Text('Send'),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      // In production, you would send this to Firebase Firestore
      // For now, just log it (could add Firebase collection later)
      debugPrint('Feedback submitted: rating=$rating, comment=${controller.text}');

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Thanks for your feedback!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
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
        'Thanks for logging your progress. If you\'re finding value, a short review would be awesome.',
      ReviewTrigger.recipeShared =>
        'Thanks for sharing a recipe! If you enjoy using FermentaCraft, a quick review helps others find it.',
      ReviewTrigger.syncSuccess =>
        'Your data synced successfully! If FermentaCraft is working well for you, a quick review would be appreciated.',
      ReviewTrigger.calculatorUsed =>
        'Thanks for using the calculator! If FermentaCraft is helpful, a quick review would be great.',
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
