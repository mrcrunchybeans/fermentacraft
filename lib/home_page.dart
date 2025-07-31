// In lib/home_page.dart

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import './models/inventory_item.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Cider Hub"),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          Text(
            "Welcome!",
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 24),
          _buildExpiringSoonSection(),
          // You can add more sections here in the future
        ],
      ),
    );
  }

  Widget _buildExpiringSoonSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Expiring Soon",
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            // Use a ValueListenableBuilder to automatically update when Hive changes
            ValueListenableBuilder(
              valueListenable: Hive.box<InventoryItem>('inventory').listenable(),
              builder: (context, Box<InventoryItem> box, _) {
                final thirtyDaysFromNow = DateTime.now().add(const Duration(days: 30));
                
                final expiringItems = box.values.where((item) {
                  // Keep items that have an expiration date set
                  if (item.expirationDate == null) return false;
                  // Keep items expiring within the next 30 days but not already past
                  return item.expirationDate!.isBefore(thirtyDaysFromNow) &&
                         item.expirationDate!.isAfter(DateTime.now());
                }).toList();

                // Sort by soonest expiration date
                expiringItems.sort((a, b) => a.expirationDate!.compareTo(b.expirationDate!));

                if (expiringItems.isEmpty) {
                  return const Text("No inventory items are expiring soon. ✅");
                }

                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: expiringItems.length,
                  itemBuilder: (context, index) {
                    final item = expiringItems[index];
                    final daysLeft = item.expirationDate!.difference(DateTime.now()).inDays;
                    return ListTile(
                      leading: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                      title: Text(item.name),
                      subtitle: Text("Expires in $daysLeft ${daysLeft == 1 ? 'day' : 'days'}"),
                      trailing: Text(DateFormat.yMMMd().format(item.expirationDate!)),
                    );
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