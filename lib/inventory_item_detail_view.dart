import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fermentacraft/utils/inventory_item_extensions.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import '../models/inventory_item.dart';
import '../widgets/log_purchase_dialog.dart';
import '../widgets/edit_inventory_dialog.dart';
import '../utils/unit_conversion.dart';
import 'widgets/edit_purchase_dialog.dart';

class InventoryItemDetailView extends StatefulWidget {
  // Use the key for robust data fetching.
  final dynamic itemKey;

  const InventoryItemDetailView({super.key, required this.itemKey});

  // The show method now accepts the key.
  static void show(BuildContext context, dynamic itemKey) {
    final item = Hive.box<InventoryItem>('inventory').get(itemKey);
    if (item == null) return; // Don't show if item doesn't exist

    if (MediaQuery.of(context).size.width < 600 || !kIsWeb) {
      Navigator.of(context).push(MaterialPageRoute(
        // The Scaffold is now inside the Stateful widget itself
        builder: (_) => InventoryItemDetailView(itemKey: itemKey),
      ));
    } else {
      showDialog(
        context: context,
        builder: (_) => Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500, maxHeight: 700),
            child: Material(
              borderRadius: BorderRadius.circular(20),
              clipBehavior: Clip.antiAlias,
              child: InventoryItemDetailView(itemKey: itemKey),
            ),
          ),
        ),
      );
    }
  }

  @override
  State<InventoryItemDetailView> createState() =>
      _InventoryItemDetailViewState();
}

class _InventoryItemDetailViewState extends State<InventoryItemDetailView> {
  late String targetUnit;

  @override
  void initState() {
    super.initState();
    // Perform an initial lookup to set the default unit.
    final item = Hive.box<InventoryItem>('inventory').get(widget.itemKey);
    targetUnit = UnitConversion.normalizeUnit(item?.unit ?? 'grams');
  }

  @override
  Widget build(BuildContext context) {
    // Wrap the entire UI in a ValueListenableBuilder to get live data.
    return ValueListenableBuilder<Box<InventoryItem>>(
      valueListenable: Hive.box<InventoryItem>('inventory').listenable(),
      builder: (context, box, _) {
        final item = box.get(widget.itemKey);

        if (item == null) {
          return Scaffold(
            appBar: AppBar(title: const Text("Item Not Found")),
            body: const Center(child: Text("This item may have been deleted.")),
          );
        }

        return DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: AppBar(
              title: Text(item.name),
              bottom: const TabBar(
                tabs: [
                  Tab(text: 'Details'),
                  Tab(text: 'Purchase History'),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                _buildDetailsTab(item, context),
                _buildPurchaseHistoryTab(item, context),
              ],
            ),
            bottomNavigationBar: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton(
                    child: const Text("Close"),
                    onPressed: () => Navigator.pop(context),
                  ),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add_shopping_cart),
                    label: const Text("Log Purchase"),
                    onPressed: () => showDialog(
                      context: context,
                      builder: (_) => LogPurchaseDialog(item: item),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit),
                    tooltip: 'Edit Item Details',
                    onPressed: () => showDialog(
                      context: context,
                      builder: (_) => EditInventoryDialog(item: item),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailsTab(InventoryItem item, BuildContext context) {
    final costFormatted = NumberFormat.simpleCurrency().format(item.costPerUnit);
    final converted = UnitConversion.tryConvertCostPerUnit(
      amount: 1.0,
      fromUnit: item.unit,
      toUnit: targetUnit,
      costPerUnit: item.costPerUnit,
    );

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _buildDetailRow("Category", item.category),
        _buildDetailRow(
          "Amount in Stock",
          "${item.amountInStock.toStringAsFixed(2)} ${item.getDisplayUnit(item.amountInStock)}",
        ),
        if (item.expirationDate != null)
          _buildDetailRow(
              "Earliest Expiration", DateFormat.yMMMd().format(item.expirationDate!)),
        _buildDetailRow("Avg. Cost per Unit", "$costFormatted / ${item.unit}"),
        if (converted != null && targetUnit != item.unit)
          _buildDetailRow(
            "Converted Cost",
            "${NumberFormat.simpleCurrency().format(converted)} / $targetUnit",
          ),
        Padding(
          padding: const EdgeInsets.only(left: 16.0, top: 8),
          child: Row(
            children: [
              const Text("View cost as:"),
              const SizedBox(width: 12),
              DropdownButton<String>(
                value: targetUnit,
                items: UnitConversion.getUnitListFor(item.unitType)
                    .map((unit) =>
                        DropdownMenuItem(value: unit, child: Text(unit)))
                    .toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      targetUnit = val;
                    });
                  }
                },
              ),
            ],
          ),
        ),
        if (item.notes != null && item.notes!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child:
                Text(item.notes!, style: TextStyle(color: Colors.grey.shade600)),
          ),
      ],
    );
  }

  Widget _buildPurchaseHistoryTab(InventoryItem item, BuildContext context) {
    final entries = [...item.purchaseHistory]..sort((a, b) => b.date.compareTo(a.date));
    if (entries.isEmpty) {
      return const Center(child: Text("No purchases logged."));
    }

    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (_, i) {
        final e = entries[i];
        final cost = NumberFormat.simpleCurrency().format(e.cost);
        final date = DateFormat.yMMMd().format(e.date);
        return ListTile(
          leading: const Icon(Icons.shopping_cart),
          title: Text(
              "${e.amount.toStringAsFixed(2)} ${item.getDisplayUnit(e.amount)} for $cost"),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Purchased: $date"),
              if (e.expirationDate != null)
                Text("Expires: ${DateFormat.yMMMd().format(e.expirationDate!)}",
                    style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          trailing: IconButton(
            icon: const Icon(Icons.edit, color: Colors.blue),
            tooltip: 'Edit Purchase',
            onPressed: () {
              showDialog(
                context: context,
                builder: (_) => EditPurchaseDialog(
                  entry: e,
                  item: item,
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "$label:",
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}