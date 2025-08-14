// widgets/inventory_overview_widget.dart

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/inventory_item.dart';
import '../models/inventory_action.dart';

class InventoryOverviewWidget extends StatelessWidget {
  const InventoryOverviewWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final inventoryBox = Hive.box<InventoryItem>('inventory');
    final actionsBox = Hive.box<InventoryAction>('inventory_actions');

    final items = inventoryBox.values.toList();
    final actions = actionsBox.values.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Inventory Overview', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        ...items.map((item) {
          final totalUsed = actions
              .where((a) => a.itemName == item.name && a.wasDeducted)
              .fold(0.0, (sum, a) => sum + a.amount);
          final totalRestored = actions
              .where((a) => a.itemName == item.name && !a.wasDeducted)
              .fold(0.0, (sum, a) => sum + a.amount);
          return Card(
            child: ListTile(
              title: Text(item.name),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('In stock: ${item.amountInStock.toStringAsFixed(2)} ${item.unit}'),
                  Text('Total used: ${totalUsed.toStringAsFixed(2)} ${item.unit}'),
                  Text('Total restored: ${totalRestored.toStringAsFixed(2)} ${item.unit}'),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}
