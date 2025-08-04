import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/purchase_transaction.dart';
import '../models/inventory_item.dart';

class EditPurchaseDialog extends StatefulWidget {
  final PurchaseTransaction entry;
  final InventoryItem item;

  const EditPurchaseDialog({
    super.key,
    required this.entry,
    required this.item,
    // The 'index' is no longer needed
  });

  @override
  State<EditPurchaseDialog> createState() => _EditPurchaseDialogState();
}

class _EditPurchaseDialogState extends State<EditPurchaseDialog> {
  final _formKey = GlobalKey<FormState>();
  
  // Local state for the form fields
  late TextEditingController _amountController;
  late TextEditingController _costController;
  late DateTime _date;
  DateTime? _expirationDate;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(text: widget.entry.amount.toString());
    _costController = TextEditingController(text: widget.entry.cost.toStringAsFixed(2));
    _date = widget.entry.date;
    _expirationDate = widget.entry.expirationDate;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _costController.dispose();
    super.dispose();
  }

  void _saveChanges() {
    if (_formKey.currentState?.validate() ?? false) {
      _formKey.currentState?.save();

      // Update the properties of the specific transaction being edited
      widget.entry.amount = double.tryParse(_amountController.text) ?? 0;
      widget.entry.cost = double.tryParse(_costController.text) ?? 0;
      widget.entry.date = _date;
      widget.entry.expirationDate = _expirationDate;

      // Important: Ensure the used amount doesn't exceed the new total amount
      if (widget.entry.usedAmount > widget.entry.amount) {
        widget.entry.usedAmount = widget.entry.amount;
      }

      // Simply save the parent item. The getters will recalculate everything automatically.
      widget.item.save();
      
      Navigator.of(context).pop(widget.entry);
    }
  }

  void _deletePurchase() {
    // Show a confirmation dialog before deleting
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Purchase?'),
        content: const Text('Are you sure you want to delete this purchase entry? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              widget.item.purchaseHistory.remove(widget.entry);
              widget.item.save();
              Navigator.pop(dialogContext); // Close confirmation dialog
              Navigator.pop(context); // Close edit dialog
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                decoration: InputDecoration(labelText: 'Amount (${widget.item.unit})'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (val) => val == null || val.isEmpty ? "Required" : null,
              ),
              TextFormField(
                controller: _costController,
                decoration: const InputDecoration(labelText: 'Total Cost'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (val) => val == null || val.isEmpty ? "Required" : null,
              ),
              const SizedBox(height: 16),
              // Date Pickers
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("Purchased: ${DateFormat.yMMMd().format(_date)}"),
                  TextButton(
                    child: const Text('Change'),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _date,
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        setState(() => _date = picked);
                      }
                    },
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("Expires: ${_expirationDate != null ? DateFormat.yMMMd().format(_expirationDate!) : 'Not set'}"),
                  TextButton(
                    child: const Text('Set'),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _expirationDate ?? DateTime.now().add(const Duration(days: 365)),
                        firstDate: DateTime.now().subtract(const Duration(days: 30)),
                        lastDate: DateTime(2040),
                      );
                      if (picked != null) {
                        setState(() => _expirationDate = picked);
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
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          onPressed: _deletePurchase,
          child: const Text('Delete'),
        ),
        const Spacer(),
        TextButton(
          child: const Text('Cancel'),
          onPressed: () => Navigator.pop(context),
        ),
        ElevatedButton(
          onPressed: _saveChanges,
          child: const Text('Save'),
        ),
      ],
    );
  }
}