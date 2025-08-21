// ignore_for_file: deprecated_member_use

import 'package:fermentacraft/widgets/show_paywall.dart';
import 'package:flutter/material.dart';
import 'package:fermentacraft/utils/inventory_item_extensions.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:fermentacraft/utils/snacks.dart';
import '../../models/inventory_item.dart';
import '../../widgets/add_inventory_dialog.dart';
import '../../widgets/edit_inventory_dialog.dart';
import '../../widgets/log_purchase_dialog.dart';
import '../inventory_item_detail_view.dart';
import '../../models/inventory_item_detail_model.dart';

// NEW: gating
import 'package:fermentacraft/services/feature_gate.dart';

import '../utils/boxes.dart';

// Sort options
enum SortOption { name, stock, expiration }
// Row menu actions
enum _InvAction { archiveToggle, delete }

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key});

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  final TextEditingController _searchController = TextEditingController();
  SortOption _sortOption = SortOption.name;

  // Store selection as strings so it doesn't matter whether Hive keys are int or String.
  final Set<String> _selectedItemKeys = <String>{};

  bool _showArchived = false;

  @override
  void initState() {
    super.initState();
    // Make sure the sidecar archive box is open so isArchived works.
    InventoryArchiveStore.ensureOpen().then((_) {
      if (mounted) setState(() {});
    });
  }

  // ---------- Navigation ----------

  void _showInventoryItemDetail(BuildContext context, InventoryItem item) {
    final isWideScreen = MediaQuery.of(context).size.width > 600;
    if (isWideScreen) {
      showDialog(
        context: context,
        builder: (_) => InventoryItemDetailDialog(item: item),
      );
    } else {
      InventoryItemDetailView.show(context, item.key);
    }
  }

  // ---------- Helpers ----------

  /// Resolve a box key (which could be int or String) from our stringified selection key.
  dynamic _resolveBoxKey(Box box, String stringKey) {
    for (final k in box.keys) {
      if (k.toString() == stringKey) return k;
    }
    // Fallback: attempt with the string itself
    return stringKey;
  }

  int _activeCount(Box<InventoryItem> box) =>
      box.values.where((i) => i.isArchived == false).length;

  void _upsell(BuildContext context, String reason) {
showPaywall(context);

  }

  // ---------- Bulk Delete ----------

  void _deleteSelectedItems(Box<InventoryItem> box) {
    for (final stringKey in _selectedItemKeys) {
      final dynKey = _resolveBoxKey(box, stringKey);
      box.delete(dynKey);
    }
    setState(() => _selectedItemKeys.clear());
  }

  // ---------- Archive / Delete helpers (single item) ----------

  Future<void> _toggleArchiveStatus(InventoryItem item) async {
    final isArchiving = !item.isArchived;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isArchiving ? 'Archive Item?' : 'Unarchive Item?'),
        content: Text(
          'Are you sure you want to ${isArchiving ? 'archive' : 'unarchive'} "${item.name}"?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text(isArchiving ? 'Archive' : 'Unarchive')),
        ],
      ),
    );
    if (confirmed == true) {
      item.isArchived = isArchiving; // sidecar flag
      await item.save();
      if (!mounted) return;
      snacks.show(
        SnackBar(content: Text(isArchiving ? 'Archived "${item.name}"' : 'Unarchived "${item.name}"')),
      );
      setState(() {});
    }
  }

  Future<void> _deleteItemWithUndo(InventoryItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Item?'),
        content: Text('This will permanently delete "${item.name}".'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

  final box = Hive.box<InventoryItem>(Boxes.inventory); // ✅ opened in setup
    final key = item.key;
    final backup = item;

    await item.delete();

    if (!mounted) return;
    snacks.show(
      SnackBar(
        content: Text('Deleted "${backup.name}"'),
        action: SnackBarAction(
          label: 'UNDO',
          onPressed: () async {
            try {
              await box.put(key, backup);
            } catch (_) {
              await box.add(backup);
            }
            if (!mounted) return;
            snacks.show(const SnackBar(content: Text('Item restored')));
          },
        ),
        duration: const Duration(seconds: 6),
      ),
    );
  }

  PopupMenuButton<_InvAction> _moreMenu(InventoryItem item) {
    return PopupMenuButton<_InvAction>(
      onSelected: (a) {
        switch (a) {
          case _InvAction.archiveToggle:
            _toggleArchiveStatus(item);
            break;
          case _InvAction.delete:
            _deleteItemWithUndo(item);
            break;
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _InvAction.archiveToggle,
          child: Text(item.isArchived ? 'Unarchive' : 'Archive'),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: _InvAction.delete,
          child: Row(
            children: const [
              Icon(Icons.delete_outline),
              SizedBox(width: 8),
              Text('Delete'),
            ],
          ),
        ),
      ],
    );
  }

  // Swipe background UI
  Widget _swipeBg(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Alignment alignment,
    bool danger = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    final color = danger ? cs.error : cs.primary;
    final onColor = danger ? cs.onError : cs.onPrimary;
    return Container(
      color: color.withOpacity(0.90),
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: onColor),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: onColor, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final inventoryBox = Hive.box<InventoryItem>('inventory');
    final fg = context.watch<FeatureGate>();

    return Scaffold(
      appBar: AppBar(
        title: Text(_showArchived ? 'Archived Inventory' : 'Inventory'),
        actions: [
          if (_selectedItemKeys.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete),
              tooltip: 'Delete Selected',
              onPressed: () => _deleteSelectedItems(inventoryBox),
            ),
          IconButton(
            icon: Icon(_showArchived ? Icons.inventory_2_outlined : Icons.archive_outlined),
            tooltip: _showArchived ? 'View Active Items' : 'View Archived Items',
            onPressed: () => setState(() => _showArchived = !_showArchived),
          ),
        ],
      ),

      // ✅ One listener drives banner + list
      body: ValueListenableBuilder<Box<InventoryItem>>(
        valueListenable: inventoryBox.listenable(),
        builder: (context, box, _) {
          final activeCount = _activeCount(box);
          final atLimit = !fg.isPremium && activeCount >= fg.inventoryLimitFree;

          return Column(
            children: [
              // Small limit banner for Free users on Active view
              if (!_showArchived && !fg.isPremium)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.teal.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('Free plan: $activeCount / ${fg.inventoryLimitFree} active items'),
                      ),
                      if (atLimit)
                        TextButton(
                          onPressed: () => _upsell(context, 'Inventory limit reached (Free)'),
                          child: const Text('Upgrade'),
                        ),
                    ],
                  ),
                ),

              // Search + sort row
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: const InputDecoration(
                          hintText: "Search by name...",
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 12),
                    DropdownButton<SortOption>(
                      value: _sortOption,
                      onChanged: (value) => setState(() => _sortOption = value!),
                      items: const [
                        DropdownMenuItem(value: SortOption.name, child: Text("Sort: Name")),
                        DropdownMenuItem(value: SortOption.stock, child: Text("Sort: Stock Level")),
                        DropdownMenuItem(value: SortOption.expiration, child: Text("Sort: Expiration")),
                      ],
                    ),
                  ],
                ),
              ),

              // The list itself
              Expanded(child: _buildInventoryList(box)),
            ],
          );
        },
      ),

      // ✅ FAB listens too; disabled & tooltip when at limit
floatingActionButton: ValueListenableBuilder<Box<InventoryItem>>(
  valueListenable: Hive.box<InventoryItem>('inventory').listenable(),
  builder: (context, box, _) {
    final fg = context.watch<FeatureGate>();
    final activeCount = box.values.where((i) => !i.isArchived).length;
    final atLimit = !fg.isPremium && activeCount >= fg.inventoryLimitFree;

    return FloatingActionButton(
      heroTag: 'addInventoryFab',
      onPressed: () async {
        if (atLimit) {
          _upsell(context, 'Inventory limit reached (Free)');
          return;
        }
        await showDialog(
          context: context,
          builder: (_) => const AddInventoryDialog(),
        );
      },
      tooltip: atLimit
          ? 'Free limit reached (${fg.inventoryLimitFree}). Tap to upgrade.'
          : 'Add Inventory Item',
      child: const Icon(Icons.add),
    );
  },
),

    );
  }

  // ---------- List builder (kept separate for readability) ----------

  Widget _buildInventoryList(Box<InventoryItem> box) {
    if (box.values.isEmpty) {
      return Center(
        child: Text(_showArchived ? "No archived items." : "No inventory items yet."),
      );
    }

    final searchTerm = _searchController.text.toLowerCase();

    final List<InventoryItem> filteredItems = box.values
        .where((item) =>
            item.isArchived == _showArchived &&
            item.name.toLowerCase().contains(searchTerm))
        .toList();

    if (filteredItems.isEmpty) {
      return Center(
        child: Text(_showArchived ? "No archived items." : "No items match your filter."),
      );
    }

    // Sorting (includes expiration)
    filteredItems.sort((a, b) {
      switch (_sortOption) {
        case SortOption.name:
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case SortOption.stock:
          return b.amountInStock.compareTo(a.amountInStock);
        case SortOption.expiration:
          final aDate = a.expirationDate;
          final bDate = b.expirationDate;
          if (aDate == null && bDate == null) return 0;
          if (aDate == null) return 1; // Items without dates go last
          if (bDate == null) return -1;
          return aDate.compareTo(bDate);
      }
    });

    // Group by category
    final Map<String, List<InventoryItem>> grouped = {};
    for (var item in filteredItems) {
      grouped.putIfAbsent(item.category, () => []).add(item);
    }
    final sortedCats = grouped.keys.toList()..sort();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: sortedCats.map((cat) {
        final items = grouped[cat]!;
        return ExpansionTile(
          initiallyExpanded: true,
          title: Text(cat, style: Theme.of(context).textTheme.titleLarge),
          children: items.map((item) {
            final itemKey = item.key.toString(); // normalize key
            final isSelected = _selectedItemKeys.contains(itemKey);

            // Expiration color/text
            final now = DateTime.now();
            final twoWeeksFromNow = now.add(const Duration(days: 14));
            Color? expirationColor;
            String? expirationText;

            if (item.expirationDate != null) {
              final date = item.expirationDate!;
              expirationText = 'Expires: ${DateFormat.yMMMd().format(date)}';
              if (date.isBefore(now)) {
                expirationColor = Colors.red; // Expired
              } else if (date.isBefore(twoWeeksFromNow)) {
                expirationColor = Colors.orange; // Soon
              }
            }

            return Dismissible(
              key: ValueKey<String>(itemKey),
              background: _swipeBg(
                context,
                icon: item.isArchived ? Icons.unarchive : Icons.archive_outlined,
                label: item.isArchived ? 'Unarchive' : 'Archive',
                alignment: Alignment.centerLeft,
              ),
              secondaryBackground: _swipeBg(
                context,
                icon: Icons.delete_outline,
                label: 'Delete',
                alignment: Alignment.centerRight,
                danger: true,
              ),
              direction: DismissDirection.horizontal,
              confirmDismiss: (direction) async {
                if (direction == DismissDirection.startToEnd) {
                  await _toggleArchiveStatus(item);
                  return false; // handled via rebuild
                } else {
                  await _deleteItemWithUndo(item);
                  return false; // handled via snackbar/undo
                }
              },
              child: Card(
                child: ListTile(
                  leading: Checkbox(
                    value: isSelected,
                    onChanged: (selected) {
                      setState(() {
                        if (selected == true) {
                          _selectedItemKeys.add(itemKey);
                        } else {
                          _selectedItemKeys.remove(itemKey);
                        }
                      });
                    },
                  ),
                  onTap: () => _showInventoryItemDetail(context, item),
                  title: Text(item.name),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("${item.amountInStock.toStringAsFixed(2)} ${item.getDisplayUnit(item.amountInStock)}"),
                      if (expirationText != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Text(
                            expirationText,
                            style: TextStyle(color: expirationColor, fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.attach_money),
                        tooltip: 'Log Purchase',
                        onPressed: () async {
                          await showDialog(context: context, builder: (_) => LogPurchaseDialog(item: item));
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit),
                        tooltip: 'Edit Item',
                        onPressed: () async {
                          await showDialog(context: context, builder: (_) => EditInventoryDialog(item: item));
                        },
                      ),
                      _moreMenu(item),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        );
      }).toList(),
    );
  }
}
