/// Debug widget for testing and monitoring sync error handling
/// Shows circuit breaker status, health metrics, and allows manual error testing
library;

import 'package:flutter/material.dart';
import 'package:fermentacraft/services/firestore_sync_service.dart';
import 'package:fermentacraft/utils/sync_error_handler.dart';

class SyncHealthDashboard extends StatefulWidget {
  const SyncHealthDashboard({super.key});

  @override
  State<SyncHealthDashboard> createState() => _SyncHealthDashboardState();
}

class _SyncHealthDashboardState extends State<SyncHealthDashboard> {
  Map<String, dynamic> _healthStatus = {};
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _refreshHealthStatus();
  }

  void _refreshHealthStatus() {
    setState(() {
      _refreshing = true;
      _healthStatus = FirestoreSyncService.instance.getSyncHealthStatus();
      _refreshing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sync Health Dashboard'),
        actions: [
          IconButton(
            onPressed: _refreshing ? null : _refreshHealthStatus,
            icon: _refreshing 
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Overall Sync Status
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sync Status',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildSyncStatusSummary(cs),
                  const Divider(height: 20),
                  _buildStatusRow(
                    'Overall Status', 
                    _healthStatus['can_sync'] ?? false,
                    cs,
                    subtitle: _healthStatus['effective_sync_status'] ?? 'Unknown',
                  ),
                  _buildStatusRow(
                    'User Enabled', 
                    _healthStatus['enabled'] ?? false,
                    cs,
                  ),
                  _buildStatusRow(
                    'Signed In', 
                    _healthStatus['signed_in'] ?? false,
                    cs,
                  ),
                  _buildStatusRow(
                    'Plan Includes Sync', 
                    _healthStatus['plan_allows_sync'] ?? false,
                    cs,
                    subtitle: _healthStatus['current_plan'] ?? 'Unknown',
                  ),
                  _buildStatusRow(
                    'Local Mode', 
                    _healthStatus['is_local_mode'] ?? false,
                    cs,
                    inverted: true, // Local mode ON means sync is blocked
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Circuit Breaker Status
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Circuit Breakers',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildCircuitBreakerStatus(cs),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Manual Error Testing
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Error Testing',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Test different error scenarios to validate user feedback:',
                    style: TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildTestButton(
                        'Network Error',
                        () => _testErrorSafely(SyncErrorCategory.network),
                        cs.primary,
                      ),
                      const SizedBox(height: 8),
                      _buildTestButton(
                        'Auth Error',
                        () => _testErrorSafely(SyncErrorCategory.authentication),
                        cs.error,
                      ),
                      const SizedBox(height: 8),
                      _buildTestButton(
                        'Storage Error',
                        () => _testErrorSafely(SyncErrorCategory.localStorage),
                        cs.error,
                      ),
                      const SizedBox(height: 8),
                      _buildTestButton(
                        'Data Error',
                        () => _testErrorSafely(SyncErrorCategory.dataIntegrity),
                        cs.tertiary,
                      ),
                      const SizedBox(height: 8),
                      _buildTestButton(
                        'Circuit Breaker',
                        () => _testErrorSafely(SyncErrorCategory.circuitBreaker),
                        cs.secondary,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Recovery Actions
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Recovery Actions',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    leading: const Icon(Icons.refresh),
                    title: const Text('Reset All Circuit Breakers'),
                    subtitle: const Text('Clear all failure states'),
                    onTap: () {
                      FirestoreSyncService.instance.syncRetry.clearAllCircuitBreakers();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('All circuit breakers reset')),
                      );
                      _refreshHealthStatus();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.bug_report),
                    title: const Text('Export Health Report'),
                    subtitle: const Text('Copy health status to clipboard'),
                    onTap: _exportHealthReport,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSyncStatusSummary(ColorScheme cs) {
    final canSync = _healthStatus['can_sync'] ?? false;
    final effectiveStatus = _healthStatus['effective_sync_status'] ?? 'Unknown';
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: canSync ? cs.primaryContainer : cs.errorContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: canSync ? cs.primary : cs.error,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            canSync ? Icons.sync : Icons.sync_disabled,
            color: canSync ? cs.onPrimaryContainer : cs.onErrorContainer,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  canSync ? 'Sync Active' : 'Sync Disabled',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: canSync ? cs.onPrimaryContainer : cs.onErrorContainer,
                  ),
                ),
                Text(
                  effectiveStatus,
                  style: TextStyle(
                    fontSize: 12,
                    color: (canSync ? cs.onPrimaryContainer : cs.onErrorContainer)
                        .withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusRow(
    String label, 
    bool status, 
    ColorScheme cs, {
    String? subtitle,
    bool inverted = false, // If true, status=true is bad (like local mode)
  }) {
    final effectiveStatus = inverted ? !status : status;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                effectiveStatus ? Icons.check_circle : Icons.cancel,
                size: 16,
                color: effectiveStatus ? cs.primary : cs.error,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text('$label: ${status ? 'Yes' : 'No'}'),
              ),
            ],
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(left: 24, top: 2),
              child: Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurface.withOpacity(0.6),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCircuitBreakerStatus(ColorScheme cs) {
    final circuitBreakers = _healthStatus['circuit_breakers'] as Map<String, dynamic>? ?? {};
    
    if (circuitBreakers.isEmpty) {
      return const Text(
        'No circuit breakers active',
        style: TextStyle(fontStyle: FontStyle.italic),
      );
    }

    return Column(
      children: circuitBreakers.entries.map((entry) {
        final key = entry.key;
        final status = entry.value as Map<String, dynamic>;
        final state = status['state'] as String? ?? 'UNKNOWN';
        final canExecute = status['can_execute'] as bool? ?? false;

        Color statusColor = switch (state) {
          'CLOSED' => cs.primary,
          'HALF_OPEN' => cs.tertiary,
          'OPEN' => cs.error,
          _ => cs.outline,
        };

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$key: $state ${canExecute ? '✓' : '✗'}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTestButton(String label, VoidCallback onPressed, Color color) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: color),
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 14),
        textAlign: TextAlign.center,
      ),
    );
  }

  void _testErrorSafely(SyncErrorCategory category) {
    // Ensure we have a valid mounted context before proceeding
    if (!mounted) return;
    
    // Use a post-frame callback to ensure we're not in the middle of a build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _testError(category);
      }
    });
  }

  void _testError(SyncErrorCategory category) {
    // Create different error types that will be properly categorized
    final Exception testException = switch (category) {
      SyncErrorCategory.network => Exception('Network connection timeout'),
      SyncErrorCategory.authentication => Exception('User unauthenticated - invalid token'),
      SyncErrorCategory.localStorage => Exception('Hive database corruption detected'),
      SyncErrorCategory.dataIntegrity => Exception('Data validation failed'),
      SyncErrorCategory.circuitBreaker => Exception('Circuit breaker is open'),
      SyncErrorCategory.permissions => Exception('Permission denied by security rules'),
      _ => Exception('Unknown error for testing'),
    };

    final testError = SyncError.fromException(
      operation: 'test_${category.name}_operation',
      error: testException,
      userId: 'test_user',
      context: {
        'test': true,
        'category': category.name,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );

    // Update context right before showing the error to ensure it's current
    SyncErrorHandler.instance.updateContext(context);
    
    SyncErrorHandler.instance.handleSyncError(
      testError,
      context: context, // Pass context directly as well
      showUserFeedback: true,
    );
  }

  void _exportHealthReport() {
    final report = StringBuffer();
    report.writeln('FermentaCraft Sync Health Report');
    report.writeln('================================');
    report.writeln('Generated: ${DateTime.now()}');
    report.writeln();
    
    // Overall status
    report.writeln('SYNC STATUS:');
    report.writeln('Overall: ${_healthStatus['can_sync'] == true ? "ACTIVE" : "DISABLED"}');
    report.writeln('Reason: ${_healthStatus['effective_sync_status'] ?? 'Unknown'}');
    report.writeln();
    
    // Detailed breakdown
    report.writeln('DETAILED STATUS:');
    report.writeln('User Enabled: ${_healthStatus['enabled']}');
    report.writeln('Signed In: ${_healthStatus['signed_in']}');
    report.writeln('Current Plan: ${_healthStatus['current_plan'] ?? 'Unknown'}');
    report.writeln('Plan Allows Sync: ${_healthStatus['plan_allows_sync']}');
    report.writeln('Local Mode: ${_healthStatus['is_local_mode']}');
    report.writeln('Plan Allows Sync (Combined): ${_healthStatus['allow_sync_by_plan']}');
    report.writeln();
    
    // Circuit breakers
    final circuitBreakers = _healthStatus['circuit_breakers'] as Map<String, dynamic>? ?? {};
    if (circuitBreakers.isNotEmpty) {
      report.writeln('CIRCUIT BREAKERS:');
      for (final entry in circuitBreakers.entries) {
        final status = entry.value as Map<String, dynamic>;
        report.writeln('${entry.key}: ${status['state']} (can_execute: ${status['can_execute']})');
      }
    } else {
      report.writeln('CIRCUIT BREAKERS: None active');
    }
    
    // Show the report in a dialog with copy functionality
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Health Report'),
        content: SingleChildScrollView(
          child: SelectableText(
            report.toString(),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}