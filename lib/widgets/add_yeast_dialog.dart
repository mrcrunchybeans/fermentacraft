// lib/widgets/add_yeast_dialog.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:fermentacraft/utils/snacks.dart';
import '../models/settings_model.dart';          // <- for currencySymbol
import '../services/yeast_store.dart';

class AddYeastDialog extends StatefulWidget {
  final Map<String, dynamic>? existing;
  final Function(Map<String, dynamic>) onAdd;
  final Function(Map<String, dynamic>)? onAddToInventory;

  const AddYeastDialog({
    super.key,
    this.existing,
    required this.onAdd,
    this.onAddToInventory,
  });

  @override
  State<AddYeastDialog> createState() => _AddYeastDialogState();
}

class _AddYeastDialogState extends State<AddYeastDialog> {
  static const String _kCustomOption = '__custom__';

  // Built-ins
  static const List<String> _builtInYeasts = [
    'Lalvin EC-1118',
    'Red Star Premier Blanc',
    'Safale US-05',
    'Wyeast 1056 American Ale',
    'Lalvin D-47',
    'Lalvin K1-V1116',
    'Nottingham Ale Yeast',
    'WLP001 California Ale',
    'Mangrove Jack’s M02 Cider',
  ];
  late final Set<String> _builtInsLower =
      _builtInYeasts.map((e) => e.toLowerCase()).toSet();

  // User-saved list
  List<String> _myYeasts = [];

  // UI state
  String _dropdownValue = _builtInYeasts.first; // or _kCustomOption
  bool _isCustom = false;
  bool _rememberCustom = true;
  bool _saving = false;

  final _formKey = GlobalKey<FormState>();
  final TextEditingController _customNameController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _costController = TextEditingController();

  DateTime purchaseDate = DateTime.now();
  DateTime? expirationDate;
  String unit = 'packets';

  @override
  void initState() {
    super.initState();
    _refreshMyYeasts();

    // Seed from existing
    if (widget.existing != null) {
      final y = widget.existing!;
      final name = (y['name'] as String?)?.trim() ?? '';

      final knownLower = {
        ..._builtInsLower,
        ..._myYeasts.map((e) => e.toLowerCase()),
      };

      if (name.isNotEmpty && knownLower.contains(name.toLowerCase())) {
        _dropdownValue = _caseMatch(name, [..._builtInYeasts, ..._myYeasts]);
        _isCustom = false;
      } else {
        _dropdownValue = _kCustomOption;
        _isCustom = true;
        _customNameController.text = name;
      }

      _amountController.text = (y['amount']?.toString() ?? '');
      unit = y['unit'] as String? ?? 'packets';
      _costController.text = (y['cost']?.toString() ?? '');

      final pDate = y['purchaseDate'];
      if (pDate is String) {
        purchaseDate = DateTime.tryParse(pDate) ?? DateTime.now();
      } else if (pDate is DateTime) {
        purchaseDate = pDate;
      }

      final eDate = y['expirationDate'];
      if (eDate is String) {
        expirationDate = DateTime.tryParse(eDate);
      } else if (eDate is DateTime) {
        expirationDate = eDate;
      }
    }
  }

  @override
  void dispose() {
    _customNameController.dispose();
    _amountController.dispose();
    _costController.dispose();
    super.dispose();
  }

  // ───────── helpers ─────────

  void _refreshMyYeasts() {
    _myYeasts = YeastStore.list();
    if (mounted) setState(() {});
  }

  String _caseMatch(String value, List<String> pool) {
    final idx = pool.indexWhere((e) => e.toLowerCase() == value.toLowerCase());
    return idx >= 0 ? pool[idx] : value;
  }

  String _effectiveName() {
    if (_isCustom) {
      final n = _customNameController.text.trim();
      return n.isEmpty ? 'Custom Yeast' : n;
    }
    return _dropdownValue;
  }

  Map<String, dynamic> _buildYeastEntry() {
    final amount = double.tryParse(_amountController.text.trim()) ?? 0.0;
    final cost = double.tryParse(_costController.text.trim()) ?? 0.0;
    return {
      'name': _effectiveName(),
      'amount': amount,
      'unit': unit,
      'cost': cost,
      'purchaseDate': purchaseDate,
      'expirationDate': expirationDate,
    };
  }

  List<DropdownMenuItem<String>> _menuItems() {
    final combined = [
      ..._builtInYeasts,
      ..._myYeasts.where((m) => !_builtInsLower.contains(m.toLowerCase())),
    ];
    return [
      ...combined.map((y) => DropdownMenuItem<String>(value: y, child: Text(y))),
      const DropdownMenuItem<String>(
        value: _kCustomOption,
        child: Text('Other (Custom)'),
      ),
    ];
  }

  Future<void> _maybeRememberCustom(String name) async {
    if (!(_isCustom && _rememberCustom)) return;
    try {
      await YeastStore.add(name);
    } catch (_) {
      if (mounted) {
        snacks.show(
          const SnackBar(
            content: Text('Saved without remembering (settings not opened).'),
          ),
        );
      }
    } finally {
      _refreshMyYeasts();
    }
  }

  Future<void> _closeDialog(Object? result) async {
    final rootNav = Navigator.of(context, rootNavigator: true);
    if (rootNav.canPop()) {
      rootNav.pop(result);
      return;
    }
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop(result);
    }
  }

  Future<void> _handleAdd({required bool toInventory}) async {
    if (_saving) return;

    final valid = _formKey.currentState?.validate() ?? true;
    if (!valid) {
      if (_isCustom && _customNameController.text.trim().isEmpty) {
        snacks.show(
          const SnackBar(content: Text('Please enter a custom yeast name.')),
        );
      }
      return;
    }

    setState(() => _saving = true);
    FocusScope.of(context).unfocus();

    try {
      final yeast = _buildYeastEntry();
      await _maybeRememberCustom(yeast['name'] as String);

      if (toInventory && widget.onAddToInventory != null) {
        await Future.sync(() => widget.onAddToInventory!(yeast));
      } else {
        await Future.sync(() => widget.onAdd(yeast));
      }

      await _closeDialog(yeast);
    } catch (e, st) {
      debugPrint('AddYeastDialog _handleAdd error: $e\n$st');
      if (!mounted) return;
      snacks.show(
        SnackBar(content: Text('Could not add yeast: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _renameMyYeast(String oldName) async {
    final controller = TextEditingController(text: oldName);
    final newName = await showDialog<String?>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Rename yeast'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'New name',
            hintText: 'e.g., Lalvin 71B-1122',
          ),
          onSubmitted: (_) => Navigator.pop(context, controller.text.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (newName == null || newName.isEmpty) return;

    final dupe = _myYeasts.any((e) => e.toLowerCase() == newName.toLowerCase());
    if (dupe && newName.toLowerCase() != oldName.toLowerCase()) {
      if (!mounted) return;
      snacks.show(
        SnackBar(content: Text('A custom yeast named "$newName" already exists.')),
      );
      return;
    }

    await YeastStore.rename(oldName, newName);
    _refreshMyYeasts();

    if (!_isCustom && _dropdownValue.toLowerCase() == oldName.toLowerCase()) {
      setState(() => _dropdownValue = newName);
    } else if (_isCustom &&
        _customNameController.text.trim().toLowerCase() == oldName.toLowerCase()) {
      _customNameController.text = newName;
    }
  }

  Future<void> _deleteMyYeast(String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete yeast'),
        content: Text('Remove "$name" from My Yeasts?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    await YeastStore.remove(name);
    _refreshMyYeasts();

    if (!_isCustom && _dropdownValue.toLowerCase() == name.toLowerCase()) {
      setState(() => _dropdownValue = _builtInYeasts.first);
    }
  }

  Future<void> _showManageMyYeasts() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        final myList = _myYeasts.toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                title: Text('Manage My Yeasts', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('Rename or remove your saved yeast strains.'),
              ),
              if (myList.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text("You haven't saved any custom yeasts yet."),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: myList.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final name = myList[i];
                      return ListTile(
                        title: Text(name),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Rename',
                              icon: const Icon(Icons.edit),
                              onPressed: () async {
                                Navigator.of(context).pop(); // close sheet
                                await _renameMyYeast(name);
                                await _showManageMyYeasts(); // reopen to refresh
                              },
                            ),
                            IconButton(
                              tooltip: 'Delete',
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () async {
                                Navigator.of(context).pop();
                                await _deleteMyYeast(name);
                                await _showManageMyYeasts();
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // ───────── UI ─────────

  @override
  Widget build(BuildContext context) {
    final bool isEditing = widget.existing != null;
    final symbol = context.watch<SettingsModel>().currencySymbol;

    // simple live preview for unit cost
    double? unitCost;
    final amt = double.tryParse(_amountController.text) ?? 0;
    final cost = double.tryParse(_costController.text) ?? 0;
    if (amt > 0 && cost > 0) unitCost = cost / amt;

    return AlertDialog(
      title: Text(isEditing ? "Edit Yeast" : "Add Yeast"),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _isCustom ? _kCustomOption : _dropdownValue,
                items: _menuItems(),
                onChanged: (val) {
                  if (val == null) return;
                  setState(() {
                    if (val == _kCustomOption) {
                      _isCustom = true;
                      _rememberCustom = true;
                      _dropdownValue = _builtInYeasts.first;
                    } else {
                      _isCustom = false;
                      _dropdownValue = val;
                    }
                  });
                },
                decoration: InputDecoration(
                  labelText: 'Yeast',
                  suffixIcon: IconButton(
                    tooltip: 'Manage My Yeasts',
                    icon: const Icon(Icons.settings),
                    onPressed: _showManageMyYeasts,
                  ),
                ),
              ),

              if (_isCustom) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _customNameController,
                  decoration: const InputDecoration(
                    labelText: "Custom Yeast Name",
                    hintText: "e.g., Lalvin 71B-1122",
                  ),
                  textCapitalization: TextCapitalization.words,
                  validator: (_) => _isCustom && _customNameController.text.trim().isEmpty
                      ? 'Please enter a name.'
                      : null,
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _rememberCustom,
                  onChanged: (v) => setState(() => _rememberCustom = (v ?? true)),
                  title: const Text("Remember this yeast for next time"),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],

              const SizedBox(height: 12),
              TextFormField(
                controller: _amountController,
                decoration: const InputDecoration(labelText: "Amount"),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}), // refresh unit-cost preview
              ),

              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: unit,
                items: const ['grams', 'packets']
                    .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                    .toList(),
                onChanged: (val) {
                  if (val != null) setState(() => unit = val);
                },
                decoration: const InputDecoration(labelText: "Unit"),
              ),

              const Divider(height: 24),

              TextFormField(
                controller: _costController,
                decoration: InputDecoration(
                  labelText: 'Total Cost ($symbol)',
                  prefixText: '$symbol ',
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}), // refresh unit-cost preview
              ),

              const SizedBox(height: 6),
              if (unitCost != null)
                Text(
                  "Cost per $unit: $symbol${unitCost.toStringAsFixed(2)}",
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),

              const SizedBox(height: 12),
              Row(
                children: [
                  Text("Purchase: ${DateFormat.yMMMd().format(purchaseDate)}"),
                  const Spacer(),
                  TextButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: purchaseDate,
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        setState(() => purchaseDate = picked);
                      }
                    },
                    child: const Text("Change"),
                  ),
                ],
              ),

              Row(
                children: [
                  Text(
                    expirationDate == null
                        ? "Expiration: Not set"
                        : "Expires: ${DateFormat.yMMMd().format(expirationDate!)}",
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: expirationDate ?? DateTime.now().add(const Duration(days: 365)),
                        firstDate: DateTime.now(),
                        lastDate: DateTime(2040),
                      );
                      if (picked != null) {
                        setState(() => expirationDate = picked);
                      }
                    },
                    child: const Text("Set"),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (widget.onAddToInventory != null)
          TextButton(
            onPressed: _saving ? null : () => _handleAdd(toInventory: true),
            child: const Text("Add to Inventory"),
          ),
        TextButton(
          onPressed: _saving ? null : () => _handleAdd(toInventory: false),
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(isEditing ? "Save Changes" : "Add"),
        ),
      ],
    );
  }
}
