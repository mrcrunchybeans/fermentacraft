import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/utils/inventory_item_extensions.dart';
import 'package:intl/intl.dart';
import '../models/inventory_item.dart';
import '../widgets/log_purchase_dialog.dart';
import '../widgets/edit_inventory_dialog.dart';
import '../utils/unit_conversion.dart';
import 'models/purchase_transaction.dart';
import 'widgets/edit_purchase_dialog.dart';

class InventoryItemDetailView extends StatefulWidget {
  final InventoryItem item;

  const InventoryItemDetailView({super.key, required this.item});

  static void show(BuildContext context, InventoryItem item) {
    if (MediaQuery.of(context).size.width < 600 || !kIsWeb) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(item.name)),
          body: InventoryItemDetailView(item: item),
        ),
      ));
    } else {
      showDialog(
        context: context,
        builder: (_) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: InventoryItemDetailView(item: item),
          ),
        ),
      );
    }
  }

  @override
  State<InventoryItemDetailView> createState() => _InventoryItemDetailViewState();
}

class _InventoryItemDetailViewState extends State<InventoryItemDetailView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late InventoryItem item;
  String targetUnit = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    item = widget.item;
    targetUnit = item.unit;
  }

Widget _buildDetailRow(String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6),
    child: Row(
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


  @override
  Widget build(BuildContext context) {
final costFormatted = NumberFormat.simpleCurrency().format(item.costPerUnit ?? 0.0);


    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(item.name,
              style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Details'),
              Tab(text: 'Purchase History'),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildDetailsTab(costFormatted),
                _buildPurchaseHistoryTab(),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              TextButton(
                child: const Text("Close"),
                onPressed: () => Navigator.pop(context),
              ),
              ElevatedButton(
                onPressed: () async {
                  final updated = await showDialog<bool>(
                    context: context,
                    builder: (_) => LogPurchaseDialog(item: item),
                  );
                  if (updated == true && mounted) {
                    setState(() {});
                  }
                },
                child: const Text("Log Purchase"),
              ),
              IconButton(
                icon: const Icon(Icons.edit),
                tooltip: 'Edit Item',
                onPressed: () async {
                  final result = await showDialog<bool>(
                    context: context,
                    builder: (_) => EditInventoryDialog(item: item),
                  );
                  if (result == true && mounted) {
                    setState(() {
                      item = widget.item; // reassign after edit
                    });
                  }
                },
              ),
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                tooltip: 'Delete Item',
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text("Delete Item"),
                      content: Text("Are you sure you want to delete '${item.name}'?"),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text("Cancel"),
                        ),
                        ElevatedButton(
                          onPressed: () {
                            item.delete();
                            Navigator.pop(context); // confirm
                            Navigator.pop(context); // detail view
                          },
                          style: ElevatedButton.styleFrom(
                            foregroundColor: Colors.white,
                            backgroundColor: Colors.red,
                          ),
                          child: const Text("Delete"),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsTab(String costFormatted) {
    final converted = UnitConversion.tryConvertCostPerUnit(
      amount: 1.0,
      fromUnit: item.unit,
      toUnit: targetUnit,
      costPerUnit: item.costPerUnit ?? 0.0


    );

    return ListView(
      children: [
        _buildDetailRow("Category", item.unitType.toString().split('.').last),
        _buildDetailRow("Amount in Stock", "${item.amountInStock} ${item.getDisplayUnit(item.amountInStock)}"),
        _buildDetailRow("Cost per Unit", "$costFormatted / ${item.unit}"),
        if (converted != null && targetUnit != item.unit)
          _buildDetailRow(
            "Converted",
  "${NumberFormat.simpleCurrency().format(converted)} / $targetUnit"
          ),
        Padding(
          padding: const EdgeInsets.only(left: 16.0, top: 8),
          child: Row(
            children: [
              const Text("View as:"),
              const SizedBox(width: 12),
              DropdownButton<String>(
                value: targetUnit,
                items: UnitConversion.getUnitListFor(item.unitType)
                    .map((unit) => DropdownMenuItem(value: unit, child: Text(unit)))
                    .toList(),
                onChanged: (val) => setState(() => targetUnit = val!),
              ),
            ],
          ),
        ),
        if (item.notes != null && item.notes!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 16.0, left: 16, right: 16),
            child: Text(item.notes!, style: TextStyle(color: Colors.grey.shade600)),
          ),
      ],
    );
  }

 Widget _buildPurchaseHistoryTab() {
  final entries = item.purchaseHistory;
  if (entries.isEmpty) {
    return const Center(child: Text("No purchases logged."));
  }

  return ListView.builder(
    itemCount: entries.length,
    itemBuilder: (_, i) {
      final e = entries[i];
final cost = NumberFormat.simpleCurrency().format(e.totalCost);
      final date = DateFormat.yMMMd().format(e.date);
      return ListTile(
        leading: const Icon(Icons.shopping_cart),
        title: Text("${e.amount} ${item.getDisplayUnit(e.amount)} @ $cost"),
        subtitle: Text(date),
        trailing: Wrap(
          spacing: 8,
          children: [
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.blue),
              tooltip: 'Edit Purchase',
              onPressed: () async {
  final updated = await showDialog<PurchaseTransaction>(
    context: context,
builder: (_) => EditPurchaseDialog(
  entry: e,
  item: item,
  index: i,
),
  );
  if (updated != null && mounted) {
    setState(() {
      item.purchaseHistory[i] = updated;
      item.save();
    });
  }
},

            ),
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              tooltip: 'Delete Purchase',
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text("Delete Purchase"),
                    content: const Text("Are you sure you want to delete this purchase?"),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text("Cancel"),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: Colors.red,
                        ),
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text("Delete"),
                      ),
                    ],
                  ),
                );

                if (confirmed == true && mounted) {
                  setState(() {
                   final newList = List<PurchaseTransaction>.from(item.purchaseHistory)..removeAt(i);
item.purchaseHistory = newList;
                    item.save();
                  });
                }
              },
            ),
          ],
        ),
      );
    },
  );
}
    }