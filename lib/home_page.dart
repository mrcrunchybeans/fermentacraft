import 'package:flutter/material.dart';
import 'package:fermentacraft/pages/batch_detail_page.dart';
import 'package:fermentacraft/inventory_item_detail_view.dart';
import 'package:fermentacraft/pages/settings_page.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import './models/inventory_item.dart';
import 'pages/recipe_list_page.dart';
import 'pages/batch_log_page.dart';
import 'pages/inventory_page.dart';
import 'pages/shopping_list_page.dart';
import 'models/batch_model.dart';
import 'pages/tools_page.dart';
import 'widgets/empty_state_widget.dart';
import 'widgets/dashboard_section.dart';
import 'widgets/expiry_alerts_section.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late String _greeting;

  @override
  void initState() {
    super.initState();
    _greeting = _getGreeting();
  }

  String _getGreeting() {
    // It's currently 5:27 PM, so this will correctly return 'Good Evening!'
    final hour = DateTime.now().hour;
    if (hour < 12) {
      return 'Good Morning!';
    }
    if (hour < 17) {
      return 'Good Afternoon!';
    }
    return 'Good Evening!';
  }

  @override
  Widget build(BuildContext context) {
    final dashboardItems = [
      DashboardCard(
        icon: Icons.receipt_long_outlined,
        title: "Recipes",
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RecipeListPage())),
      ),
      // ... other DashboardCard items
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
    ];
    
    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 16.0),
          child: Text(
            _greeting,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
        ),
        GridView.builder(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 200,
            childAspectRatio: 1,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemCount: dashboardItems.length,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemBuilder: (context, index) {
            return dashboardItems[index];
          },
        ),
        const SizedBox(height: 24),
        const ActiveBatchesSection(),
        const ExpiryAlertsSection(expiringWindowDays: 14, maxExpiredToShow: 6),
      ],
    );
  }
}

// --- REUSABLE WIDGETS ---

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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Text(title, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
            ),
          ],
        ),
      ),
    );
  }
}


// REMOVED: The DashboardSection class is now in its own file and imported at the top.


// UPDATED: Using the new DashboardSection widget
class ActiveBatchesSection extends StatelessWidget {
  const ActiveBatchesSection({super.key});

  @override
  Widget build(BuildContext context) {
    return DashboardSection<BatchModel>(
      title: "Active Batches",
      valueListenable: Hive.box<BatchModel>('batches').listenable(),
      filterAndSortData: (box) {
        return box.values
            .where((batch) => batch.status != 'Completed')
            .toList()
          ..sort((a, b) => a.startDate.compareTo(b.startDate));
      },
      emptyState: const EmptyStateWidget(
        icon: Icons.science_outlined,
        message: "No active batches.\nTime to start brewing! 🍻",
      ),
      itemBuilder: (context, batch) {
        final daysActive = DateTime.now().difference(batch.startDate).inDays;
        
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.opacity, color: Theme.of(context).colorScheme.secondary),
          title: Text(batch.name),
          subtitle: Text("Status: ${batch.status}"),
          trailing: Text("Day $daysActive", style: Theme.of(context).textTheme.bodyMedium),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BatchDetailPage(batchKey: batch.key))),
        );
      },
    );
  }
}

// UPDATED: Using the new DashboardSection widget
class ExpiringSoonSection extends StatelessWidget {
  const ExpiringSoonSection({super.key});

  String _formatDaysLeft(int days) {
    if (days < 0) return "Expired";
    if (days == 0) return "Expires today";
    if (days == 1) return "Expires tomorrow";
    return "Expires in $days days";
  }

  Color _getExpiryColor(int daysLeft, BuildContext context) {
    if (daysLeft <= 7) {
      return Theme.of(context).colorScheme.error;
    }
    if (daysLeft <= 14) {
      return Theme.of(context).colorScheme.tertiary;
    }
    return Theme.of(context).colorScheme.secondary;
  }

  @override
  Widget build(BuildContext context) {
    return DashboardSection<InventoryItem>(
      title: "Expiring Soon",
      valueListenable: Hive.box<InventoryItem>('inventory').listenable(),
      filterAndSortData: (box) {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final thirtyDaysFromNow = today.add(const Duration(days: 30));

        final expiringItems = box.values.where((item) {
          if (item.expirationDate == null) return false;
          final itemExpiryDate = DateTime(item.expirationDate!.year, item.expirationDate!.month, item.expirationDate!.day);
          return itemExpiryDate.isBefore(thirtyDaysFromNow) && !itemExpiryDate.isBefore(today);
        }).toList();

        expiringItems.sort((a, b) => a.expirationDate!.compareTo(b.expirationDate!));
        return expiringItems;
      },
      emptyState: const EmptyStateWidget(
        icon: Icons.inventory_2_outlined,
        message: "No inventory items are expiring soon. ✅",
      ),
      itemBuilder: (context, item) {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final itemExpiryDate = DateTime(item.expirationDate!.year, item.expirationDate!.month, item.expirationDate!.day);
        final daysLeft = itemExpiryDate.difference(today).inDays;

        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            Icons.warning_amber_rounded,
            color: _getExpiryColor(daysLeft, context),
          ),
          title: Text(item.name),
          subtitle: Text(_formatDaysLeft(daysLeft)),
          trailing: Text(DateFormat.yMMMd().format(item.expirationDate!)),
          onTap: () => InventoryItemDetailView.show(context, item.key),
        );
      },
    );
  }
}
