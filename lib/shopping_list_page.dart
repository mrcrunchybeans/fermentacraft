// lib/shopping_list_page.dart

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:collection/collection.dart'; // Import for groupBy
import 'models/shopping_list_item.dart';

class ShoppingListPage extends StatefulWidget {
  const ShoppingListPage({super.key});

  @override
  State<ShoppingListPage> createState() => _ShoppingListPageState();
}

class _ShoppingListPageState extends State<ShoppingListPage> {
  final _shoppingBox = Hive.box<ShoppingListItem>('shopping_list');

  // Toggles the checked state of an item
  void _toggleItem(ShoppingListItem item) {
    item.isChecked = !item.isChecked;
    item.save();
  }

  // Deletes a single item and provides an undo option.
  void _deleteItem(ShoppingListItem item) {
    final itemCopy = ShoppingListItem(
      name: item.name,
      amount: item.amount,
      unit: item.unit,
      recipeName: item.recipeName,
      isChecked: item.isChecked,
    )..id = item.id;

    item.delete();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Deleted "${itemCopy.name}"'),
        action: SnackBarAction(
          label: 'UNDO',
          onPressed: () {
            // Re-add the item to the box to undo the deletion.
            _shoppingBox.put(itemCopy.id, itemCopy);
          },
        ),
      ),
    );
  }

  // Shows a dialog to add an item manually
  Future<void> _showAddItemDialog() async {
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
                  validator: (value) =>
                      value!.isEmpty ? 'Please enter a name' : null,
                ),
                TextFormField(
                  controller: amountController,
                  decoration: const InputDecoration(labelText: 'Amount'),
                  keyboardType: TextInputType.number,
                  validator: (value) =>
                      value!.isEmpty ? 'Please enter an amount' : null,
                ),
                TextFormField(
                  controller: unitController,
                  decoration: const InputDecoration(labelText: 'Unit (e.g., lbs, oz)'),
                  validator: (value) =>
                      value!.isEmpty ? 'Please enter a unit' : null,
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
                    name: nameController.text,
                    amount: double.tryParse(amountController.text) ?? 0,
                    unit: unitController.text,
                    recipeName: 'General', // Manually added items
                  );
                  _shoppingBox.add(newItem);
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
    final List<dynamic> keysToDelete = _shoppingBox.values
        .where((item) => item.isChecked)
        .map((item) => item.key)
        .toList();
    
    if (keysToDelete.isNotEmpty) {
      _shoppingBox.deleteAll(keysToDelete);
    }
  }

  // Shows a confirmation dialog before deleting an item.
  Future<void> _showDeleteConfirmationDialog(ShoppingListItem item) async {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Item'),
          content: Text('Are you sure you want to delete "${item.name}"?'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: const Text('Delete'),
              onPressed: () {
                _deleteItem(item);
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🛒 Shopping List'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'Clear Checked Items',
            onPressed: () {
              // Add a confirmation dialog for safety
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
      body: ValueListenableBuilder(
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

          // Group items by recipe name
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
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  initiallyExpanded: true,
                  children: recipeItems.map((item) {
                    return Dismissible(
                      key: ValueKey(item.id), // Use the unique ID for the key
                      onDismissed: (direction) {
                        _deleteItem(item);
                      },
                      background: Container(
                        color: Colors.red.shade400,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20.0),
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      // FIX: Wrap with InkWell to handle long press.
                      child: InkWell(
                        onLongPress: () => _showDeleteConfirmationDialog(item),
                        child: CheckboxListTile(
                          value: item.isChecked,
                          onChanged: (_) => _toggleItem(item),
                          title: Text(
                            '${item.amount.toStringAsFixed(2)} ${item.unit} ${item.name}',
                            style: TextStyle(
                              decoration: item.isChecked
                                  ? TextDecoration.lineThrough
                                  : TextDecoration.none,
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
      floatingActionButton: FloatingActionButton(
        heroTag: 'addManualItemFab',
        onPressed: _showAddItemDialog,
        tooltip: 'Add Manual Item',
        child: const Icon(Icons.add),
      ),
    );
  }
}
