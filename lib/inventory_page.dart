import 'package:flutter/material.dart';
import 'package:flutter_application_1/utils/inventory_item_extensions.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import '../models/inventory_item.dart';
import '../widgets/add_inventory_dialog.dart';
import '../widgets/edit_inventory_dialog.dart';
import '../widgets/log_purchase_dialog.dart';
import 'inventory_item_detail_view.dart';
import '../models/inventory_item_detail_model.dart';

// ADDED: New sort option for expiration date
enum SortOption { name, stock, expiration }

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key});

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  final TextEditingController _searchController = TextEditingController();
  SortOption _sortOption = SortOption.name;
  final Set<int> _selectedItemKeys = {};

  void _showInventoryItemDetail(BuildContext context, InventoryItem item) {
    final isWideScreen = MediaQuery.of(context).size.width > 600;
    if (isWideScreen) {
      showDialog(
        context: context,
        builder: (_) => InventoryItemDetailDialog(item: item),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => InventoryItemDetailView(item: item),
        ),
      );
    }
  }

  void _deleteSelectedItems(Box<InventoryItem> box) {
    for (var key in _selectedItemKeys) {
      box.delete(key);
    }
    setState(() => _selectedItemKeys.clear());
  }

  @override
  Widget build(BuildContext context) {
    final inventoryBox = Hive.box<InventoryItem>('inventory');

    return Scaffold(
      appBar: AppBar(
        title: const Text("Inventory"),
        actions: [
          if (_selectedItemKeys.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete),
              tooltip: 'Delete Selected',
              onPressed: () => _deleteSelectedItems(inventoryBox),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      hintText: "Search by name...",
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 12),
                DropdownButton<SortOption>(
                  value: _sortOption,
                  onChanged: (value) => setState(() => _sortOption = value!),
                  items: const [
                    DropdownMenuItem(
                      value: SortOption.name,
                      child: Text("Sort: Name"),
                    ),
                    DropdownMenuItem(
                      value: SortOption.stock,
                      child: Text("Sort: Stock Level"),
                    ),
                    // ADDED: Expiration sort option
                    DropdownMenuItem(
                      value: SortOption.expiration,
                      child: Text("Sort: Expiration"),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: ValueListenableBuilder(
              valueListenable: inventoryBox.listenable(),
              builder: (context, Box<InventoryItem> box, _) {
                if (box.values.isEmpty) {
                  return const Center(child: Text("No inventory items yet."));
                }

                final searchTerm = _searchController.text.toLowerCase();
                final List<InventoryItem> filteredItems = box.values
                    .where((item) =>
                        item.name.toLowerCase().contains(searchTerm))
                    .toList();

                // UPDATED: Sorting logic to include expiration date
                filteredItems.sort((a, b) {
                  switch (_sortOption) {
                    case SortOption.name:
                      return a.name.compareTo(b.name);
                    case SortOption.stock:
                      return b.amountInStock.compareTo(a.amountInStock);
                    case SortOption.expiration:
                      final aDate = a.expirationDate;
                      final bDate = b.expirationDate;
                      if (aDate == null && bDate == null) return 0;
                      if (aDate == null) return 1; // Items without dates go last
                      if (bDate == null) return -1;
                      return aDate.compareTo(bDate);
                  }
                });

                final Map<String, List<InventoryItem>> grouped = {};
                for (var item in filteredItems) {
                  grouped.putIfAbsent(item.category, () => []).add(item);
                }

                return ListView(
                  padding: const EdgeInsets.all(12),
                  children: grouped.entries.map((entry) {
                    return ExpansionTile(
                      initiallyExpanded: true, // Keep categories open
                      title: Text(
                        entry.key,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      children: entry.value.map((item) {
                        final key = item.key as int;
                        final isSelected = _selectedItemKeys.contains(key);

                        // --- OPTIMIZED: Expiration date logic ---
                        final now = DateTime.now();
                        final twoWeeksFromNow = now.add(const Duration(days: 14));
                        Color? expirationColor;
                        String? expirationText;

                        if (item.expirationDate != null) {
                          final date = item.expirationDate!;
                          expirationText = 'Expires: ${DateFormat.yMMMd().format(date)}';
                          if (date.isBefore(now)) {
                            expirationColor = Colors.red; // Expired
                          } else if (date.isBefore(twoWeeksFromNow)) {
                            expirationColor = Colors.orange; // Expiring soon
                          }
                        }
                        // --- End of optimization logic ---

                        return Card(
                          child: ListTile(
                            leading: Checkbox(
                              value: isSelected,
                              onChanged: (selected) {
                                setState(() {
                                  selected == true
                                      ? _selectedItemKeys.add(key)
                                      : _selectedItemKeys.remove(key);
                                });
                              },
                            ),
                            onTap: () => _showInventoryItemDetail(context, item),
                            title: Text(item.name),
                            // UPDATED: Subtitle is now a Column to show both lines
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "${item.amountInStock} ${item.getDisplayUnit(item.amountInStock)}",
                                ),
                                if (expirationText != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4.0),
                                    child: Text(
                                      expirationText,
                                      style: TextStyle(
                                        color: expirationColor,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.attach_money),
                                  tooltip: 'Log Purchase',
                                  onPressed: () async {
                                    await showDialog(
                                      context: context,
                                      builder: (_) =>
                                          LogPurchaseDialog(item: item),
                                    );
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.edit),
                                  tooltip: 'Edit Item',
                                  onPressed: () async {
                                    await showDialog(
                                      context: context,
                                      builder: (_) =>
                                          EditInventoryDialog(item: item),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    );
                  }).toList(),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await showDialog(
            context: context,
            builder: (_) => const AddInventoryDialog(),
          );
        },
        tooltip: 'Add Inventory Item',
        child: const Icon(Icons.add),
      ),
    );
  }
}
