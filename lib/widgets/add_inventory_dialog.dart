import 'package:fermentacraft/utils/inventory_item_extensions.dart';
import 'package:fermentacraft/widgets/show_paywall.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:collection/collection.dart';
import 'package:uuid/uuid.dart';
import 'package:fermentacraft/utils/units.dart'; // <- shared units
import '../models/inventory_item.dart';
import '../models/unit_type.dart';
import '../utils/unit_conversion.dart';
import '../models/purchase_transaction.dart';

// NEW: gating imports
import 'package:fermentacraft/services/feature_gate.dart';

class AddInventoryDialog extends StatefulWidget {
  final Map<String, dynamic>? initialData;

  const AddInventoryDialog({super.key, this.initialData});

  @override
  State<AddInventoryDialog> createState() => _AddInventoryDialogState();
}

class _AddInventoryDialogState extends State<AddInventoryDialog> {
  final _formKey = GlobalKey<FormState>();
  final _uuid = const Uuid();

  String _name = '';
  String _category = 'Juice';
  double _amount = 0;
  String _unit = 'g'; // <- default to canonical
  double _cost = 0;
  String? _notes;
  UnitType _unitType = UnitType.mass;
  DateTime? _expirationDate;

  final List<String> _categories = ['Juice', 'Sugar', 'Additive', 'Yeast', 'Other'];

  @override
  void initState() {
    super.initState();

    // Normalize incoming unit (if any) to our canonical set
    _unit = normalizeUnit(widget.initialData?['unit'] as String?);
    _unitType = inferUnitType(_unit);

    if (widget.initialData != null) {
      _name = (widget.initialData!['name'] ?? '').toString();

      // DO NOT overwrite with the raw string; keep normalized (_unit already set)
      final inputCategory = widget.initialData!['category'];
      if (inputCategory != null && _categories.contains(inputCategory)) {
        _category = inputCategory;
      }
    }
  }

  Future<void> _saveInventoryItem() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    _formKey.currentState?.save();

    final inventoryBox = Hive.box<InventoryItem>('inventory');

    final transaction = PurchaseTransaction(
      date: DateTime.now(),
      amount: _amount,
      cost: _cost,
      expirationDate: _expirationDate,
    );

    // Try to merge with an existing item by name (case-insensitive)
    final existingItem = inventoryBox.values.firstWhereOrNull(
      (item) => item.name.toLowerCase() == _name.toLowerCase(),
    );

    // Gate only when creating a brand-new item (merges are allowed)
    if (existingItem == null) {
      final fg = FeatureGate.instance;
      final activeCount = inventoryBox.values.where((i) => !i.isArchived).length;
      final atLimit = !fg.isPremium && activeCount >= fg.inventoryLimitFree;

      if (atLimit) {
        // Tell the user and offer upgrade. Keep the dialog open.
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Free limit reached (${fg.inventoryLimitFree}). Upgrade to add more.'),
              duration: const Duration(seconds: 2),
            ),
          );
showPaywall(context);

        }
        return;
      }
    }

    if (existingItem != null) {
      existingItem.addPurchase(transaction); // merge path
    } else {
      final newItem = InventoryItem(
        id: _uuid.v4(),
        name: _name.trim(),
        unit: _unit,            // <- canonical unit
        unitType: _unitType,
        notes: _notes,
        category: _category,
        purchaseHistory: [transaction],
      );
      await inventoryBox.put(newItem.id, newItem); // stable key
    }

    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _pickExpirationDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expirationDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (picked != null) {
      setState(() => _expirationDate = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Inventory Item'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Name
              TextFormField(
                initialValue: _name,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  contentPadding: EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                ),
                onSaved: (val) => _name = (val ?? '').trim(),
                validator: (val) => val == null || val.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 10),

              // Category
              DropdownButtonFormField<String>(
                value: _category,
                items: _categories
                    .map((cat) => DropdownMenuItem(value: cat, child: Text(cat)))
                    .toList(),
                onChanged: (val) => setState(() => _category = val ?? _category),
                decoration: const InputDecoration(
                  labelText: 'Category',
                  contentPadding: EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                ),
              ),
              const SizedBox(height: 10),

              // Amount + Unit
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      decoration: const InputDecoration(
                        labelText: 'Amount in Stock',
                        contentPadding: EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onSaved: (val) => _amount = double.tryParse((val ?? '').trim()) ?? 0,
                      validator: (val) => (val == null || val.trim().isEmpty)
                          ? 'Required'
                          : (double.tryParse(val.trim()) == null ? 'Invalid number' : null),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: kCanonicalUnits.contains(_unit) ? _unit : kCanonicalUnits.first, // <- guard
                      items: kCanonicalUnits
                          .map((unit) => DropdownMenuItem(value: unit, child: Text(unit)))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) {
                          final inferred = inferUnitType(val);
                          setState(() {
                            _unit = val;
                            _unitType = inferred;
                          });
                        }
                      },
                      decoration: const InputDecoration(
                        labelText: 'Unit',
                        contentPadding: EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Total Cost
              TextFormField(
                decoration: const InputDecoration(
                  labelText: 'Total Cost (\$)',
                  contentPadding: EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onSaved: (val) {
                  final parsed = double.tryParse((val ?? '').trim());
                  _cost = (parsed != null && parsed >= 0) ? parsed : 0;
                },
                validator: (val) => (val == null || val.trim().isEmpty)
                    ? 'Required'
                    : (double.tryParse(val.trim()) == null ? 'Invalid number' : null),
              ),
              const SizedBox(height: 10),

              // Notes
              TextFormField(
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  contentPadding: EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                ),
                onSaved: (val) => _notes = val?.trim(),
              ),
              const SizedBox(height: 14),

              // Expiration
              Row(
                children: [
                  const Text('Expiration:'),
                  const SizedBox(width: 12),
                  Text(
                    _expirationDate != null
                        ? "${_expirationDate!.month}/${_expirationDate!.day}/${_expirationDate!.year}"
                        : 'None selected',
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _pickExpirationDate,
                    child: const Text('Pick Date'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saveInventoryItem,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
