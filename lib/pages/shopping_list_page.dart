// lib/shopping_list_page.dart

import 'package:fermentacraft/widgets/show_paywall.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:collection/collection.dart'; // groupBy
import 'package:fermentacraft/services/feature_gate.dart';
import 'package:fermentacraft/widgets/soft_lock_overlay.dart';
import 'package:provider/provider.dart';
import 'package:fermentacraft/utils/snacks.dart';
import '../utils/id.dart';
import '../models/shopping_list_item.dart';

class ShoppingListPage extends StatefulWidget {
  const ShoppingListPage({super.key});

  @override
  State<ShoppingListPage> createState() => _ShoppingListPageState();
}

class _ShoppingListPageState extends State<ShoppingListPage> {
  final _shoppingBox = Hive.box<ShoppingListItem>('shopping_list');

  void _upsell(BuildContext context, String reason) {

showPaywall(context);

  }

  // Toggles the checked state of an item
  void _toggleItem(ShoppingListItem item) {
    if (!FeatureGate.instance.allowShoppingList) {
      _upsell(context, 'Shopping List is a Premium feature');
      return;
    }
    item.isChecked = !item.isChecked;
    item.save();
  }

  /// Deletes a single item after confirmation, providing an undo option.
  Future<void> _deleteItemWithConfirmation(ShoppingListItem item) async {
    if (!FeatureGate.instance.allowShoppingList) {
      _upsell(context, 'Shopping List is a Premium feature');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Item'),
          content: Text('Are you sure you want to delete "${item.name}"?'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              child: const Text('Delete'),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    final itemKey = item.key;
    final itemBackup = ShoppingListItem(
      id: item.id,
      name: item.name,
      amount: item.amount,
      unit: item.unit,
      recipeName: item.recipeName,
      isChecked: item.isChecked,
    );

    await item.delete();
    if (!mounted) return;

    snacks.show(
      SnackBar(
        content: Text('Deleted "${itemBackup.name}"'),
        action: SnackBarAction(
          label: 'UNDO',
          onPressed: () {
            _shoppingBox.put(itemKey, itemBackup);
          },
        ),
      ),
    );
  }

  // Shows a dialog to add an item manually
  Future<void> _showAddItemDialog() async {
    if (!FeatureGate.instance.allowShoppingList) {
      _upsell(context, 'Shopping List is a Premium feature');
      return;
    }

    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    final amountController = TextEditingController();
    final unitController = TextEditingController();

    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Add Manual Item'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Item Name'),
                  validator: (value) => value!.isEmpty ? 'Please enter a name' : null,
                ),
                TextFormField(
                  controller: amountController,
                  decoration: const InputDecoration(labelText: 'Amount'),
                  keyboardType: TextInputType.number,
                  validator: (value) => value!.isEmpty ? 'Please enter an amount' : null,
                ),
                TextFormField(
                  controller: unitController,
                  decoration: const InputDecoration(labelText: 'Unit (e.g., lbs, oz)'),
                  validator: (value) => value!.isEmpty ? 'Please enter a unit' : null,
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              child: const Text('Add'),
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  final newItem = ShoppingListItem(
                    id: generateId(),
                    name: nameController.text,
                    amount: double.tryParse(amountController.text) ?? 0,
                    unit: unitController.text,
                    recipeName: 'General',
                  );
                  _shoppingBox.put(newItem.id, newItem);
                  Navigator.of(context).pop();
                }
              },
            ),
          ],
        );
      },
    );
  }

  // Deletes all items that are currently checked
  void _clearCheckedItems() {
    if (!FeatureGate.instance.allowShoppingList) {
      _upsell(context, 'Shopping List is a Premium feature');
      return;
    }

    final List<dynamic> keysToDelete = _shoppingBox.values
        .where((item) => item.isChecked)
        .map((item) => item.key)
        .toList();

    if (keysToDelete.isNotEmpty) {
      _shoppingBox.deleteAll(keysToDelete);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fg = context.watch<FeatureGate>();

    return Scaffold(
appBar: AppBar(
  title: const Row(
    children: [
      Text('🛒 Shopping List'),
      SizedBox(width: 8),
      
    ],
  ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'Clear Checked Items',
            onPressed: () {
              if (!fg.allowShoppingList) {
                _upsell(context, 'Shopping List is a Premium feature');
                return;
              }
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Are you sure?'),
                  content: const Text('This will permanently delete all checked items.'),
                  actions: [
                    TextButton(
                      child: const Text('No'),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                    TextButton(
                      child: const Text('Yes, Delete'),
                      onPressed: () {
                        _clearCheckedItems();
                        Navigator.of(ctx).pop();
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),

      // Keep the list visible but non-interactive for Free
      body: SoftLockOverlay(
        allow: fg.allowShoppingList,
        message: 'Shopping List is a Premium feature',
        child: ValueListenableBuilder(
          valueListenable: _shoppingBox.listenable(),
          builder: (context, Box<ShoppingListItem> box, _) {
            final items = box.values.toList();

            if (items.isEmpty) {
              return const Center(
                child: Text(
                  'Your shopping list is empty!',
                  style: TextStyle(fontSize: 18, color: Colors.grey),
                ),
              );
            }

            final groupedItems = groupBy(items, (item) => item.recipeName);
            final sortedRecipeNames = groupedItems.keys.toList()..sort();

            return ListView.builder(
              itemCount: sortedRecipeNames.length,
              itemBuilder: (context, index) {
                final recipeName = sortedRecipeNames[index];
                final recipeItems = groupedItems[recipeName]!;

                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: ExpansionTile(
                    title: Text(
                      recipeName,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                    initiallyExpanded: true,
                    children: recipeItems.map((item) {
                      return Dismissible(
                        key: ValueKey<String>(item.id),
                        confirmDismiss: (direction) async {
                          _deleteItemWithConfirmation(item);
                          return false;
                        },
                        background: Container(
                          color: Colors.red.shade400,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20.0),
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        child: InkWell(
                          onLongPress: () => _deleteItemWithConfirmation(item),
                          child: CheckboxListTile(
                            value: item.isChecked,
                            onChanged: (_) => _toggleItem(item),
                            title: Text(
                              '${item.amount.toStringAsFixed(2)} ${item.unit} ${item.name}',
                              style: TextStyle(
                                decoration: item.isChecked ? TextDecoration.lineThrough : TextDecoration.none,
                                color: item.isChecked ? Colors.grey[600] : null,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                );
              },
            );
          },
        ),
      ),

      // FAB remains visible; upsells for Free
      floatingActionButton: FloatingActionButton(
        heroTag: 'addManualItemFab',
        onPressed: () {
          if (!fg.allowShoppingList) {
            _upsell(context, 'Shopping List is a Premium feature');
            return;
          }
          _showAddItemDialog();
        },
        tooltip: 'Add Manual Item',
        child: const Icon(Icons.add),
      ),
    );
  }
}
