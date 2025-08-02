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
            // FIX: Added a maxHeight to constrain the dialog's height
            constraints: const BoxConstraints(maxWidth: 500, maxHeight: 700),
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

  @override
  Widget build(BuildContext context) {
    final costFormatted = NumberFormat.simpleCurrency().format(item.costPerUnit);

    // --- RESTRUCTURED LAYOUT ---
    return Column(
      // REMOVED: mainAxisSize.min to allow Expanded to work correctly.
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(item.name,
              style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
        ),
        TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Details'),
            Tab(text: 'Purchase History'),
          ],
        ),
        // This Expanded widget now correctly fills the available space
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildDetailsTab(costFormatted),
              _buildPurchaseHistoryTab(),
            ],
          ),
        ),
        // --- CLEANED UP: Action buttons are now in a consistent bar ---
        const Divider(height: 1),
        Padding(
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
                onPressed: () async {
                  final updated = await showDialog<bool>(
                    context: context,
                    builder: (_) => LogPurchaseDialog(item: item),
                  );
                  if (updated == true && mounted) {
                    setState(() {});
                  }
                },
              ),
              IconButton(
                icon: const Icon(Icons.edit),
                tooltip: 'Edit Item Details',
                onPressed: () async {
                  final result = await showDialog<bool>(
                    context: context,
                    builder: (_) => EditInventoryDialog(item: item),
                  );
                  if (result == true && mounted) {
                    setState(() {});
                  }
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDetailsTab(String costFormatted) {
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
        _buildDetailRow("Amount in Stock", "${item.amountInStock.toStringAsFixed(2)} ${item.getDisplayUnit(item.amountInStock)}"),
        if (item.expirationDate != null)
           _buildDetailRow("Earliest Expiration", DateFormat.yMMMd().format(item.expirationDate!)),
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
                    .map((unit) => DropdownMenuItem(value: unit, child: Text(unit)))
                    .toList(),
                onChanged: (val) => setState(() => targetUnit = val!),
              ),
            ],
          ),
        ),
        if (item.notes != null && item.notes!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
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

    // Sort by date, most recent first
    entries.sort((a, b) => b.date.compareTo(a.date));

    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (_, i) {
        final e = entries[i];
        final cost = NumberFormat.simpleCurrency().format(e.cost);
        final date = DateFormat.yMMMd().format(e.date);
        return ListTile(
          leading: const Icon(Icons.shopping_cart),
          title: Text("${e.amount.toStringAsFixed(2)} ${item.getDisplayUnit(e.amount)} for $cost"),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Purchased: $date"),
              if (e.expirationDate != null)
                Text("Expires: ${DateFormat.yMMMd().format(e.expirationDate!)}", style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          trailing: IconButton(
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
                setState(() {});
              }
            },
          ),
        );
      },
    );
  }
}
