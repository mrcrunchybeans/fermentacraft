// lib/widgets/add_inventory_dialog.dart
import 'package:collection/collection.dart';
import 'package:fermentacraft/utils/inventory_item_extensions.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/inventory_item.dart';
import '../models/purchase_transaction.dart';
import '../models/unit_type.dart';
import '../models/settings_model.dart';
import '../services/feature_gate.dart';
import '../utils/boxes.dart';
import '../utils/unit_conversion.dart';
import '../utils/units.dart';
import '../widgets/show_paywall.dart';

class AddInventoryDialog extends StatefulWidget {
  final Map<String, dynamic>? initialData;
  const AddInventoryDialog({super.key, this.initialData});

  @override
  State<AddInventoryDialog> createState() => _AddInventoryDialogState();
}

class _AddInventoryDialogState extends State<AddInventoryDialog> {
  final _formKey = GlobalKey<FormState>();
  final _uuid = const Uuid();
  bool _saving = false;

  String _name = '';
  String _category = 'Juice';
  double _amount = 0;
  String _unit = 'g'; // canonical default
  double _cost = 0;
  String? _notes;
  UnitType _unitType = UnitType.mass;
  DateTime? _expirationDate;

  static const List<String> _categories = ['Juice', 'Sugar', 'Additive', 'Yeast', 'Other'];

  @override
  void initState() {
    super.initState();

    _unit = normalizeUnit(widget.initialData?['unit'] as String?);
    _unitType = inferUnitType(_unit);

    if (widget.initialData != null) {
      _name = (widget.initialData!['name'] ?? '').toString();
      final inputCategory = widget.initialData!['category'];
      if (inputCategory != null && _categories.contains(inputCategory)) {
        _category = inputCategory;
      }
    }
  }

  /// Find the Hive key for an InventoryItem we already pulled from the box.
  dynamic _findKeyForItem(Box<InventoryItem> box, InventoryItem item) {
    // 1) Prefer stable id key
    if (box.containsKey(item.id)) return item.id;

    // 2) Identity match (same instance)
    final kByIdentity = box.keys.firstWhereOrNull((k) => identical(box.get(k), item));
    if (kByIdentity != null) return kByIdentity;

    // 3) Match by id on stored values
    final kById = box.keys.firstWhereOrNull((k) {
      final v = box.get(k);
      return v is InventoryItem && v.id == item.id;
    });
    return kById; // may be null
  }

  Future<void> _saveInventoryItem() async {
    if (_saving) return;
    setState(() => _saving = true);

    try {
      // Validate form
      if (!(_formKey.currentState?.validate() ?? false)) {
        setState(() => _saving = false);
        return;
      }
      _formKey.currentState?.save();

      final box = Hive.box<InventoryItem>(Boxes.inventory);

      final transaction = PurchaseTransaction(
        date: DateTime.now(),
        amount: _amount,
        cost: _cost, // total cost for this purchase
        expirationDate: _expirationDate,
      );

      // Merge by case-insensitive name
      final existingItem = box.values.firstWhereOrNull(
        (i) => i.name.toLowerCase() == _name.toLowerCase(),
      );

      // Gate only on *new* items (merges allowed on Free)
      if (existingItem == null) {
        final fg = FeatureGate.instance; // ✅ singleton, not Provider
        final activeCount = box.values.where((i) => !i.isArchived).length;
        final atLimit = !fg.isPremium && activeCount >= fg.inventoryLimitFree;

        if (atLimit) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Free limit reached (${fg.inventoryLimitFree}). Upgrade to add more.'),
              duration: const Duration(seconds: 3),
            ),
          );
          await showPaywall(context);
          if (!mounted) return;

          // If still not premium after paywall, stop
          if (!FeatureGate.instance.isPremium) {
            setState(() => _saving = false);
            return;
          }
        }
      }

      if (existingItem != null) {
        // ---- MERGE PATH ----
        existingItem.addPurchase(transaction);

        final key = _findKeyForItem(box, existingItem);
        if (key != null) {
          await box.put(key, existingItem);
        } else {
          // Fallback: add if we truly can't locate the original key
          await box.add(existingItem);
        }
      } else {
        // ---- CREATE PATH ----
        final item = InventoryItem(
          id: _uuid.v4(),
          name: _name.trim(),
          unit: _unit,
          unitType: _unitType,
          notes: _notes,
          category: _category,
          purchaseHistory: [transaction],
        );

        // Support both key modes: string (stable id) or auto-int
        final usesStringKeys = box.isEmpty ? true : box.keys.first is String;
        if (usesStringKeys) {
          await box.put(item.id, item); // stable id key
        } else {
          await box.add(item); // auto-increment key
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inventory saved')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
      setState(() => _saving = false);
    }
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
    // currency symbol for labels & prefixes
    final symbol = context.watch<SettingsModel>().currencySymbol;

    // live preview of unit cost if the user entered both amount & cost
    double? unitCostPreview;
    if (_amount > 0 && _cost > 0) {
      unitCostPreview = _cost / _amount;
    }

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
                      onChanged: (v) {
                        final parsed = double.tryParse((v).trim());
                        setState(() => _amount = parsed ?? 0);
                      },
                      onSaved: (val) => _amount = double.tryParse((val ?? '').trim()) ?? 0,
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) return 'Required';
                        return double.tryParse(val.trim()) == null ? 'Invalid number' : null;
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: kCanonicalUnits.contains(_unit) ? _unit : kCanonicalUnits.first,
                      items: kCanonicalUnits
                          .map((unit) => DropdownMenuItem(value: unit, child: Text(unit)))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _unit = val;
                            _unitType = inferUnitType(val);
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

              // Total Cost (with currency symbol)
              TextFormField(
                decoration: InputDecoration(
                  labelText: 'Total Cost ($symbol) — optional',
                  prefixText: '$symbol ',
                  contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (v) {
                  final parsed = double.tryParse((v).trim());
                  setState(() => _cost = parsed ?? 0);
                },
                onSaved: (val) {
                  final v = double.tryParse((val ?? '').trim());
                  _cost = (v != null && v >= 0) ? v : 0;
                },
                validator: (val) {
                  if (val == null || val.trim().isEmpty) return null; // optional
                  return double.tryParse(val.trim()) == null ? 'Invalid number' : null;
                },
              ),
              if (unitCostPreview != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '≈ $symbol${unitCostPreview.toStringAsFixed(2)} per $_unit',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
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
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _saveInventoryItem,
          child: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }
}
