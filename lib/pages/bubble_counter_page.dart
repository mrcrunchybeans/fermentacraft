import 'package:flutter/material.dart';
import 'dart:async';

class BubbleCounterTab extends StatefulWidget {
  const BubbleCounterTab({super.key});

  @override
  State<BubbleCounterTab> createState() => _BubbleCounterTabState();
}

class _BubbleCounterTabState extends State<BubbleCounterTab> {
  List<DateTime> tapTimes = [];
  double avgInterval = 0.0;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {});
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  void recordTap() {
    final now = DateTime.now();

    setState(() {
      tapTimes.add(now);

      if (tapTimes.length >= 2) {
        List<double> intervals = [];
        for (int i = 1; i < tapTimes.length; i++) {
          intervals.add(
              tapTimes[i].difference(tapTimes[i - 1]).inMilliseconds / 1000.0);
        }

        final filtered =
            intervals.where((i) => i > 0.2 && i < 120).toList();

        if (filtered.isNotEmpty) {
          avgInterval = filtered.reduce((a, b) => a + b) / filtered.length;
        } else {
          avgInterval = 0.0;
        }
      }
    });
  }

  void reset() {
    setState(() {
      tapTimes.clear();
      avgInterval = 0.0;
    });
  }

  Widget buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bubblesPerMin =
        avgInterval > 0 ? (60 / avgInterval).toStringAsFixed(1) : "--";
    final lastTap = tapTimes.isNotEmpty ? tapTimes.last : null;
    final timeSinceLast = lastTap != null
        ? (DateTime.now().difference(lastTap).inMilliseconds / 1000.0)
            .toStringAsFixed(1)
        : "--";

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bubble Counter'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            ElevatedButton(
              onPressed: recordTap,
              style: ElevatedButton.styleFrom(
                shape: const CircleBorder(),
                padding: const EdgeInsets.all(48),
                backgroundColor: Colors.greenAccent.shade400,
                foregroundColor: Colors.black,
                elevation: 8,
              ),
              child: const Text(
                "Tap\nBubble",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 30),
            Card(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    buildStatRow("Total Taps:", tapTimes.length.toString()),
                    buildStatRow("Time Since Last Tap:", "$timeSinceLast sec"),
                    buildStatRow("Avg Interval:", "${avgInterval.toStringAsFixed(2)} sec"),
                    buildStatRow("Bubbles Per Minute:", bubblesPerMin),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 30),
            FilledButton.icon(
              onPressed: reset,
              icon: const Icon(Icons.refresh),
              label: const Text("Reset"),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
