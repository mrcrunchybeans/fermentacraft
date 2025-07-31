import 'package:flutter/material.dart';
import 'package:flutter_application_1/utils/inventory_item_extensions.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/inventory_item.dart';
import '../widgets/add_inventory_dialog.dart';
import '../widgets/edit_inventory_dialog.dart';
import '../widgets/log_purchase_dialog.dart';
import 'inventory_item_detail_view.dart';
import '../models/inventory_item_detail_model.dart';

enum SortOption { name, stock }

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

                if (_sortOption == SortOption.name) {
                  filteredItems.sort((a, b) => a.name.compareTo(b.name));
                } else {
                  filteredItems.sort((a, b) =>
                      b.amountInStock.compareTo(a.amountInStock));
                }

                final Map<String, List<InventoryItem>> grouped = {};
                for (var item in filteredItems) {
                  grouped.putIfAbsent(item.category, () => []).add(item);
                }

                return ListView(
                  padding: const EdgeInsets.all(12),
                  children: grouped.entries.map((entry) {
                    return ExpansionTile(
                      title: Text(
                        entry.key,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      children: entry.value.map((item) {
                        final key = item.key as int;
                        final isSelected = _selectedItemKeys.contains(key);
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
                            onLongPress: () {
                              showDialog(
                                context: context,
                                builder: (_) => AlertDialog(
                                  title: const Text("Delete Item"),
                                  content: Text(
                                      "Delete '${item.name}' from inventory?"),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(),
                                      child: const Text("Cancel"),
                                    ),
                                    ElevatedButton(
                                      onPressed: () {
                                        item.delete();
                                        Navigator.of(context).pop();
                                      },
                                      child: const Text("Delete"),
                                    ),
                                  ],
                                ),
                              );
                            },
                            title: Text(item.name),
                            subtitle: Text(
                              "${item.amountInStock} ${item.getDisplayUnit(item.amountInStock)} @ \$${item.costPerUnit!.toStringAsFixed(2)} / ${item.unit}",
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
