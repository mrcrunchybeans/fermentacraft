import 'package:flutter/material.dart';
import 'package:fermentacraft/utils/inventory_item_extensions.dart';
import 'package:intl/intl.dart';
import '../models/inventory_item.dart';
import '../models/purchase_transaction.dart';
import '../widgets/log_purchase_dialog.dart';
import '../widgets/edit_purchase_dialog.dart';

class InventoryItemDetailDialog extends StatefulWidget {
  const InventoryItemDetailDialog({super.key, required this.item});

  final InventoryItem item;

  @override
  State<InventoryItemDetailDialog> createState() => _InventoryItemDetailDialogState();
}


class _InventoryItemDetailDialogState extends State<InventoryItemDetailDialog> {
  late InventoryItem item;

  @override
  void initState() {
    super.initState();
    item = widget.item;
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("$label: ", style: const TextStyle(fontWeight: FontWeight.bold)),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(item.name),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoRow("Category", item.category),
              _infoRow("Amount in Stock", "${item.amountInStock} ${item.getDisplayUnit(item.amountInStock)}"),
              _infoRow(
  "Cost per Unit",
  // ignore: unnecessary_null_comparison
  item.costPerUnit != null
      ? "\$${item.costPerUnit.toStringAsFixed(2)}"
      : "N/A",
),

if (item.expirationDate != null)
  Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Expires: ", style: TextStyle(fontWeight: FontWeight.bold)),
        Expanded(
          child: Text(
            DateFormat.yMMMd().format(item.expirationDate!),
            // Style the text red if the date is in the past
            style: TextStyle(
              color: item.expirationDate!.isBefore(DateTime.now())
                  ? Colors.red
                  : null,
            ),
          ),
        ),
        // Add a warning icon if the item is expired
        if (item.expirationDate!.isBefore(DateTime.now()))
          const Tooltip(
            message: 'Expired',
            child: Icon(Icons.warning_amber_rounded, color: Colors.red, size: 20),
          ),
      ],
    ),
  ),

              if (item.notes != null && item.notes!.isNotEmpty)
                _infoRow("Notes", item.notes!),
              const SizedBox(height: 16),
              Text("Purchase History", style: Theme.of(context).textTheme.titleMedium),
              const Divider(),
              if (item.purchaseHistory.isEmpty)
                const Text("No purchases logged."),
              ...item.purchaseHistory.asMap().entries.map((entry) {
                final i = entry.key;
                final tx = entry.value;
final cost = NumberFormat.simpleCurrency().format(tx.totalCost);
                final date = DateFormat.yMMMd().format(tx.date);

                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.shopping_cart),
                  title: Text("${tx.amount} ${item.getDisplayUnit(tx.amount)} @ $cost"),
                  subtitle: Text(date),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue),
                        tooltip: 'Edit Purchase',
                        onPressed: () async {
                          final updated = await showDialog<PurchaseTransaction>(
                            context: context,
                            builder: (_) => EditPurchaseDialog(
  entry: tx,
  item: item,
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
                                  onPressed: () => Navigator.pop(context, true),
                                  style: ElevatedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    backgroundColor: Colors.red,
                                  ),
                                  child: const Text("Delete"),
                                ),
                              ],
                            ),
                          );

                          if (confirmed == true && mounted) {
                            setState(() {
                              final newList = List<PurchaseTransaction>.from(item.purchaseHistory)
                                ..removeAt(i);
                              item.purchaseHistory = newList;
                              item.save();
                            });
                          }
                        },
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text("Close"),
        ),
        ElevatedButton(
          onPressed: () async {
            await showDialog(
              context: context,
              builder: (_) => LogPurchaseDialog(item: item),
            );
            if (context.mounted) {
              setState(() {}); // Refresh to reflect new purchase
            }
          },
          child: const Text("Log Purchase"),
        ),
      ],
    );
  }

}
