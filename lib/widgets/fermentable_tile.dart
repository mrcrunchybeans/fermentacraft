// lib/widgets/fermentable_tile.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:fermentacraft/models/enums.dart';
import 'package:fermentacraft/models/settings_model.dart';
import 'package:fermentacraft/services/usda_service.dart';
import 'package:fermentacraft/controllers/recipe_builder_controller.dart';
import 'package:fermentacraft/models/inventory_item.dart';
import 'package:fermentacraft/utils/boxes.dart';
import 'package:hive_flutter/hive_flutter.dart';

class FermentableTile extends StatefulWidget {
  final int index;
  const FermentableTile({super.key, required this.index});
  

  @override
  State<FermentableTile> createState() => _FermentableTileState();
}

enum _GravityMode { brix, sg }

class _FermentableTileState extends State<FermentableTile> {
  // Controllers

  late final TextEditingController _nameCtrl;
  late final TextEditingController _brixCtrl;
  late final TextEditingController _sgCtrl;
  late final TextEditingController _wtCtrl;
  late final TextEditingController _volCtrl;

  // Focus
  late final FocusNode _nameFocus;
  late final FocusNode _wtFocus;
  late final FocusNode _volFocus;
  late final FocusNode _brixFocus;
  late final FocusNode _sgFocus;

  // Prevent feedback loops while we sync programmatically.
  bool _programmaticSet = false;

  // Default mobile-first units
  late WeightUnit _weightUnit;
  late VolumeUiUnit _volumeUnit;

  // Gravity UI state
  _GravityMode _mode = _GravityMode.brix;

  @override
  void initState() {
    super.initState();
    _nameFocus = FocusNode();
    _wtFocus = FocusNode();
    _volFocus = FocusNode();
    _brixFocus = FocusNode();
    _sgFocus = FocusNode();

    final ctrl = context.read<RecipeBuilderController>();
    final line = (widget.index >= 0 && widget.index < ctrl.fermentables.length)
        ? ctrl.fermentables[widget.index]
        : null;

    _weightUnit = line?.userWeightUnit ?? WeightUnit.pounds;
    _volumeUnit = line?.userVolumeUnit ?? context.read<SettingsModel>().volumeUnit;

    _nameCtrl = TextEditingController(text: line?.name ?? '');
    _brixCtrl =
        TextEditingController(text: line?.brix?.toStringAsFixed(1) ?? '');
    _sgCtrl =
        TextEditingController(text: line?.density?.toStringAsFixed(3) ?? '');
    _wtCtrl = TextEditingController(
      text: (line?.weightG == null)
          ? ''
          : _trimTrailing(_weightUnit.fromGrams(line!.weightG!)),
    );
    _volCtrl = TextEditingController(
      text: (line?.volumeMl == null)
          ? ''
          : _trimTrailing(_volumeUnit.fromMl(line!.volumeMl!)),
    );

    // Prefer Brix for liquids, SG for non-liquids (feel free to invert)
    if (line != null && line.type.isLiquid) {
      _mode = _GravityMode.brix;
    } else {
      _mode = _GravityMode.sg;
    }

    // Add listeners
    _nameCtrl.addListener(() {
      if (_programmaticSet) return;
      final c = context.read<RecipeBuilderController>();
      if (!_inRange(c)) return;
      final current = c.fermentables[widget.index];
      c.updateFermentable(widget.index, current.copyWith(name: _nameCtrl.text));
    });

    // BRIX listener -> setBrixAt (will also set density & resync W<->V)
    _brixCtrl.addListener(() {
      if (_programmaticSet) return;
      final c = context.read<RecipeBuilderController>();
      if (!_inRange(c)) return;
      final v = double.tryParse(_brixCtrl.text.trim());
      if (v == null) return;
      c.setBrixAt(widget.index, v);
    });

    // SG listener -> setSgAt (accepts "1.045" or "1045")
    _sgCtrl.addListener(() {
      if (_programmaticSet) return;
      final c = context.read<RecipeBuilderController>();
      if (!_inRange(c)) return;
      final sg = _parseUserSg(_sgCtrl.text);
      if (sg == null) return;
      c.setSgAt(widget.index, sg);
    });

    // Weight
    _wtCtrl.addListener(() {
      if (_programmaticSet) return;
      final c = context.read<RecipeBuilderController>();
      if (!_inRange(c)) return;
      final cur = c.fermentables[widget.index];
      final val = double.tryParse(_wtCtrl.text);
      final grams = (val == null) ? null : _weightUnit.toGrams(val);
      c.updateFermentable(widget.index, cur.copyWith(weightG: grams));
    });

    // Volume
    _volCtrl.addListener(() {
      if (_programmaticSet) return;
      final c = context.read<RecipeBuilderController>();
      if (!_inRange(c)) return;
      final cur = c.fermentables[widget.index];
      final val = double.tryParse(_volCtrl.text);
      final ml = (val == null) ? null : _volumeUnit.toMl(val);
      c.updateFermentable(widget.index, cur.copyWith(volumeMl: ml));
    });
  }

  @override
  void dispose() {
    _nameFocus.dispose();
    _wtFocus.dispose();
    _volFocus.dispose();
    _brixFocus.dispose();
    _sgFocus.dispose();

    _nameCtrl.dispose();
    _brixCtrl.dispose();
    _sgCtrl.dispose();
    _wtCtrl.dispose();
    _volCtrl.dispose();
    super.dispose();
  }

  bool _inRange(RecipeBuilderController c) =>
      widget.index >= 0 && widget.index < c.fermentables.length;

  void _syncControllersFromModel(FermentableLine line) {
    _programmaticSet = true;

    if (!_nameFocus.hasFocus) {
      _setIfChanged(_nameCtrl, line.name);
    }
    if (!_wtFocus.hasFocus) {
      final g = line.weightG;
      final display =
          (g == null) ? '' : _trimTrailing(_weightUnit.fromGrams(g));
      _setIfChanged(_wtCtrl, display);
    }
    if (!_volFocus.hasFocus) {
      final ml = line.volumeMl;
      final display =
          (ml == null) ? '' : _trimTrailing(_volumeUnit.fromMl(ml));
      _setIfChanged(_volCtrl, display);
    }
    if (!_brixFocus.hasFocus) {
      _setIfChanged(_brixCtrl,
          (line.brix == null) ? '' : line.brix!.toStringAsFixed(1));
    }
    if (!_sgFocus.hasFocus) {
      _setIfChanged(_sgCtrl,
          (line.density == null) ? '' : line.density!.toStringAsFixed(3));
    }

    _programmaticSet = false;
  }

  String _trimTrailing(double v) {
    final s = v.toStringAsFixed(3);
    return s.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  void _setIfChanged(TextEditingController c, String next) {
    if (c.text == next) return;
    final atEnd = c.selection.baseOffset == c.text.length &&
        c.selection.extentOffset == c.text.length;
    c.text = next;
    if (atEnd) {
      c.selection = TextSelection.fromPosition(
          TextPosition(offset: next.length));
    }
  }

  // Accepts "1.045" or "1045"
  double? _parseUserSg(String raw) {
    final v = double.tryParse(raw.trim());
    if (v == null) return null;
    if (v >= 10 && v < 200) return v / 1000.0;
    if (v > 0.9 && v < 2.0) return v;
    return null;
  }

  // ==================== USDA Picker method ====================
  Future<void> _openUsdaPicker(FermentableLine line) async {
    final ctrl = context.read<RecipeBuilderController>();
    final String initialQuery = _nameCtrl.text.trim();

    final UsdaChoice? picked = await showModalBottomSheet<UsdaChoice>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) {
        String query = initialQuery;
        FermentableType? typeFilter = line.type;
        List<UsdaChoice> results = <UsdaChoice>[];
        bool loading = false;
        Timer? debounce;
        Key fieldKey = UniqueKey();

        Future<void> performSearch(StateSetter setState) async {
          final q = query.trim();
          if (q.isEmpty) {
            if (!sheetCtx.mounted) return;
            setState(() {
              loading = false;
              results = const [];
            });
            return;
          }
          setState(() => loading = true);
          List<UsdaChoice> filtered = const [];
          try {
            final raw = await ctrl.usda.searchFoods(q);
            filtered = (typeFilter == null)
                ? raw
                : raw.where((c) => c.type == typeFilter).toList(growable: false);
          } catch (_) {
            filtered = const [];
          }
          if (!sheetCtx.mounted) return;
          setState(() {
            results = filtered;
            loading = false;
          });
        }

        return StatefulBuilder(
          builder: (ctx, setState) {
            void onQueryChanged(String v) {
              query = v;
              debounce?.cancel();
              debounce = Timer(const Duration(milliseconds: 400), () {
                if (ctx.mounted) performSearch(setState);
              });
            }

            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!ctx.mounted) return;
              if (initialQuery.isNotEmpty && results.isEmpty && !loading) {
                performSearch(setState);
              }
            });

            final viewInsets = MediaQuery.of(ctx).viewInsets;
            final height = MediaQuery.of(ctx).size.height;

            return AnimatedPadding(
              duration: const Duration(milliseconds: 200),
              padding: EdgeInsets.only(bottom: viewInsets.bottom),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: height * 0.85),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 8),
                    Container(
                      width: 48,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade400,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              key: fieldKey,
                              initialValue: initialQuery,
                              autofocus: true,
                              textInputAction: TextInputAction.search,
                              onChanged: onQueryChanged,
                              onFieldSubmitted: (_) => performSearch(setState),
                              decoration: InputDecoration(
                                labelText: 'Search USDA',
                                hintText: 'e.g., honey, apple juice…',
                                prefixIcon: const Icon(Icons.search),
                                border: const OutlineInputBorder(),
                                isDense: true,
                                suffixIcon: query.isNotEmpty
                                    ? IconButton(
                                        tooltip: 'Clear',
                                        icon: const Icon(Icons.clear),
                                        onPressed: () {
                                          query = '';
                                          setState(() {
                                            results = const [];
                                            loading = false;
                                            fieldKey = UniqueKey();
                                          });
                                        },
                                      )
                                    : null,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 150,
                            child: DropdownButtonFormField<FermentableType?>(
                              value: typeFilter,
                              items: [
                                const DropdownMenuItem(
                                    value: null, child: Text('All types')),
                                ...FermentableType.values.map(
                                  (t) => DropdownMenuItem(
                                      value: t, child: Text(t.label)),
                                ),
                              ],
                              onChanged: (t) {
                                typeFilter = t;
                                performSearch(setState);
                              },
                              decoration: const InputDecoration(
                                labelText: 'Type',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: loading
                          ? const Center(child: CircularProgressIndicator())
                          : (query.trim().isEmpty
                              ? const _CenteredHint(
                                  icon: Icons.travel_explore,
                                  text: 'Enter a search term to begin',
                                )
                              : (results.isEmpty
                                  ? const _CenteredHint(
                                      icon: Icons.search_off,
                                      text: 'No results found',
                                    )
                                  : ListView.separated(
                                      padding:
                                          const EdgeInsets.only(bottom: 16),
                                      itemCount: results.length,
                                      separatorBuilder: (_, __) =>
                                          const Divider(height: 1),
                                      itemBuilder: (ctx2, i) {
                                        final o = results[i];
                                        return ListTile(
                                          dense: true,
                                          title: Text(o.name),
                                          subtitle: Text(o.type.label),
                                          trailing:
                                              const Icon(Icons.chevron_right),
                                          onTap: () {
                                            debounce?.cancel();
                                            Navigator.of(ctx).pop<UsdaChoice>(
                                                o);
                                          },
                                        );
                                      },
                                    ))),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (picked != null && mounted) {
      await ctrl.applyUsda(line.id, picked);
      _programmaticSet = true;
      _nameCtrl.text = picked.name;
      _programmaticSet = false;
    }
  }

  // ==================== Inventory Picker method ====================
  Future<void> _openInventoryPicker(FermentableLine line) async {
    final ctrl = context.read<RecipeBuilderController>();
    
    final InventoryItem? picked = await showModalBottomSheet<InventoryItem>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) {
        final box = Hive.box<InventoryItem>(Boxes.inventory);
        final items = box.values.where((i) {
          final c = i.category.toLowerCase();
          return c.contains('juice') || c.contains('sugar') || c.contains('honey') || c.contains('fruit');
        }).toList()..sort((a,b) => a.name.compareTo(b.name));

        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(sheetCtx).size.height * 0.85),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 16),
              Text('Select from Inventory', style: Theme.of(sheetCtx).textTheme.titleLarge),
              const SizedBox(height: 16),
              Expanded(
                child: items.isEmpty
                    ? const Center(child: Text('No fermentables in inventory.'))
                    : ListView.separated(
                        padding: const EdgeInsets.only(bottom: 16),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (ctx2, i) {
                          final o = items[i];
                          return ListTile(
                            dense: true,
                            title: Text(o.name),
                            subtitle: Text('${o.category} • ${o.amountInStock.toStringAsFixed(1)} ${o.unit} in stock'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              Navigator.of(sheetCtx).pop<InventoryItem>(o);
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );

    if (picked != null && mounted) {
      ctrl.seedFromInventoryItem(widget.index, picked);
      _programmaticSet = true;
      _nameCtrl.text = picked.name;
      _programmaticSet = false;
    }
  }

  // Helper methods to show pop-up menus for units
  void _showWeightUnitMenu(BuildContext context, Offset globalPosition) {
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(globalPosition, globalPosition),
      Offset.zero & overlay.size,
    );

    showMenu<WeightUnit>(
      context: context,
      position: position,
      items: WeightUnit.values
          .map((u) => PopupMenuItem(
                value: u,
                child: Text(u.label),
              ))
          .toList(),
    ).then((selectedUnit) {
      if (selectedUnit != null) {
        setState(() {
          _weightUnit = selectedUnit;
          final ctrl = context.read<RecipeBuilderController>();
          ctrl.setWeightUnitAt(widget.index, selectedUnit);
          final g = ctrl.fermentables[widget.index].weightG;
          if (g != null && !_wtFocus.hasFocus) {
            _programmaticSet = true;
            _wtCtrl.text = _trimTrailing(_weightUnit.fromGrams(g));
            _programmaticSet = false;
          }
        });
      }
    });
  }

  void _showVolumeUnitMenu(BuildContext context, Offset globalPosition) {
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(globalPosition, globalPosition),
      Offset.zero & overlay.size,
    );
    showMenu<VolumeUiUnit>(
      context: context,
      position: position,
      items: VolumeUiUnit.values
          .map((u) => PopupMenuItem(
                value: u,
                child: Text(u.label),
              ))
          .toList(),
    ).then((selectedUnit) {
      if (selectedUnit != null) {
        setState(() {
          _volumeUnit = selectedUnit;
          final ctrl = context.read<RecipeBuilderController>();
          ctrl.setVolumeUnitAt(widget.index, selectedUnit);
          final ml = ctrl.fermentables[widget.index].volumeMl;
          if (ml != null && !_volFocus.hasFocus) {
            _programmaticSet = true;
            _volCtrl.text = _trimTrailing(_volumeUnit.fromMl(ml));
            _programmaticSet = false;
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Selector<RecipeBuilderController, FermentableLine?>(
      selector: (_, c) => _inRange(c) ? c.fermentables[widget.index] : null,
      builder: (context, line, _) {
        if (line == null) return const SizedBox.shrink();
        _syncControllersFromModel(line);
        final isWater = line.type == FermentableType.water;

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Name + Type
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _nameCtrl,
                        focusNode: _nameFocus,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: 'Fermentable name',
                          hintText: 'e.g., Honey, Apple juice…',
                          border: const OutlineInputBorder(),
                          isDense: true,
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.inventory_2_outlined, size: 20),
                                tooltip: 'Select from Inventory',
                                onPressed: () => _openInventoryPicker(line),
                              ),
                              IconButton(
                                icon: const Icon(Icons.travel_explore, size: 20),
                                tooltip: 'Search USDA',
                                onPressed: () => _openUsdaPicker(line),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<FermentableType>(
                        value: line.type,
                        isDense: true,
                        decoration: const InputDecoration(
                          labelText: 'Type',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: FermentableType.values
                            .map((t) => DropdownMenuItem(
                                  value: t,
                                  child: Text(t.label),
                                ))
                            .toList(),
                        onChanged: (t) {
                          if (t == null) return;
                          context
                              .read<RecipeBuilderController>()
                              .updateFermentable(
                                  widget.index, line.copyWith(type: t));
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Weight + Volume
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _wtCtrl,
                        focusNode: _wtFocus,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'^\d*\.?\d*'))
                        ],
                        decoration: InputDecoration(
                          labelText: 'Weight',
                          border: const OutlineInputBorder(),
                          isDense: true,
                          contentPadding:
                              const EdgeInsets.fromLTRB(12, 10, 8, 10),
                          suffixIcon: SizedBox(
                            width: 65,
                            child: GestureDetector(
                              onTapDown: (details) => _showWeightUnitMenu(context, details.globalPosition),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    _weightUnit.label,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                                  ),
                                  Icon(
                                    Icons.arrow_drop_down,
                                    size: 18,
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _volCtrl,
                        focusNode: _volFocus,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'^\d*\.?\d*'))
                        ],
                        decoration: InputDecoration(
                          labelText: 'Volume',
                          border: const OutlineInputBorder(),
                          isDense: true,
                          contentPadding:
                              const EdgeInsets.fromLTRB(12, 10, 8, 10),
                          suffixIcon: SizedBox(
                            width: 65,
                            child: GestureDetector(
                              onTapDown: (details) => _showVolumeUnitMenu(context, details.globalPosition),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    _volumeUnit.label,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                                  ),
                                  Icon(
                                    Icons.arrow_drop_down,
                                    size: 18,
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Gravity: Brix <-> SG toggle + input + companion readout + density chip
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ToggleButtons(
                    isSelected: [
                      _mode == _GravityMode.brix,
                      _mode == _GravityMode.sg
                    ],
                    onPressed: isWater
                        ? null // disables the toggle when water is selected
                        : (i) {
                            setState(() {
                              _mode = (i == 0) ? _GravityMode.brix : _GravityMode.sg;
                        });
                      },
                      borderRadius: const BorderRadius.all(Radius.circular(8)),
                      children: const [
                        Padding(
                            padding: EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            child: Text('°Brix')),
                        Padding(
                            padding: EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            child: Text('SG')),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_mode == _GravityMode.brix)
 TextField(
  controller: _brixCtrl,
  focusNode: _brixFocus,
  enabled: !isWater, // <-- disable when water
  keyboardType: const TextInputType.numberWithOptions(decimal: true),
  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
  decoration: InputDecoration(
    labelText: 'Brix (°Bx)',
    hintText: 'e.g. 20.0',
    border: const OutlineInputBorder(),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    helperText: isWater ? 'Fixed at 0.0°Bx for Water' : null,
                        ),
                        onEditingComplete: () {
                          final v = double.tryParse(_brixCtrl.text);
                          _programmaticSet = true;
                          _brixCtrl.text = (v == null) ? '' : v.toStringAsFixed(1);
                          _programmaticSet = false;
                          _brixFocus.unfocus();
                        },
                      )
                    else
                      TextField(
                        controller: _sgCtrl,
                        focusNode: _sgFocus,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'^\d*\.?\d*'))
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Specific Gravity (SG)',
                          hintText: 'e.g. 1.045 or 1045',
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        onEditingComplete: () {
                          final sg = _parseUserSg(_sgCtrl.text);
                          _programmaticSet = true;
                          _sgCtrl.text =
                              (sg == null) ? '' : sg.toStringAsFixed(3);
                          _programmaticSet = false;
                          _sgFocus.unfocus();
                        },
                      ),
                    const SizedBox(height: 6),
                    Opacity(
                      opacity: 0.7,
                      child: Text(
                        _mode == _GravityMode.brix
                            ? 'SG: ${_sgCtrl.text.isEmpty ? '—' : _sgCtrl.text}'
                            : '°Bx: ${_brixCtrl.text.isEmpty ? '—' : _brixCtrl.text}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.opacity, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          'Density: ${line.density?.toStringAsFixed(3) ?? '—'} g/mL',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
if (line.type == FermentableType.fruit) ...[
  const SizedBox(height: 12),
  // Fruit estimation block
  Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<FruitCategory>(
              value: line.fruitCategory ?? FruitCategory.berries,
              isDense: true,
              decoration: const InputDecoration(
                labelText: 'Fruit category',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: FruitCategory.values
                  .map((c) => DropdownMenuItem(
                        value: c,
                        child: Text(c.label),
                      ))
                  .toList(),
              onChanged: (c) {
                if (c == null) return;
                context.read<RecipeBuilderController>()
                       .setFruitCategoryAt(widget.index, c);
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
              decoration: const InputDecoration(
                labelText: 'Yield (gal / lb)',
                hintText: 'e.g. 0.11',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              controller: TextEditingController(
                text: (line.fruitYieldGalPerLb
                        ?? (line.fruitCategory ?? FruitCategory.berries).defaultGalPerLb)
                    .toStringAsFixed(3),
              ),
              onChanged: (v) {
                final p = double.tryParse(v.trim());
                if (p == null) return;
                context.read<RecipeBuilderController>()
                       .setFruitYieldGalPerLbAt(widget.index, p);
              },
            ),
          ),
        ],
      ),
      const SizedBox(height: 6),
      // Read-only preview: estimated must volume from fruit (if user hasn't set Volume)
      Builder(
        builder: (_) {
          // recompute estimated if volume not explicitly set
          String estText;
          if (line.volumeMl != null && line.volumeMl! > 0) {
            estText = 'Using explicit volume: '
                      '${(line.volumeMl! / 3785.411784).toStringAsFixed(2)} gal';
          } else {
            final g = line.weightG ?? 0.0;
            final lbs = g / 453.59237;
            final galPerLb = (line.fruitYieldGalPerLb
                    ?? (line.fruitCategory ?? FruitCategory.berries).defaultGalPerLb)
                .clamp(0.05, 0.20);
            final estGal = lbs * galPerLb;
            estText = 'Estimated must volume from fruit: ${estGal.toStringAsFixed(2)} gal';
          }
          return Opacity(
            opacity: 0.8,
            child: Text(
              estText,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          );
        },
      ),
    ],
  ),
],

                // Footer
                Row(
                  children: [
                    Checkbox(
                      visualDensity: VisualDensity.compact,
                      value: line.syncWeightVolume,
                      onChanged: (v) => context
                          .read<RecipeBuilderController>()
                          .updateFermentable(widget.index,
                              line.copyWith(syncWeightVolume: v ?? true)),
                    ),
                    const Text('Sync Wt ↔ Vol'),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Remove',
                      icon: const Icon(Icons.delete_outline),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => context
                          .read<RecipeBuilderController>()
                          .removeFermentable(widget.index),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ----------------- Helper widgets only -----------------

class _CenteredHint extends StatelessWidget {
  final IconData icon;
  final String text;
  const _CenteredHint({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 56, color: Colors.grey.shade500),
            const SizedBox(height: 12),
            Text(text, style: TextStyle(color: Colors.grey.shade700)),
          ],
        ),
      ),
    );
  }
}
