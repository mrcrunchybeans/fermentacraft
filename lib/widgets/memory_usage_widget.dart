/// Simple memory usage display widget for debugging memory issues
/// Only shows in debug builds - hidden in release

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../utils/performance_profiler.dart';
import '../services/memory_optimization_service.dart';
import '../services/ultra_memory_mode.dart';

class MemoryUsageWidget extends StatefulWidget {
  const MemoryUsageWidget({super.key});

  @override
  State<MemoryUsageWidget> createState() => _MemoryUsageWidgetState();
}

class _MemoryUsageWidgetState extends State<MemoryUsageWidget> {
  Timer? _refreshTimer;
  double? _currentMemoryMB;

  @override
  void initState() {
    super.initState();
    _updateMemory();
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _updateMemory();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _updateMemory() {
    final memory = MemoryMonitor.instance.currentMemoryMB;
    if (mounted && memory != _currentMemoryMB) {
      setState(() {
        _currentMemoryMB = memory;
      });
    }
  }

  Color _getMemoryColor(double? memoryMB) {
    if (memoryMB == null) return Colors.grey;
    if (memoryMB < 200) return Colors.green;
    if (memoryMB < 350) return Colors.orange;
    return Colors.red;
  }

  String _getMemoryStatus(double? memoryMB) {
    if (memoryMB == null) return 'Unknown';
    if (memoryMB < 200) return 'Good';
    if (memoryMB < 350) return 'Moderate';
    if (memoryMB < 500) return 'High';
    return 'Critical';
  }

  @override
  Widget build(BuildContext context) {
    // Hide completely in release builds
    if (kReleaseMode) {
      return const SizedBox.shrink();
    }
    
    final memoryColor = _getMemoryColor(_currentMemoryMB);
    final memoryStatus = _getMemoryStatus(_currentMemoryMB);
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.memory, color: memoryColor),
                const SizedBox(width: 8),
                Text(
                  'Memory Usage',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            
            if (_currentMemoryMB != null) ...[
              Text(
                '${_currentMemoryMB!.toStringAsFixed(1)} MB',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: memoryColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'Status: $memoryStatus',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: memoryColor,
                ),
              ),
              
              if (_currentMemoryMB! > 400) ...[
                const SizedBox(height: 8),
                Text(
                  '⚠️ High memory usage detected',
                  style: TextStyle(
                    color: Colors.red[700],
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () {
                        MemoryOptimizationService.instance.forceCleanup();
                      },
                      icon: const Icon(Icons.cleaning_services, size: 16),
                      label: const Text('Force Cleanup'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        textStyle: const TextStyle(fontSize: 12),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (_currentMemoryMB! > 500) 
                      ElevatedButton.icon(
                        onPressed: () async {
                          await MemoryOptimizationService.instance.performNuclearCleanup();
                          _updateMemory();
                        },
                        icon: const Icon(Icons.delete_forever, size: 16),
                        label: const Text('Nuclear Cleanup'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          textStyle: const TextStyle(fontSize: 12),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        ),
                      )
                    else if (_currentMemoryMB! > 400)
                      ElevatedButton.icon(
                        onPressed: () async {
                          // Enable ultra-memory mode first
                          UltraMemoryMode.enable();
                          
                          // Perform extreme reduction
                          await MemoryOptimizationService.instance.performExtremeMemoryReduction();
                          _updateMemory();
                        },
                        icon: const Icon(Icons.flash_on, size: 16),
                        label: const Text('Extreme'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepOrange,
                          foregroundColor: Colors.white,
                          textStyle: const TextStyle(fontSize: 12),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        ),
                      ),
                  ],
                ),
              ],
            ] else ...[
              const Text('Memory monitoring not available'),
            ],
          ],
        ),
      ),
    );
  }
}

class MemoryRecommendationsWidget extends StatelessWidget {
  const MemoryRecommendationsWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final recommendations = MemoryOptimizationService.instance.getMemoryRecommendations();
    
    if (recommendations.isEmpty) {
      return const SizedBox.shrink();
    }
    
    return Card(
      color: Colors.orange[50],
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.lightbulb, color: Colors.orange[700]),
                const SizedBox(width: 8),
                Text(
                  'Memory Optimization Recommendations',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.orange[800],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            
            for (final recommendation in recommendations) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('• ', style: TextStyle(color: Colors.orange[700])),
                  Expanded(
                    child: Text(
                      recommendation,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.orange[800],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
            ],
            
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ElevatedButton.icon(
                  onPressed: () {
                    MemoryOptimizationService.instance.forceCleanup();
                  },
                  icon: const Icon(Icons.cleaning_services, size: 16),
                  label: const Text('Force Cleanup'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange[700],
                    foregroundColor: Colors.white,
                    textStyle: const TextStyle(fontSize: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                ),
                
                if (PerformanceProfiler.instance.isEnabled)
                  ElevatedButton.icon(
                    onPressed: () {
                      PerformanceProfiler.instance.setEnabled(false);
                    },
                    icon: const Icon(Icons.stop, size: 16),
                    label: const Text('Disable Monitoring'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red[700],
                      foregroundColor: Colors.white,
                      textStyle: const TextStyle(fontSize: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}