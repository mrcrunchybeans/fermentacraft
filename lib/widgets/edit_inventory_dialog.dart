import 'package:flutter/material.dart';
import '../models/inventory_item.dart';
import '../models/unit_type.dart';

class EditInventoryDialog extends StatefulWidget {
  final InventoryItem item;

  const EditInventoryDialog({super.key, required this.item});

  @override
  State<EditInventoryDialog> createState() => _EditInventoryDialogState();
}

class _EditInventoryDialogState extends State<EditInventoryDialog> {
  final _formKey = GlobalKey<FormState>();
  late String _name;
  late String _category;
  late UnitType _unitType;
  late double _amount;
  late String _unit;
  late double _cost;
  String? _notes;
  DateTime? _expirationDate;

  final List<String> _categories = ['Juice', 'Sugar', 'Additive', 'Yeast', 'Other'];

  final List<String> _units = [
    'grams', 'ml', 'oz', 'tsp', 'tbsp', 'gallon', 'package'
  ];

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _name = item.name;
    _category = item.category;
    _unitType = item.unitType;
    _amount = item.amountInStock;
    _unit = item.unit;
    _cost = item.costPerUnit ?? 0;
    _notes = item.notes;
    _expirationDate = item.expirationDate;
  }

  void _pickExpirationDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expirationDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
    );
    if (picked != null) {
      setState(() => _expirationDate = picked);
    }
  }

  void _saveEdits() {
    if (_formKey.currentState?.validate() ?? false) {
      _formKey.currentState?.save();

      widget.item
        ..name = _name
        ..category = _category
        ..unitType = _unitType
        ..amountInStock = _amount
        ..unit = _unit
        ..costPerUnit = _cost
        ..notes = _notes
        ..expirationDate = _expirationDate;

      widget.item.save();

      Navigator.of(context).pop(true); // Return true for updated
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Inventory Item'),
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
                items: _categories
                    .map((cat) => DropdownMenuItem(value: cat, child: Text(cat)))
                    .toList(),
                onChanged: (val) => setState(() => _category = val!),
                decoration: const InputDecoration(labelText: 'Category'),
              ),
              DropdownButtonFormField<UnitType>(
                value: _unitType,
                items: UnitType.values
                    .map((type) => DropdownMenuItem(
                          value: type,
                          child: Text(type.name),
                        ))
                    .toList(),
                onChanged: (val) => setState(() => _unitType = val!),
                decoration: const InputDecoration(labelText: 'Unit Type'),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      initialValue: _amount.toString(),
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
                      items: _units
                          .map((unit) => DropdownMenuItem(value: unit, child: Text(unit)))
                          .toList(),
                      onChanged: (val) => setState(() => _unit = val!),
                      decoration: const InputDecoration(labelText: 'Unit'),
                    ),
                  ),
                ],
              ),
              TextFormField(
                initialValue: _cost.toStringAsFixed(2),
                decoration: const InputDecoration(labelText: 'Cost per Unit (\$)'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onSaved: (val) => _cost = double.tryParse(val ?? '0') ?? 0,
                validator: (val) => val == null || val.isEmpty ? 'Required' : null,
              ),
              TextFormField(
                initialValue: _notes,
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
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saveEdits,
          child: const Text('Save Changes'),
        ),
      ],
    );
  }
}
