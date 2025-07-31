import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/inventory_item.dart';
import '../models/purchase_transaction.dart';

class LogPurchaseDialog extends StatefulWidget {
  final InventoryItem item;

  const LogPurchaseDialog({super.key, required this.item});

  @override
  State<LogPurchaseDialog> createState() => _LogPurchaseDialogState();
}

class _LogPurchaseDialogState extends State<LogPurchaseDialog> {
  final _formKey = GlobalKey<FormState>();
  DateTime _date = DateTime.now();
  double _amount = 0;
  double _cost = 0;

  final _amountController = TextEditingController();
  final _costController = TextEditingController();

  void _saveTransaction() {
    // 1. First, validate the form.
    if (_formKey.currentState?.validate() ?? false) {
      _formKey.currentState?.save();

      // 2. Create the transaction.
      final transaction = PurchaseTransaction(
        amount: _amount,
        cost: _cost,
        date: _date,
      );
      widget.item.purchaseHistory.add(transaction);

      // 3. Recalculate the weighted cost for the entire inventory.
      double runningTotalAmount = 0;
      double runningTotalCost = 0;

      for (final tx in widget.item.purchaseHistory) {
          runningTotalAmount += tx.amount;
          runningTotalCost += tx.cost;
      }

      // 4. Update the parent inventory item.
      widget.item.amountInStock = runningTotalAmount;
      widget.item.costPerUnit = runningTotalAmount > 0 ? runningTotalCost / runningTotalAmount : 0;
      widget.item.save();

      // 5. Defensively clear controllers before popping the dialog.
      // This prevents a common framework error where a text field with invalid
      // input (e.g., a single ".") crashes upon disposal.
      _amountController.clear();
      _costController.clear();

      // 6. Close the dialog.
      Navigator.of(context).pop();
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _date = picked);
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _costController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    double? unitCost;
    if (_amount > 0 && _cost > 0) {
      unitCost = _cost / _amount;
    }

    return AlertDialog(
      title: Text("Log Purchase: ${widget.item.name}"),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton.icon(
              icon: const Icon(Icons.calendar_today),
              label: Text("Date: ${DateFormat.yMMMd().format(_date)}"),
              onPressed: _pickDate,
            ),
            TextFormField(
              controller: _amountController,
              decoration: const InputDecoration(labelText: "Amount Purchased"),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (val) => setState(() => _amount = double.tryParse(val) ?? 0),
              onSaved: (val) => _amount = double.tryParse(val ?? '0') ?? 0,
              validator: (val) {
                if (val == null || val.isEmpty) {
                  return "Required";
                }
                if (double.tryParse(val) == null) {
                  return "Please enter a valid number";
                }
                if (double.parse(val) <= 0) {
                  return "Amount must be positive";
                }
                return null; // The input is valid
              },
            ),
            TextFormField(
              controller: _costController,
              decoration: const InputDecoration(labelText: "Total Cost (\$)"),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (val) => setState(() => _cost = double.tryParse(val) ?? 0),
              onSaved: (val) => _cost = double.tryParse(val ?? '0') ?? 0,
              validator: (val) {
                if (val == null || val.isEmpty) {
                  return "Required";
                }
                if (double.tryParse(val) == null) {
                  return "Please enter a valid number";
                }
                if (double.parse(val) <= 0) {
                  return "Cost must be positive";
                }
                return null; // The input is valid
              },
            ),
            const SizedBox(height: 8),
            if (unitCost != null)
              Text(
                "Cost per ${widget.item.unit}: \$${unitCost.toStringAsFixed(2)}",
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          child: const Text("Cancel"),
          onPressed: () => Navigator.of(context).pop(),
        ),
        ElevatedButton(
          onPressed: _saveTransaction,
          child: const Text("Log Purchase"),
        ),
      ],
    );
  }
}
