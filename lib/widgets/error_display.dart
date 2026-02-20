// lib/widgets/error_display.dart
// Copyright 2024 Brian Henson
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import '../core/errors.dart';

/// Display error messages to users with helpful context
class ErrorDisplay extends StatelessWidget {
  final Object? error;
  final String? title;
  final VoidCallback? onRetry;
  final bool showDetails;

  const ErrorDisplay({
    super.key,
    this.error,
    this.title,
    this.onRetry,
    this.showDetails = false,
  });

  String _getUserMessage() {
    if (error is AppException) {
      return (error as AppException).userMessage;
    }

    if (error is FormatException) {
      return 'Invalid data format. Please try again.';
    }

    if (error is TimeoutException) {
      return 'Request timed out. Please check your connection.';
    }

    return 'An unexpected error occurred. Please try again.';
  }

  String? _getErrorDetails() {
    if (!showDetails) return null;
    return error.toString();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final message = _getUserMessage();
    final details = _getErrorDetails();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Card(
        color: colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.error_outline,
                    color: colorScheme.error,
                    size: 32,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (title != null)
                          Text(
                            title!,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(color: colorScheme.onErrorContainer),
                          ),
                        Text(
                          message,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: colorScheme.onErrorContainer),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (details != null && details.isNotEmpty) ...[
                const SizedBox(height: 12),
                ExpansionTile(
                  title: const Text('Details'),
                  children: [
                    SelectableText(
                      details,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
              if (onRetry != null) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonal(
                    onPressed: onRetry,
                    child: const Text('Retry'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Show error snackbar
void showErrorSnackBar(
  BuildContext context,
  Object? error, {
  String? title,
  Duration duration = const Duration(seconds: 4),
}) {
  final message = (error is AppException)
      ? error.userMessage
      : 'An error occurred. Please try again.';

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      duration: duration,
      action: SnackBarAction(
        label: 'Dismiss',
        onPressed: () {},
      ),
    ),
  );
}

/// Dialog for detailed error information
Future<void> showErrorDialog(
  BuildContext context,
  Object? error, {
  String? title,
  VoidCallback? onRetry,
}) {
  return showDialog(
    context: context,
    builder: (context) => AlertDialog(
      icon: Icon(
        Icons.error_outline,
        color: Theme.of(context).colorScheme.error,
      ),
      title: Text(title ?? 'Error'),
      content: ErrorDisplay(
        error: error,
        showDetails: true,
      ),
      actions: [
        if (onRetry != null)
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              onRetry();
            },
            child: const Text('Retry'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
