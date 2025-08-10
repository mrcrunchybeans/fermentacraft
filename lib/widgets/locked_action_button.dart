// lib/widgets/locked_action_button.dart
import 'package:fermentacraft/widgets/show_paywall.dart';
import 'package:flutter/material.dart';
// adjust import if you place PaywallPage elsewhere

class LockedActionButton extends StatelessWidget {
  final bool allow;              // if false => soft lock
  final VoidCallback onAllowed;  // real action
  final String label;
  final IconData icon;
  final String reason;

  const LockedActionButton({
    super.key,
    required this.allow,
    required this.onAllowed,
    required this.label,
    required this.icon,
    required this.reason,
  });

  void _upsell(BuildContext context) {

showPaywall(context);

  }

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: allow ? onAllowed : () => _upsell(context),
      icon: Icon(allow ? icon : Icons.lock),
      label: Text(label),
    );
  }
}
