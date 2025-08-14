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
  });

  @override
  State<EditPurchaseDialog> createState() => _EditPurchaseDialogState();
}

class _EditPurchaseDialogState extends State<EditPurchaseDialog> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _amountController;
  late TextEditingController _costController;
  late DateTime _date;
  DateTime? _expirationDate;

  @override
  void initState() {
    super.initState();
    _amountController =
        TextEditingController(text: widget.entry.amount.toString());
    _costController =
        TextEditingController(text: widget.entry.cost.toStringAsFixed(2));
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
    if (!(_formKey.currentState?.validate() ?? false)) return;
    _formKey.currentState?.save();

    widget.entry.amount =
        double.tryParse(_amountController.text.trim()) ?? 0.0;
    widget.entry.cost = double.tryParse(_costController.text.trim()) ?? 0.0;
    widget.entry.date = _date;
    widget.entry.expirationDate = _expirationDate;

    // Ensure usedAmount is not greater than new amount
    if (widget.entry.usedAmount > widget.entry.amount) {
      widget.entry.usedAmount = widget.entry.amount;
    }

    // Persist via parent (common pattern with embedded objects in Hive)
    widget.item.save();
    Navigator.of(context).pop(widget.entry);
  }

  void _deletePurchase() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Purchase?'),
        content: const Text(
          'Are you sure you want to delete this purchase entry? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              widget.item.purchaseHistory.remove(widget.entry);
              widget.item.save();
              Navigator.pop(dialogContext); // close confirm
              Navigator.pop(context); // close edit dialog
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // Guard: clamp an initial date to [first, last] to avoid showDatePicker assertion
  DateTime _clampDate(DateTime d, DateTime first, DateTime last) {
    if (d.isBefore(first)) return first;
    if (d.isAfter(last)) return last;
    return d;
  }

  @override
  Widget build(BuildContext context) {
    final expirationFirst = DateTime.now().subtract(const Duration(days: 30));
    final expirationLast = DateTime(2040);

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
                decoration:
                    InputDecoration(labelText: 'Amount (${widget.item.unit})'),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: (val) =>
                    (val == null || val.trim().isEmpty) ? 'Required' : null,
              ),
              TextFormField(
                controller: _costController,
                decoration: const InputDecoration(labelText: 'Total Cost'),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: (val) =>
                    (val == null || val.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 16),

              // Purchase date
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("Purchased: ${DateFormat.yMMMd().format(_date)}"),
                  TextButton(
                    child: const Text('Change'),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _clampDate(
                          _date,
                          DateTime(2000),
                          DateTime.now(),
                        ),
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null && mounted) {
                        setState(() => _date = picked);
                      }
                    },
                  ),
                ],
              ),

              // Expiration date
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Expires: ${_expirationDate != null ? DateFormat.yMMMd().format(_expirationDate!) : 'Not set'}",
                  ),
                  TextButton(
                    child: Text(_expirationDate == null ? 'Set' : 'Change'),
                    onPressed: () async {
                      final init = _expirationDate ??
                          DateTime.now().add(const Duration(days: 365));
                      final picked = await showDatePicker(
                        context: context,
                        initialDate:
                            _clampDate(init, expirationFirst, expirationLast),
                        firstDate: expirationFirst,
                        lastDate: expirationLast,
                      );
                      if (picked != null && mounted) {
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

      // ❗ No Spacer here — use actionsAlignment instead
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton(
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          onPressed: _deletePurchase,
          child: const Text('Delete'),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _saveChanges,
              child: const Text('Save'),
            ),
          ],
        ),
      ],
    );
  }
}
