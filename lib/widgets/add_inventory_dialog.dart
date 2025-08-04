import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/inventory_item.dart';
import '../models/unit_type.dart';
import '../utils/unit_conversion.dart';
import '../models/purchase_transaction.dart';
import 'package:collection/collection.dart';

class AddInventoryDialog extends StatefulWidget {
  final Map<String, dynamic>? initialData;

  const AddInventoryDialog({super.key, this.initialData});

  @override
  State<AddInventoryDialog> createState() => _AddInventoryDialogState();
}

class _AddInventoryDialogState extends State<AddInventoryDialog> {
  final _formKey = GlobalKey<FormState>();
  String _name = '';
  String _category = 'Juice';
  double _amount = 0;
  String _unit = 'grams';
  double _cost = 0;
  String? _notes;
  UnitType _unitType = UnitType.mass;
  DateTime? _expirationDate;

  final List<String> _categories = ['Juice', 'Sugar', 'Additive', 'Yeast', 'Other'];
  final List<String> _units = [
    'grams', 'mL', 'fl oz', 'cup', 'oz', 'tsp', 'tbsp', 'gal', 'packets'];

  @override
  void initState() {
    super.initState();
    if (widget.initialData != null) {
      _name = widget.initialData!['name'] ?? '';
      _unit = widget.initialData!['unit'] ?? 'grams';
      _unitType = inferUnitType(_unit);
      final inputCategory = widget.initialData!['category'];
      if (inputCategory != null && _categories.contains(inputCategory)) {
        _category = inputCategory;
      }
    }
  }

  void _saveInventoryItem() async {
    if (_formKey.currentState?.validate() ?? false) {
      _formKey.currentState?.save();

      final inventoryBox = Hive.box<InventoryItem>('inventory');

      final existingItem = inventoryBox.values.firstWhereOrNull(
        (item) => item.name.toLowerCase() == _name.toLowerCase(),
      );

      final transaction = PurchaseTransaction(
        date: DateTime.now(),
        amount: _amount,
        cost: _cost,
        expirationDate: _expirationDate,
      );

      if (existingItem != null) {
        existingItem.purchaseHistory.add(transaction);
        existingItem.recalculateAmountInStock();
        existingItem.save();
      } else {
        final newItem = InventoryItem(
          name: _name,
          amountInStock: _amount,
          unit: _unit,
          unitType: _unitType,
          costPerUnit: _cost > 0 && _amount > 0 ? _cost / _amount : 0,
          notes: _notes,
          category: _category,
          expirationDate: _expirationDate,
          purchaseHistory: [transaction],
        );
        await inventoryBox.add(newItem);
      }
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }
  void _pickExpirationDate() async {
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
            children: [
              TextFormField(
                initialValue: _name,
                decoration: const InputDecoration(labelText: 'Name'),
                onSaved: (val) => _name = val!.trim(),
                validator: (val) => val == null || val.isEmpty ? 'Required' : null,
              ),
              DropdownButtonFormField<String>(
                value: _category,
                items: _categories.map((cat) => DropdownMenuItem(value: cat, child: Text(cat))).toList(),
                onChanged: (val) => setState(() => _category = val!),
                decoration: const InputDecoration(labelText: 'Category'),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      decoration: const InputDecoration(labelText: 'Amount in Stock'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onSaved: (val) => _amount = double.tryParse(val ?? '0') ?? 0,
                      validator: (val) => val == null || val.isEmpty ? 'Required' : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _unit,
                      items: _units.map((unit) => DropdownMenuItem(value: unit, child: Text(unit))).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          final inferred = inferUnitType(val);
                          setState(() {
                            _unit = val;
                            _unitType = inferred;
                          });
                        }
                      },
                      decoration: const InputDecoration(labelText: 'Unit'),
                    ),
                  ),
                ],
              ),
              TextFormField(
                decoration: const InputDecoration(labelText: 'Total Cost (\$)'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onSaved: (val) {
                  final parsed = double.tryParse(val ?? '');
                  _cost = parsed != null && parsed >= 0 ? parsed : 0;
                },
                validator: (val) => val == null || val.isEmpty ? 'Required' : null,
              ),
              TextFormField(
                decoration: const InputDecoration(labelText: 'Notes (optional)'),
                onSaved: (val) => _notes = val?.trim(),
              ),
              const SizedBox(height: 12),
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
