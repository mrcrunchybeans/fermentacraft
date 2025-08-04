// In lib/home_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_application_1/batch_detail_page.dart';
import 'package:flutter_application_1/inventory_item_detail_view.dart'; // Import for item detail view
import 'package:flutter_application_1/settings_page.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import './models/inventory_item.dart';
import 'recipe_list_page.dart';
import 'batch_log_page.dart';
import 'inventory_page.dart';
import 'shopping_list_page.dart';
import 'models/batch_model.dart';
import 'tools_page.dart';


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
        title: const Text("Cider Hub Dashboard"),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          Text(
            "Welcome Back!",
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 2,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _buildDashboardCard(
                context,
                icon: Icons.receipt_long,
                title: "Recipes",
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RecipeListPage())),
              ),
              _buildDashboardCard(
                context,
                icon: Icons.science_outlined,
                title: "Batches",
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BatchLogPage())),
              ),
              _buildDashboardCard(
                context,
                icon: Icons.inventory_2_outlined,
                title: "Inventory",
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const InventoryPage())),
              ),
              _buildDashboardCard(
                context,
                icon: Icons.shopping_cart_outlined,
                title: "Shopping List",
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ShoppingListPage())),
              ),
              _buildDashboardCard(
                context,
                icon: Icons.construction_outlined,
                title: "Tools",
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ToolsPage())),
              ),
              _buildDashboardCard(
                context,
                icon: Icons.settings_outlined,
                title: "Settings",
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage())),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildActiveBatchesSection(),
          const SizedBox(height: 24),
          _buildExpiringSoonSection(),
        ],
      ),
    );
  }

  Widget _buildDashboardCard(BuildContext context, {required IconData icon, required String title, required VoidCallback onTap}) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).primaryColor),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveBatchesSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Active Batches",
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            ValueListenableBuilder(
              valueListenable: Hive.box<BatchModel>('batches').listenable(),
              builder: (context, Box<BatchModel> box, _) {
                final activeBatches = box.values.where((batch) => batch.status != 'Completed').toList();

                if (activeBatches.isEmpty) {
                  return const Text("No active batches. Time to start brewing! 🍻");
                }

                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: activeBatches.length,
                  itemBuilder: (context, index) {
                    final batch = activeBatches[index];
                    return InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            // FIX: Pass the 'batchKey' instead of the 'batch' object.
                            builder: (_) => BatchDetailPage(batchKey: batch.key),
                          ),
                        );
                      },
                      child: ListTile(
                        leading: const Icon(Icons.opacity, color: Colors.brown),
                        title: Text(batch.name),
                        subtitle: Text("Status: ${batch.status}"),
                        trailing: Text(DateFormat.yMMMd().format(batch.startDate)),
                      ),
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
            ValueListenableBuilder(
              valueListenable: Hive.box<InventoryItem>('inventory').listenable(),
              builder: (context, Box<InventoryItem> box, _) {
                final thirtyDaysFromNow = DateTime.now().add(const Duration(days: 30));
                
                final expiringItems = box.values.where((item) {
                  if (item.expirationDate == null) return false;
                  return item.expirationDate!.isBefore(thirtyDaysFromNow) &&
                         item.expirationDate!.isAfter(DateTime.now());
                }).toList();

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
                    return InkWell(
                      onTap: () => InventoryItemDetailView.show(context, item),
                      child: ListTile(
                        leading: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                        title: Text(item.name),
                        subtitle: Text("Expires in $daysLeft ${daysLeft == 1 ? 'day' : 'days'}"),
                        trailing: Text(DateFormat.yMMMd().format(item.expirationDate!)),
                      ),
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