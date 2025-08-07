// lib/widgets/dashboard_section.dart

import 'package:flutter/foundation.dart'; // Provides ValueListenable
import 'package:flutter/material.dart'; // Provides general UI widgets
import 'package:hive/hive.dart';         // Provides the 'Box' class

// NEW: A generic, reusable dashboard section widget.
class DashboardSection<T> extends StatelessWidget {
  final String title;
  final ValueListenable<Box<T>> valueListenable;
  final List<T> Function(Box<T> box) filterAndSortData;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final Widget emptyState;

  const DashboardSection({
    super.key,
    required this.title,
    required this.valueListenable,
    required this.filterAndSortData,
    required this.itemBuilder,
    required this.emptyState,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            ValueListenableBuilder<Box<T>>(
              valueListenable: valueListenable,
              builder: (context, box, _) {
                final items = filterAndSortData(box);

                if (items.isEmpty) {
                  return emptyState;
                }

                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return itemBuilder(context, item);
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}