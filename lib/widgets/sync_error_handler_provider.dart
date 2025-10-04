/// Widget that provides sync error handling context to the error handler
/// Should wrap major navigation areas to ensure error dialogs can be shown
library;

import 'package:flutter/material.dart';
import 'package:fermentacraft/services/firestore_sync_service.dart';

class SyncErrorHandlerProvider extends StatefulWidget {
  const SyncErrorHandlerProvider({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  State<SyncErrorHandlerProvider> createState() => _SyncErrorHandlerProviderState();
}

class _SyncErrorHandlerProviderState extends State<SyncErrorHandlerProvider> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Update the error handler with current context whenever dependencies change
    if (mounted) {
      FirestoreSyncService.instance.updateErrorHandlingContext(context);
    }
  }

  @override
  void dispose() {
    // Clear the context when this widget is disposed
    FirestoreSyncService.instance.updateErrorHandlingContext(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}