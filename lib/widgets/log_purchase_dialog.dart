import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/inventory_item.dart';
import '../models/purchase_transaction.dart';
import '../models/settings_model.dart';
import '../utils/boxes.dart';
import 'package:fermentacraft/utils/money.dart'; // moneyText / moneyWithSymbol
import 'package:fermentacraft/utils/inventory_item_extensions.dart'; // <- for addPurchaseTx

class LogPurchaseDialog extends StatefulWidget {
  final InventoryItem item;

  const LogPurchaseDialog({super.key, required this.item});

  @override
  State<LogPurchaseDialog> createState() => _LogPurchaseDialogState();
}

class _LogPurchaseDialogState extends State<LogPurchaseDialog> {
  final _formKey = GlobalKey<FormState>();
  DateTime _date = DateTime.now();
  DateTime? _expirationDate;
  double _amount = 0;
  double _cost = 0;

  final _amountController = TextEditingController();
  final _costController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // live preview of unit cost as user types
    _amountController.addListener(_recalc);
    _costController.addListener(_recalc);
  }

  @override
  void dispose() {
    _amountController.removeListener(_recalc);
    _costController.removeListener(_recalc);
    _amountController.dispose();
    _costController.dispose();
    super.dispose();
  }

  void _recalc() => setState(() {});

  Future<void> _saveTransaction() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    _formKey.currentState?.save();

    final tx = PurchaseTransaction(
      amount: _amount,
      cost: _cost, // TOTAL cost of this purchase
      date: _date,
      expirationDate: _expirationDate,
    );

    // Append the transaction
    widget.item.addPurchaseTx(tx);

    // Persist back to Hive (handles either string-id or auto keys)
    final box = Hive.box<InventoryItem>(Boxes.inventory);
    dynamic foundKey;

    // Try to find by identity or by id
    for (final k in box.keys) {
      final v = box.get(k);
      if (identical(v, widget.item)) {
        foundKey = k;
        break;
      }
      if (v is InventoryItem && v.id == widget.item.id) {
        foundKey = k;
        break;
      }
    }

    if (foundKey != null) {
      await box.put(foundKey, widget.item);
    } else {
      // Fallback: put by stable id (works if box uses string keys)
      await box.put(widget.item.id, widget.item);
    }

    if (!mounted) return;
    Navigator.of(context).pop(true);
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
  Widget build(BuildContext context) {
    final symbol = context.watch<SettingsModel>().currencySymbol;

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
                decoration: InputDecoration(
                  labelText: "Amount Purchased (${widget.item.unit})",
                ),
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
                decoration: InputDecoration(
                  labelText: "Total Cost",
                  prefixText: '$symbol ',
                ),
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
                  "Cost per ${widget.item.unit}: ${moneyText(context, unitCost)}",
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("Purchased: ${DateFormat.yMMMd().format(_date)}"),
                  TextButton(
                    child: const Text('Change'),
                    onPressed: () => _pickDate(false),
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Expires: ${_expirationDate != null ? DateFormat.yMMMd().format(_expirationDate!) : 'Not set'}",
                  ),
                  TextButton(
                    child: Text(_expirationDate == null ? 'Set' : 'Change'),
                    onPressed: () => _pickDate(true),
                  ),
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
