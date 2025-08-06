import 'package:flutter/material.dart';
import 'package:fermentacraft/batch_detail_page.dart';
import 'package:fermentacraft/inventory_item_detail_view.dart';
import 'package:fermentacraft/settings_page.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import './models/inventory_item.dart';
import 'recipe_list_page.dart';
import 'batch_log_page.dart';
import 'inventory_page.dart';
import 'shopping_list_page.dart';
import 'models/batch_model.dart';
import 'tools_page.dart';
import 'widgets/empty_state_widget.dart'; // We'll use our new empty state widget

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 16.0),
          child: Text(
            "Welcome Back!",
            style: Theme.of(context).textTheme.headlineMedium,
          ),
        ),
        GridView.count(
          crossAxisCount: 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            // Refactored into its own reusable widget
            DashboardCard(
              icon: Icons.receipt_long_outlined,
              title: "Recipes",
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RecipeListPage())),
            ),
            DashboardCard(
              icon: Icons.science_outlined,
              title: "Batches",
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BatchLogPage())),
            ),
            DashboardCard(
              icon: Icons.inventory_2_outlined,
              title: "Inventory",
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const InventoryPage())),
            ),
            DashboardCard(
              icon: Icons.shopping_cart_outlined,
              title: "Shopping List",
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ShoppingListPage())),
            ),
            DashboardCard(
              icon: Icons.construction_outlined,
              title: "Tools",
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ToolsPage())),
            ),
            DashboardCard(
              icon: Icons.settings_outlined,
              title: "Settings",
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage())),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const ActiveBatchesSection(), // Refactored into its own widget
        const SizedBox(height: 24),
        const ExpiringSoonSection(), // Refactored into its own widget
      ],
    );
  }
}

// --- REFACTORED WIDGETS ---
// Note: These could be moved to their own files in a 'widgets' folder for even better organization.

class DashboardCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const DashboardCard({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class ActiveBatchesSection extends StatelessWidget {
  const ActiveBatchesSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Active Batches", style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            ValueListenableBuilder(
              valueListenable: Hive.box<BatchModel>('batches').listenable(),
              builder: (context, Box<BatchModel> box, _) {
                final activeBatches = box.values.where((batch) => batch.status != 'Completed').toList();

                if (activeBatches.isEmpty) {
                  // IMPROVEMENT: Using the branded EmptyStateWidget
                  return const EmptyStateWidget(
                    icon: Icons.science_outlined,
                    message: "No active batches.\nTime to start brewing! 🍻",
                  );
                }

                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: activeBatches.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final batch = activeBatches[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.opacity, color: Theme.of(context).colorScheme.secondary),
                      title: Text(batch.name),
                      subtitle: Text("Status: ${batch.status}"),
                      trailing: Text(DateFormat.yMMMd().format(batch.startDate)),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BatchDetailPage(batchKey: batch.key))),
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

class ExpiringSoonSection extends StatelessWidget {
  const ExpiringSoonSection({super.key});

  String _formatDaysLeft(int days) {
    if (days < 0) return "Expired";
    if (days == 0) return "Expires today";
    if (days == 1) return "Expires tomorrow";
    return "Expires in $days days";
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Expiring Soon", style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            ValueListenableBuilder(
              valueListenable: Hive.box<InventoryItem>('inventory').listenable(),
              builder: (context, Box<InventoryItem> box, _) {
                final now = DateTime.now();
                final today = DateTime(now.year, now.month, now.day);
                final thirtyDaysFromNow = today.add(const Duration(days: 30));

                final expiringItems = box.values.where((item) {
                  if (item.expirationDate == null) return false;
                  final itemExpiryDate = DateTime(item.expirationDate!.year, item.expirationDate!.month, item.expirationDate!.day);
                  return itemExpiryDate.isBefore(thirtyDaysFromNow) && !itemExpiryDate.isBefore(today);
                }).toList();

                expiringItems.sort((a, b) => a.expirationDate!.compareTo(b.expirationDate!));

                if (expiringItems.isEmpty) {
                  // IMPROVEMENT: Using the branded EmptyStateWidget
                  return const EmptyStateWidget(
                    icon: Icons.inventory_2_outlined,
                    message: "No inventory items are expiring soon. ✅",
                  );
                }

                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: expiringItems.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = expiringItems[index];
                    final itemExpiryDate = DateTime(item.expirationDate!.year, item.expirationDate!.month, item.expirationDate!.day);
                    final daysLeft = itemExpiryDate.difference(today).inDays;
                    
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.warning_amber_rounded, color: Theme.of(context).colorScheme.secondary),
                      title: Text(item.name),
                      subtitle: Text(_formatDaysLeft(daysLeft)),
                      trailing: Text(DateFormat.yMMMd().format(item.expirationDate!)),
                      onTap: () => InventoryItemDetailView.show(context, item.key),
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