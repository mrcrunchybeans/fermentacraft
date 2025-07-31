import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/purchase_transaction.dart';
import '../models/inventory_item.dart';

class EditPurchaseDialog extends StatefulWidget {
  final PurchaseTransaction entry;
  final InventoryItem item;
  final int index;

  const EditPurchaseDialog({
    super.key,
    required this.entry,
    required this.item,
    required this.index,
  });

  @override
  State<EditPurchaseDialog> createState() => _EditPurchaseDialogState();
}

class _EditPurchaseDialogState extends State<EditPurchaseDialog> {
  late double amount;
  late double cost;
  late DateTime date;

  final _formKey = GlobalKey<FormState>();
  late TextEditingController _amountController;
  late TextEditingController _costController;

  @override
  void initState() {
    super.initState();
    amount = widget.entry.amount;
    cost = widget.entry.totalCost ?? 0.0;
    date = widget.entry.date;

    _amountController = TextEditingController(text: amount.toString());
    _costController = TextEditingController(text: cost.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _amountController.dispose();
    _costController.dispose();
    super.dispose();
  }

  void _recalculateAndSave() {
  final totalAmount = widget.item.purchaseHistory.fold<double>(
    0,
    (sum, tx) => sum + (tx.amount),
  );

  final totalCost = widget.item.purchaseHistory.fold<double>(
    0,
    (sum, tx) => sum + (tx.totalCost ?? 0),
  );

  widget.item.amountInStock = totalAmount;

  final costPerUnit = (totalAmount > 0) ? (totalCost / totalAmount) : 0.0;

  // Safe fallback in case something later uses .isNegative on costPerUnit
  widget.item.costPerUnit = costPerUnit.isNaN ? 0.0 : costPerUnit;

  widget.item.save();
}


  @override
  Widget build(BuildContext context) {
    double? unitCost;
    if (amount > 0 && cost > 0) {
      unitCost = cost / amount;
    }

    return AlertDialog(
      title: const Text('Edit Purchase'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _amountController,
                decoration: const InputDecoration(labelText: 'Amount'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (val) => setState(() => amount = double.tryParse(val) ?? 0),
                onSaved: (val) => amount = double.tryParse(val ?? '0') ?? 0,
                validator: (val) => val == null || val.isEmpty ? "Required" : null,
              ),
              TextFormField(
                controller: _costController,
                decoration: const InputDecoration(labelText: 'Total Cost'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (val) => setState(() => cost = double.tryParse(val) ?? 0),
                onSaved: (val) => cost = double.tryParse(val ?? '0') ?? 0,
                validator: (val) => val == null || val.isEmpty ? "Required" : null,
              ),
              const SizedBox(height: 12),
              if (unitCost != null)
                Text(
                  "Cost per ${widget.item.unit}: \$${unitCost.toStringAsFixed(2)}",
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text("Date: "),
                  Text(DateFormat.yMMMd().format(date)),
                  const Spacer(),
                  TextButton(
                    child: const Text('Change'),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: date,
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        setState(() => date = picked);
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          child: const Text('Cancel'),
          onPressed: () => Navigator.pop(context),
        ),
        TextButton(
          child: const Text('Delete'),
          onPressed: () {
            widget.item.purchaseHistory.removeAt(widget.index);
            _recalculateAndSave();
            Navigator.pop(context, null);
          },
        ),
        ElevatedButton(
          child: const Text('Save'),
          onPressed: () {
            if (_formKey.currentState?.validate() ?? false) {
              _formKey.currentState?.save();
              final updated = PurchaseTransaction(
                amount: amount,
                cost: cost,
                date: date,
              );
              widget.item.purchaseHistory[widget.index] = updated;
              _recalculateAndSave();
              Navigator.pop(context, updated);
            }
          },
        ),
      ],
    );
  }
}
