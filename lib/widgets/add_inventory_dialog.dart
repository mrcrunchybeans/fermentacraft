import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/inventory_item.dart';
import '../models/unit_type.dart';
import '../utils/unit_conversion.dart'; // Add this import

class AddInventoryDialog extends StatefulWidget {
  const AddInventoryDialog({super.key});

  @override
  State<AddInventoryDialog> createState() => _AddInventoryDialogState();
}

class _AddInventoryDialogState extends State<AddInventoryDialog> {
  UnitType _unitType = UnitType.mass;
  final _formKey = GlobalKey<FormState>();
  String _name = '';
  String _category = 'Juice';
  double _amount = 0;
  String _unit = 'grams';
  double _cost = 0;
  String? _notes;

  final List<String> _categories = [
    'Juice',
    'Sugar',
    'Additive',
    'Yeast',
    'Other',
  ];

  final List<String> _units = [
    'grams',
    'mL',
    'fl oz',
    'cup',
    'oz',
    'tsp',
    'tbsp',
    'gallon',
    'package',
  ];

  void _saveInventoryItem() {
    if (_formKey.currentState?.validate() ?? false) {
      _formKey.currentState?.save();

final newItem = InventoryItem(
  name: _name,
  amountInStock: _amount,
  unit: _unit,
  unitType: _unitType, // ✅ use this instead of inferredType
  costPerUnit: _cost,
  notes: _notes,
  category: _category,
);


      Hive.box<InventoryItem>('inventory').add(newItem);
      Navigator.of(context).pop();
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
  items: _units
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
  decoration: const InputDecoration(labelText: 'Unit'),
),

                  ),
                ],
              ),
              TextFormField(
                decoration: const InputDecoration(labelText: 'Cost per Unit (\$)'),
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
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          child: const Text('Cancel'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        ElevatedButton(
          onPressed: _saveInventoryItem,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
