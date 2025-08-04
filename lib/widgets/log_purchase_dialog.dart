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
  DateTime? _expirationDate; // Added for expiration date logging
  double _amount = 0;
  double _cost = 0;

  final _amountController = TextEditingController();
  final _costController = TextEditingController();

  void _saveTransaction() {
    if (_formKey.currentState?.validate() ?? false) {
      _formKey.currentState?.save();

      // FIX: The logic is now much simpler.
      
      // 1. Create the new transaction.
      final transaction = PurchaseTransaction(
        amount: _amount,
        cost: _cost,
        date: _date,
        expirationDate: _expirationDate,
      );

      // 2. Add it to the item's history using the helper method.
      //    This automatically saves the parent item.
      widget.item.addPurchase(transaction);

      // 3. Close the dialog.
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _pickDate(bool isExpiration) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (isExpiration ? _expirationDate : _date) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
    );
    if (picked != null) {
      setState(() {
        if (isExpiration) {
          _expirationDate = picked;
        } else {
          _date = picked;
        }
      });
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
    final currentAmount = double.tryParse(_amountController.text) ?? 0;
    final currentCost = double.tryParse(_costController.text) ?? 0;
    if (currentAmount > 0 && currentCost > 0) {
      unitCost = currentCost / currentAmount;
    }

    return AlertDialog(
      title: Text("Log Purchase: ${widget.item.name}"),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _amountController,
                decoration: InputDecoration(labelText: "Amount Purchased (${widget.item.unit})"),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onSaved: (val) => _amount = double.tryParse(val ?? '0') ?? 0,
                validator: (val) {
                  if (val == null || val.isEmpty) return "Required";
                  if ((double.tryParse(val) ?? 0) <= 0) return "Must be positive";
                  return null;
                },
              ),
              TextFormField(
                controller: _costController,
                decoration: const InputDecoration(labelText: "Total Cost (\$)"),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onSaved: (val) => _cost = double.tryParse(val ?? '0') ?? 0,
                validator: (val) {
                  if (val == null || val.isEmpty) return "Required";
                   if ((double.tryParse(val) ?? 0) <= 0) return "Must be positive";
                  return null;
                },
              ),
              const SizedBox(height: 8),
              if (unitCost != null)
                Text(
                  "Cost per ${widget.item.unit}: \$${unitCost.toStringAsFixed(2)}",
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("Purchased: ${DateFormat.yMMMd().format(_date)}"),
                  TextButton(child: const Text('Change'), onPressed: () => _pickDate(false)),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                   Text("Expires: ${_expirationDate != null ? DateFormat.yMMMd().format(_expirationDate!) : 'Not set'}"),
                  TextButton(child: const Text('Set'), onPressed: () => _pickDate(true)),
                ],
              ),
            ],
          ),
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