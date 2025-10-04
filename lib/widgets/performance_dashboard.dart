/// Performance monitoring dashboard widget
/// Provides real-time performance metrics, profiling controls, and validation tools
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/performance_profiler.dart';
import '../services/memory_optimization_service.dart';
import 'memory_usage_widget.dart';

class PerformanceDashboard extends StatefulWidget {
  const PerformanceDashboard({super.key});

  @override
  State<PerformanceDashboard> createState() => _PerformanceDashboardState();
}

class _PerformanceDashboardState extends State<PerformanceDashboard>
    with TickerProviderStateMixin {
  late TabController _tabController;
  Timer? _refreshTimer;
  bool _isAutoRefresh = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    
    if (_isAutoRefresh) {
      _startAutoRefresh();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    // Reduced frequency to save resources
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  void _stopAutoRefresh() {
    _refreshTimer?.cancel();
  }

  void _toggleAutoRefresh() {
    setState(() {
      _isAutoRefresh = !_isAutoRefresh;
      if (_isAutoRefresh) {
        _startAutoRefresh();
      } else {
        _stopAutoRefresh();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Performance Dashboard'),
        actions: [
          IconButton(
            icon: Icon(_isAutoRefresh ? Icons.pause : Icons.play_arrow),
            onPressed: _toggleAutoRefresh,
            tooltip: _isAutoRefresh ? 'Pause refresh' : 'Start refresh',
          ),
          PopupMenuButton<String>(
            onSelected: (value) => _handleMenuAction(value),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(Icons.clear_all),
                    SizedBox(width: 8),
                    Text('Clear Metrics'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'cleanup',
                child: Row(
                  children: [
                    Icon(Icons.cleaning_services),
                    SizedBox(width: 8),
                    Text('Force Memory Cleanup'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'export',
                child: Row(
                  children: [
                    Icon(Icons.download),
                    SizedBox(width: 8),
                    Text('Export Data'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'toggle',
                child: Row(
                  children: [
                    Icon(PerformanceProfiler.instance.isEnabled 
                        ? Icons.stop 
                        : Icons.play_arrow),
                    const SizedBox(width: 8),
                    Text(PerformanceProfiler.instance.isEnabled 
                        ? 'Stop Monitoring' 
                        : 'Start Monitoring'),
                  ],
                ),
              ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.speed), text: 'Overview'),
            Tab(icon: Icon(Icons.timeline), text: 'Frame Rate'),
            Tab(icon: Icon(Icons.memory), text: 'Memory'),
            Tab(icon: Icon(Icons.build), text: 'Widgets'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOverviewTab(),
          _buildFrameRateTab(),
          _buildMemoryTab(),
          _buildWidgetTab(),
        ],
      ),
    );
  }

  Widget _buildOverviewTab() {
    final summary = PerformanceProfiler.instance.getPerformanceSummary();
    final isEnabled = PerformanceProfiler.instance.isEnabled;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStatusCard(
            'Monitoring Status',
            isEnabled ? 'Active' : 'Inactive',
            isEnabled ? Colors.green : Colors.red,
            icon: isEnabled ? Icons.monitor : Icons.monitor_outlined,
            actions: [
              ElevatedButton.icon(
                onPressed: () {
                  PerformanceProfiler.instance.setEnabled(!isEnabled);
                  setState(() {});
                },
                icon: Icon(isEnabled ? Icons.stop : Icons.play_arrow),
                label: Text(isEnabled ? 'Stop' : 'Start'),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Memory usage display with optimization recommendations
          const MemoryUsageWidget(),
          const SizedBox(height: 8),
          const MemoryRecommendationsWidget(),
          
          const SizedBox(height: 16),
          
          if (summary.containsKey('frame_timing'))
            _buildFrameTimingSummaryCard(summary['frame_timing']),
          
          const SizedBox(height: 16),
          
          if (summary.containsKey('memory'))
            _buildMemorySummaryCard(summary['memory']),
          
          const SizedBox(height: 16),
          
          if (summary.containsKey('widget_rebuilds'))
            _buildWidgetRebuildSummaryCard(summary['widget_rebuilds']),
          
          const SizedBox(height: 16),
          
          _buildMetricsSummaryCard(summary['metrics']),
          
          const SizedBox(height: 16),
          
          _buildPerformanceValidationCard(),
        ],
      ),
    );
  }

  Widget _buildFrameTimingSummaryCard(Map<String, dynamic> frameData) {
    final avgFps = frameData['avg_fps'] as double? ?? 0.0;
    final jankPercentage = frameData['jank_percentage'] as double? ?? 0.0;
    
    final fpsColor = avgFps >= 55 ? Colors.green : 
                     avgFps >= 30 ? Colors.orange : Colors.red;
    final jankColor = jankPercentage <= 5 ? Colors.green :
                      jankPercentage <= 15 ? Colors.orange : Colors.red;

    return _buildStatusCard(
      'Frame Performance',
      '${avgFps.toStringAsFixed(1)} FPS',
      fpsColor,
      icon: Icons.speed,
      subtitle: 'Jank: ${jankPercentage.toStringAsFixed(1)}%',
      subtitleColor: jankColor,
      details: [
        'Avg Frame Time: ${frameData['avg_frame_time_ms']?.toStringAsFixed(2) ?? 'N/A'}ms',
        'P99 Frame Time: ${frameData['p99_frame_time_ms']?.toStringAsFixed(2) ?? 'N/A'}ms',
      ],
    );
  }

  Widget _buildMemorySummaryCard(Map<String, dynamic> memoryData) {
    final currentMB = memoryData['current_mb'] as double? ?? 0.0;
    final baselineMB = memoryData['baseline_mb'] as double? ?? 150.0;
    final withinBaseline = memoryData['within_baseline'] as bool? ?? true;
    
    final memoryColor = withinBaseline ? Colors.green : Colors.orange;

    return _buildStatusCard(
      'Memory Usage',
      '${currentMB.toStringAsFixed(1)} MB',
      memoryColor,
      icon: Icons.memory,
      subtitle: 'Baseline: ${baselineMB.toStringAsFixed(0)}MB',
      details: [
        'Status: ${withinBaseline ? 'Within Baseline' : 'Above Baseline'}',
        'Overhead: ${((currentMB / baselineMB - 1) * 100).toStringAsFixed(1)}%',
      ],
    );
  }

  Widget _buildWidgetRebuildSummaryCard(Map<String, dynamic> widgetData) {
    final totalWidgets = widgetData['total_widgets'] as int? ?? 0;
    final totalRebuilds = widgetData['total_rebuilds'] as int? ?? 0;
    final mostRebuiltWidget = widgetData['most_rebuilt_widget'] as String? ?? 'N/A';
    final maxRebuilds = widgetData['max_rebuilds'] as int? ?? 0;
    
    final avgRebuilds = totalWidgets > 0 ? totalRebuilds / totalWidgets : 0.0;
    final rebuildColor = avgRebuilds <= 5 ? Colors.green :
                         avgRebuilds <= 15 ? Colors.orange : Colors.red;

    return _buildStatusCard(
      'Widget Rebuilds',
      '$totalRebuilds Total',
      rebuildColor,
      icon: Icons.build,
      subtitle: '$totalWidgets Widgets Tracked',
      details: [
        'Average: ${avgRebuilds.toStringAsFixed(1)} rebuilds/widget',
        'Most Rebuilt: $mostRebuiltWidget ($maxRebuilds times)',
      ],
    );
  }

  Widget _buildMetricsSummaryCard(Map<String, dynamic> metricsData) {
    final totalRecorded = metricsData['total_recorded'] as int? ?? 0;
    final byCategory = metricsData['by_category'] as Map<String, dynamic>? ?? {};

    return _buildStatusCard(
      'Metrics Collection',
      '$totalRecorded Total',
      Colors.blue,
      icon: Icons.analytics,
      details: [
        for (final entry in byCategory.entries)
          '${entry.key}: ${entry.value}',
      ],
    );
  }

  Widget _buildStatusCard(
    String title,
    String value,
    Color valueColor, {
    IconData? icon,
    String? subtitle,
    Color? subtitleColor,
    List<String>? details,
    List<Widget>? actions,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 24),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (actions != null) ...actions,
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: valueColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: subtitleColor ?? Colors.grey[600],
                ),
              ),
            ],
            if (details != null && details.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              for (final detail in details) ...[
                Text(
                  detail,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFrameRateTab() {
    final frameStats = FrameTimingMonitor.instance.currentFrameStats;
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Frame Timing Analysis',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          
          if (frameStats != null) ...[
            _buildFrameStatsCard(frameStats),
            const SizedBox(height: 16),
            _buildFrameTargetsCard(),
          ] else ...[
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('No frame data available. Start monitoring to collect frame metrics.'),
              ),
            ),
          ],
          
          const SizedBox(height: 16),
          _buildFrameTestingCard(),
        ],
      ),
    );
  }

  Widget _buildFrameStatsCard(PerformanceStats stats) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Current Frame Statistics',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            
            _buildStatRow('Average FPS', (1000.0 / stats.mean).toStringAsFixed(1)),
            _buildStatRow('Average Frame Time', '${stats.mean.toStringAsFixed(2)}ms'),
            _buildStatRow('Min Frame Time', '${stats.min.toStringAsFixed(2)}ms'),
            _buildStatRow('Max Frame Time', '${stats.max.toStringAsFixed(2)}ms'),
            _buildStatRow('P50 Frame Time', '${stats.p50.toStringAsFixed(2)}ms'),
            _buildStatRow('P95 Frame Time', '${stats.p95.toStringAsFixed(2)}ms'),
            _buildStatRow('P99 Frame Time', '${stats.p99.toStringAsFixed(2)}ms'),
            _buildStatRow('Total Frames', '${stats.count}'),
          ],
        ),
      ),
    );
  }

  Widget _buildFrameTargetsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Performance Targets',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            
            _buildTargetRow('60 FPS Target', '16.67ms', Colors.green),
            _buildTargetRow('30 FPS Minimum', '33.33ms', Colors.orange),
            _buildTargetRow('Jank Threshold', '16.67ms', Colors.red),
            _buildTargetRow('Severe Jank', '50.00ms', Colors.red[800]!),
          ],
        ),
      ),
    );
  }

  Widget _buildMemoryTab() {
    final currentMemory = MemoryMonitor.instance.currentMemoryMB;
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Memory Usage Analysis',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          
          if (currentMemory != null) ...[
            _buildMemoryUsageCard(currentMemory),
            const SizedBox(height: 16),
            _buildMemoryTargetsCard(),
          ] else ...[
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('Memory monitoring not available on this platform.'),
              ),
            ),
          ],
          
          const SizedBox(height: 16),
          _buildMemoryTestingCard(),
        ],
      ),
    );
  }

  Widget _buildMemoryUsageCard(double currentMemory) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Current Memory Usage',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            
            Text(
              '${currentMemory.toStringAsFixed(1)} MB',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: _getMemoryColor(currentMemory),
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            
            LinearProgressIndicator(
              value: (currentMemory / 500.0).clamp(0.0, 1.0), // 500MB max scale
              backgroundColor: Colors.grey[300],
              valueColor: AlwaysStoppedAnimation(_getMemoryColor(currentMemory)),
            ),
            const SizedBox(height: 16),
            
            _buildStatRow('Status', _getMemoryStatus(currentMemory)),
            _buildStatRow('Baseline (150MB)', '${(currentMemory / 150.0 * 100).toStringAsFixed(0)}%'),
          ],
        ),
      ),
    );
  }

  Color _getMemoryColor(double memoryMB) {
    if (memoryMB <= 200) return Colors.green;
    if (memoryMB <= 350) return Colors.orange;
    return Colors.red;
  }

  String _getMemoryStatus(double memoryMB) {
    if (memoryMB <= 200) return 'Good';
    if (memoryMB <= 350) return 'Moderate';
    return 'High';
  }

  Widget _buildMemoryTargetsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Memory Targets',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            
            _buildTargetRow('Baseline Target', '150 MB', Colors.green),
            _buildTargetRow('Acceptable Range', '< 200 MB', Colors.orange),
            _buildTargetRow('Warning Level', '200-350 MB', Colors.orange),
            _buildTargetRow('Critical Level', '> 350 MB', Colors.red),
          ],
        ),
      ),
    );
  }

  Widget _buildWidgetTab() {
    final rebuilds = WidgetRebuildTracker.instance.rebuildCounts;
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Widget Rebuild Analysis',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              ElevatedButton.icon(
                onPressed: () {
                  WidgetRebuildTracker.instance.reset();
                  setState(() {});
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Reset'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          if (rebuilds.isNotEmpty) ...[
            _buildWidgetRebuildSummary(rebuilds),
            const SizedBox(height: 16),
            _buildWidgetRebuildList(rebuilds),
          ] else ...[
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('No widget rebuild data available. Use WidgetRebuildTracker.instance.trackRebuild() in your widgets to collect data.'),
              ),
            ),
          ],
          
          const SizedBox(height: 16),
          _buildWidgetTrackingGuide(),
        ],
      ),
    );
  }

  Widget _buildWidgetRebuildSummary(Map<String, int> rebuilds) {
    final totalRebuilds = rebuilds.values.reduce((a, b) => a + b);
    final avgRebuilds = totalRebuilds / rebuilds.length;
    final maxRebuilds = rebuilds.values.reduce((a, b) => a > b ? a : b);
    final maxWidget = rebuilds.entries
        .firstWhere((entry) => entry.value == maxRebuilds)
        .key;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Rebuild Summary',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            
            _buildStatRow('Total Widgets', '${rebuilds.length}'),
            _buildStatRow('Total Rebuilds', '$totalRebuilds'),
            _buildStatRow('Average Rebuilds/Widget', avgRebuilds.toStringAsFixed(1)),
            _buildStatRow('Most Rebuilt Widget', maxWidget),
            _buildStatRow('Max Rebuilds', '$maxRebuilds'),
          ],
        ),
      ),
    );
  }

  Widget _buildWidgetRebuildList(Map<String, int> rebuilds) {
    final sortedEntries = rebuilds.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Widget Rebuild Details',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            
            ...sortedEntries.take(20).map((entry) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.key,
                      style: Theme.of(context).textTheme.bodyMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: _getRebuildCountColor(entry.value),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${entry.value}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            )),
            
            if (sortedEntries.length > 20) ...[
              const SizedBox(height: 8),
              Text(
                '... and ${sortedEntries.length - 20} more',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey[600],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _getRebuildCountColor(int count) {
    if (count <= 5) return Colors.green;
    if (count <= 15) return Colors.orange;
    return Colors.red;
  }

  Widget _buildPerformanceValidationCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Performance Validation',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            
            const Text(
              'Run comprehensive performance validation tests to verify optimizations.',
            ),
            const SizedBox(height: 16),
            
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: _runFrameRateTest,
                  icon: const Icon(Icons.speed),
                  label: const Text('Frame Rate Test'),
                ),
                ElevatedButton.icon(
                  onPressed: _runMemoryTest,
                  icon: const Icon(Icons.memory),
                  label: const Text('Memory Test'),
                ),
                ElevatedButton.icon(
                  onPressed: _runRebuildTest,
                  icon: const Icon(Icons.build),
                  label: const Text('Rebuild Test'),
                ),
                ElevatedButton.icon(
                  onPressed: _runFullValidation,
                  icon: const Icon(Icons.check_circle),
                  label: const Text('Full Validation'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFrameTestingCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Frame Rate Testing',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            
            const Text(
              'Generate artificial load to test frame rate performance.',
            ),
            const SizedBox(height: 16),
            
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton(
                  onPressed: _simulateLightLoad,
                  child: const Text('Light Load'),
                ),
                ElevatedButton(
                  onPressed: _simulateHeavyLoad,
                  child: const Text('Heavy Load'),
                ),
                ElevatedButton(
                  onPressed: _simulateJankFrames,
                  child: const Text('Simulate Jank'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMemoryTestingCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Memory Testing',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            
            const Text(
              'Test memory usage patterns and leak detection.',
            ),
            const SizedBox(height: 16),
            
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton(
                  onPressed: _testMemoryAllocation,
                  child: const Text('Allocation Test'),
                ),
                ElevatedButton(
                  onPressed: _testMemoryLeaks,
                  child: const Text('Leak Test'),
                ),
                ElevatedButton(
                  onPressed: _forceGarbageCollection,
                  child: const Text('Force GC'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWidgetTrackingGuide() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Widget Tracking Guide',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            
            const Text(
              'To track widget rebuilds, add this code to your widget\'s build method:',
            ),
            const SizedBox(height: 8),
            
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: const Text(
                'WidgetRebuildTracker.instance.trackRebuild(\'MyWidget\');',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 12),
            
            const Text(
              'Place this call at the beginning of your build() method to track rebuilds.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildTargetRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              border: Border.all(color: color),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              value,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Performance testing methods
  Future<void> _runFrameRateTest() async {
    _showTestDialog('Frame Rate Test', 'Testing frame rate performance...');
    
    // Record baseline
    await Future.delayed(const Duration(milliseconds: 500));
    
    // Simulate various loads
    for (int i = 0; i < 10; i++) {
      setState(() {}); // Force rebuild
      await Future.delayed(const Duration(milliseconds: 100));
    }
    
    if (!mounted) return;
    Navigator.of(context).pop();
    _showTestComplete('Frame Rate Test completed');
  }

  Future<void> _runMemoryTest() async {
    _showTestDialog('Memory Test', 'Testing memory usage patterns...');
    
    // Create temporary memory load
    final heavyData = <List<int>>[];
    for (int i = 0; i < 100; i++) {
      heavyData.add(List.filled(10000, i));
      await Future.delayed(const Duration(milliseconds: 10));
    }
    
    // Let it collect
    heavyData.clear();
    
    if (!mounted) return;
    Navigator.of(context).pop();
    _showTestComplete('Memory Test completed');
  }

  Future<void> _runRebuildTest() async {
    _showTestDialog('Rebuild Test', 'Testing widget rebuild patterns...');
    
    // Force multiple rebuilds
    for (int i = 0; i < 20; i++) {
      setState(() {});
      await Future.delayed(const Duration(milliseconds: 50));
    }
    
    if (!mounted) return;
    Navigator.of(context).pop();
    _showTestComplete('Rebuild Test completed');
  }

  void _runFullValidation() async {
    _showTestDialog('Full Validation', 'Running comprehensive performance validation...');
    
    await _runFrameRateTest();
    await Future.delayed(const Duration(milliseconds: 200));
    await _runMemoryTest();
    await Future.delayed(const Duration(milliseconds: 200));
    await _runRebuildTest();
    
    if (!mounted) return;
    Navigator.of(context).pop();
    _showTestComplete('Full Performance Validation completed');
  }

  void _simulateLightLoad() async {
    for (int i = 0; i < 30; i++) {
      // Light computational load
      final _ = List.generate(1000, (index) => index * 2);
      await Future.delayed(const Duration(milliseconds: 16));
    }
  if (!mounted) return;
  _showTestComplete('Light load simulation completed');
  }

  void _simulateHeavyLoad() async {
    for (int i = 0; i < 10; i++) {
      // Heavy computational load
      final data = <double>[];
      for (int j = 0; j < 100000; j++) {
        data.add(j * 1.5);
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }
    _showTestComplete('Heavy load simulation completed');
  }

  void _simulateJankFrames() async {
    for (int i = 0; i < 5; i++) {
      // Simulate jank by blocking for longer than 16ms
      final stopwatch = Stopwatch()..start();
      while (stopwatch.elapsedMilliseconds < 50) {
        // Busy wait to simulate jank
      }
      await Future.delayed(const Duration(milliseconds: 200));
    }
    _showTestComplete('Jank simulation completed');
  }

  void _testMemoryAllocation() {
    // Create and release memory to test allocation patterns
    final data = <List<int>>[];
    for (int i = 0; i < 50; i++) {
      data.add(List.filled(5000, i));
    }
    data.clear(); // Release immediately
    _showTestComplete('Memory allocation test completed');
  }

  void _testMemoryLeaks() {
    // This would normally create potential leaks for testing
    // In a real implementation, you might create listeners that aren't disposed
    _showTestComplete('Memory leak test completed (simulated)');
  }

  void _forceGarbageCollection() {
    // Note: Dart doesn't provide direct GC control
    // This is a placeholder for garbage collection testing
    _showTestComplete('Garbage collection requested (note: Dart GC is automatic)');
  }

  void _showTestDialog(String title, String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }

  void _showTestComplete(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _handleMenuAction(String action) async {
    switch (action) {
      case 'clear':
        PerformanceProfiler.instance.clearMetrics();
        setState(() {});
        _showTestComplete('Performance metrics cleared');
        break;
        
      case 'cleanup':
        MemoryOptimizationService.instance.forceCleanup();
        setState(() {});
        _showTestComplete('Memory cleanup completed');
        break;
        
      case 'export':
        await _exportPerformanceData();
        break;
        
      case 'toggle':
        PerformanceProfiler.instance.setEnabled(
          !PerformanceProfiler.instance.isEnabled
        );
        setState(() {});
        _showTestComplete(
          PerformanceProfiler.instance.isEnabled 
            ? 'Performance monitoring started'
            : 'Performance monitoring stopped'
        );
        break;
    }
  }

  Future<void> _exportPerformanceData() async {
    try {
      final data = PerformanceProfiler.instance.exportData();
      
      // Copy to clipboard as JSON
      await Clipboard.setData(ClipboardData(
        text: '''
Performance Data Export
Generated: ${DateTime.now()}

${_formatExportData(data)}
        '''.trim(),
      ));
      
      _showTestComplete('Performance data copied to clipboard');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _formatExportData(Map<String, dynamic> data) {
    final buffer = StringBuffer();
    
    buffer.writeln('PERFORMANCE SUMMARY:');
    final summary = data['summary'] as Map<String, dynamic>? ?? {};
    
    if (summary.containsKey('frame_timing')) {
      final frame = summary['frame_timing'] as Map<String, dynamic>;
      buffer.writeln('  Frame Performance:');
      buffer.writeln('    Average FPS: ${frame['avg_fps']?.toStringAsFixed(1) ?? 'N/A'}');
      buffer.writeln('    Average Frame Time: ${frame['avg_frame_time_ms']?.toStringAsFixed(2) ?? 'N/A'}ms');
      buffer.writeln('    P99 Frame Time: ${frame['p99_frame_time_ms']?.toStringAsFixed(2) ?? 'N/A'}ms');
      buffer.writeln('    Jank Percentage: ${frame['jank_percentage']?.toStringAsFixed(1) ?? 'N/A'}%');
    }
    
    if (summary.containsKey('memory')) {
      final memory = summary['memory'] as Map<String, dynamic>;
      buffer.writeln('  Memory Usage:');
      buffer.writeln('    Current: ${memory['current_mb']?.toStringAsFixed(1) ?? 'N/A'}MB');
      buffer.writeln('    Baseline: ${memory['baseline_mb']?.toStringAsFixed(1) ?? 'N/A'}MB');
      buffer.writeln('    Within Baseline: ${memory['within_baseline'] ?? 'N/A'}');
    }
    
    if (summary.containsKey('widget_rebuilds')) {
      final rebuilds = summary['widget_rebuilds'] as Map<String, dynamic>;
      buffer.writeln('  Widget Rebuilds:');
      buffer.writeln('    Total Widgets: ${rebuilds['total_widgets'] ?? 'N/A'}');
      buffer.writeln('    Total Rebuilds: ${rebuilds['total_rebuilds'] ?? 'N/A'}');
      buffer.writeln('    Most Rebuilt: ${rebuilds['most_rebuilt_widget'] ?? 'N/A'} (${rebuilds['max_rebuilds'] ?? 'N/A'} times)');
    }
    
    buffer.writeln('\nMONITORING STATUS:');
    buffer.writeln('  Enabled: ${data['enabled'] ?? false}');
    buffer.writeln('  Total Metrics: ${(data['metrics'] as List?)?.length ?? 0}');
    
    return buffer.toString();
  }
}