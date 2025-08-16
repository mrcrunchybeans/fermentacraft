import 'package:flutter/material.dart';
import 'package:fermentacraft/models/inventory_item.dart';
import 'package:fermentacraft/models/unit_type.dart';
import 'package:fermentacraft/utils/unit_conversion.dart';
import 'package:intl/intl.dart';

class EditInventoryDialog extends StatefulWidget {
  final InventoryItem item;

  const EditInventoryDialog({super.key, required this.item});

  @override
  State<EditInventoryDialog> createState() => _EditInventoryDialogState();
}

class _EditInventoryDialogState extends State<EditInventoryDialog> {
  final _formKey = GlobalKey<FormState>();

  // --- Editable Properties ---
  late TextEditingController _nameController;
  late TextEditingController _notesController;
  late String _category;
  late String _unit;
  late UnitType _unitType;
  
  // --- Data for Dropdowns ---
  final List<String> _categories = ['Juice', 'Sugar', 'Additive', 'Yeast', 'Other'];
  late List<String> _unitOptions;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    
    // Initialize controllers for editable fields
    _nameController = TextEditingController(text: item.name);
    _notesController = TextEditingController(text: item.notes);
    _category = item.category;
    _unit = item.unit;
    _unitType = item.unitType;

    _unitOptions = UnitConversion.getUnitListFor(_unitType);
  }
  
  @override
  void dispose() {
    _nameController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _saveEdits() {
    if (_formKey.currentState?.validate() ?? false) {
      _formKey.currentState?.save();

      // Only save the properties that can be directly changed
      widget.item.name = _nameController.text.trim();
      widget.item.category = _category;
      widget.item.unit = _unit;
      widget.item.unitType = _unitType;
      widget.item.notes = _notesController.text.trim();
      
      widget.item.save();

      Navigator.of(context).pop(true);
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- Editable Fields ---
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (val) => val == null || val.isEmpty ? 'Required' : null,
              ),
              DropdownButtonFormField<String>(
                initialValue: _category,
                items: _categories
                    .map((cat) => DropdownMenuItem(value: cat, child: Text(cat)))
                    .toList(),
                onChanged: (val) => setState(() => _category = val!),
                decoration: const InputDecoration(labelText: 'Category'),
              ),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<UnitType>(
                      initialValue: _unitType,
                      items: UnitType.values
                          .map((type) => DropdownMenuItem(
                                value: type,
                                child: Text(type.name),
                              ))
                          .toList(),
                          onChanged: (val) => setState(() {
                            _unitType = val!;
                            _unitOptions = UnitConversion.getUnitListFor(_unitType);
                            if (!_unitOptions.contains(_unit)) {
                              _unit = _unitOptions.isNotEmpty ? _unitOptions.first : '';
                            }
                          }),
                      decoration: const InputDecoration(labelText: 'Unit Type'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _unit,
                      items: _unitOptions
                          .map((unit) => DropdownMenuItem(value: unit, child: Text(unit)))
                          .toList(),
                      onChanged: (val) => setState(() => _unit = val!),
                      decoration: const InputDecoration(labelText: 'Unit'),
                    ),
                  ),
                ],
              ),
              TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(labelText: 'Notes (optional)'),
              ),

              const Divider(height: 32),

              // --- Read-Only Calculated Fields ---
              Text(
                "Calculated from Purchase History:",
                style: Theme.of(context).textTheme.labelSmall
              ),
              const SizedBox(height: 8),
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text("Amount in Stock"),
                trailing: Text(widget.item.amountInStock.toStringAsFixed(2)),
              ),
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text("Avg. Cost per Unit"),
                trailing: Text(NumberFormat.simpleCurrency().format(widget.item.costPerUnit)),
              ),
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text("Earliest Expiration"),
                trailing: Text(widget.item.expirationDate != null
                  ? DateFormat.yMMMd().format(widget.item.expirationDate!)
                  : "N/A"
                ),
              ),
               Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  "To change amount, cost, or expiration, edit the entries in the 'Purchase History' tab.",
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade600)
                ),
              )
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
