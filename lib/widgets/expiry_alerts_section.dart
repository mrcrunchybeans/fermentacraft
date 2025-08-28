// lib/widgets/expiry_alerts_section.dart
// Plain-language copy; US phrasing.

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

import '../models/inventory_item.dart';
import '../models/purchase_transaction.dart';
import '../models/shopping_list_item.dart';
import '../utils/boxes.dart';
import '../utils/id.dart';
import '../utils/snacks.dart';
import '../inventory_item_detail_view.dart';
import '../pages/inventory_page.dart'; // InventoryPresetFilter + InventoryPage
import 'edit_purchase_dialog.dart';

class ExpiryAlertsSection extends StatelessWidget {
  const ExpiryAlertsSection({
    super.key,
    this.expiringWindowDays = 14,
    this.maxExpiredToShow = 6,
  });

  /// Items with 0..=expiringWindowDays appear under “Use soon”.
  final int expiringWindowDays;

  /// Cap how many expired rows we show inline.
  final int maxExpiredToShow;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box<InventoryItem>>(
      valueListenable: Hive.box<InventoryItem>(Boxes.inventory).listenable(),
      builder: (context, box, _) {
        final now = DateTime.now();
        final midnightNow = DateTime(now.year, now.month, now.day);

        final itemsWithExpiry = box.values.where((it) => it.expirationDate != null).toList();

        final useSoon = <InventoryItem>[];
        final expired = <InventoryItem>[];

        for (final it in itemsWithExpiry) {
          final expiry = DateTime(
            it.expirationDate!.year,
            it.expirationDate!.month,
            it.expirationDate!.day,
          );
          final daysLeft = expiry.difference(midnightNow).inDays;
          if (daysLeft >= 0 && daysLeft <= expiringWindowDays) {
            useSoon.add(it);
          } else if (daysLeft < 0) {
            expired.add(it);
          }
        }

        useSoon.sort((a, b) => a.expirationDate!.compareTo(b.expirationDate!));
        // Most recently expired first
        expired.sort((a, b) => b.expirationDate!.compareTo(a.expirationDate!));

        final hasAny = useSoon.isNotEmpty || expired.isNotEmpty;

        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.event_busy),
                    const SizedBox(width: 8),
                    Text('Use soon & expired', style: Theme.of(context).textTheme.titleLarge),
                    const Spacer(),
                    if (hasAny)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceVariant,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text('${useSoon.length + expired.length}'),
                      ),
                  ],
                ),
                const SizedBox(height: 12),

                const _Subheader('Use soon'),
                if (useSoon.isEmpty)
                  const _EmptyRow('Nothing coming due')
                else
                  ...useSoon.map((it) => _itemTile(context, it, isExpired: false)),

                const SizedBox(height: 12),

                const _Subheader('Expired'),
                if (expired.isEmpty)
                  const _EmptyRow('No expired items')
                else ...[
                  ...expired.take(maxExpiredToShow).map((it) => _itemTile(context, it, isExpired: true)),
                  if (expired.length > maxExpiredToShow)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const InventoryPage(
                                presetFilter: InventoryPresetFilter.expired,
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.list),
                        label: Text('Show all expired (${expired.length})'),
                      ),
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  static Widget _itemTile(BuildContext context, InventoryItem item, {required bool isExpired}) {
    final now = DateTime.now();
    final midnightNow = DateTime(now.year, now.month, now.day);
    final expiry = DateTime(item.expirationDate!.year, item.expirationDate!.month, item.expirationDate!.day);
    final days = expiry.difference(midnightNow).inDays;

    final subtitle = isExpired
        ? 'Expired ${days.abs()} day${days.abs() == 1 ? '' : 's'} ago'
        : (days == 0 ? 'Expires today' : 'In $days day${days == 1 ? '' : 's'}');

    final dateText = DateFormat.yMMMd().format(item.expirationDate!);

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        Icons.warning_amber_rounded,
        color: isExpired ? Colors.red : Theme.of(context).colorScheme.tertiary,
      ),
      title: Text(item.name),
      subtitle: Text(subtitle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(dateText),
          const SizedBox(width: 8),
          _overflowMenu(context, item, isExpired: isExpired),
        ],
      ),
      onTap: () => InventoryItemDetailView.show(context, item.key),
    );
  }

  static Widget _overflowMenu(BuildContext context, InventoryItem item, {required bool isExpired}) {
    return PopupMenuButton<_ExpirationAction>(
      onSelected: (a) async {
        switch (a) {
          case _ExpirationAction.addToShopping:
            await _addToShoppingList(item);
            snacks.text('Added “${item.name}” to the shopping list.');
            break;
          case _ExpirationAction.editDate:
            await _editExpiration(context, item);
            break;
          case _ExpirationAction.removeExpired:
            final written = await _writeOffExpiredStock(item);
            if (written.count == 0) {
              snacks.text('Nothing expired to remove for “${item.name}”.');
            } else {
              final unit = item.unit.isEmpty ? '' : ' ${item.unit}';
              snacks.text('Removed ${_fmt(written.amount)}$unit from ${written.count} purchase record${written.count == 1 ? '' : 's'}.');
            }
            break;
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: _ExpirationAction.addToShopping,
          child: ListTile(
            leading: Icon(Icons.add_shopping_cart_outlined),
            title: Text('Add to shopping list'),
          ),
        ),
        PopupMenuItem(
          value: _ExpirationAction.editDate,
          child: ListTile(
            leading: Icon(Icons.edit_calendar_outlined),
            title: Text('Edit date…'),
          ),
        ),
        PopupMenuItem(
          value: _ExpirationAction.removeExpired,
          child: ListTile(
            leading: Icon(Icons.inventory_2_outlined),
            title: Text('Remove expired from stock'),
            subtitle: Text('Mark expired purchases as used up'),
          ),
        ),
      ],
    );
  }

  // ——— Actions ———

  static Future<void> _addToShoppingList(InventoryItem item) async {
    final box = Hive.box<ShoppingListItem>(Boxes.shoppingList);
    final id = generateId();
    final sli = ShoppingListItem(
      id: id,
      name: item.name,
      amount: 1.0, // sensible default; user can edit in Shopping List
      unit: item.unit,
      recipeName: '',
      isChecked: false,
    );
    await box.put(id, sli);
  }

  static Future<void> _editExpiration(BuildContext context, InventoryItem item) async {
    // Pick the most relevant purchase row: the earliest expiring (or first available)
    PurchaseTransaction? target;
    final withExpiry = item.purchaseHistory
        .where((p) => p.remainingAmount > 0 && p.expirationDate != null)
        .toList()
      ..sort((a, b) => a.expirationDate!.compareTo(b.expirationDate!));
    if (withExpiry.isNotEmpty) {
      target = withExpiry.first;
    } else if (item.purchaseHistory.isNotEmpty) {
      target = item.purchaseHistory.first;
    }

    if (target == null) {
      snacks.text('No purchases found for “${item.name}”.');
      return;
    }

    await showDialog(
      context: context,
      builder: (_) => EditPurchaseDialog(entry: target!, item: item),
    );
  }

  /// Set usedAmount=amount on all expired purchases with remaining stock.
  static Future<_WriteOffResult> _writeOffExpiredStock(InventoryItem item) async {
    final now = DateTime.now();

    int rows = 0;
    double amountCleared = 0.0;

    for (final p in item.purchaseHistory) {
      final exp = p.expirationDate;
      if (exp == null) continue;
      if (!exp.isBefore(now)) continue;
      final remaining = p.remainingAmount;
      if (remaining <= 0) continue;
      amountCleared += remaining;
      p.usedAmount = p.amount; // write off
      rows++;
    }

    if (rows > 0) {
      await item.save();
    }
    return _WriteOffResult(count: rows, amount: amountCleared);
  }

  static String _fmt(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(2);
  }
}

enum _ExpirationAction { addToShopping, editDate, removeExpired }

class _Subheader extends StatelessWidget {
  const _Subheader(this.title);
  final String title;
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(width: 6),
        Expanded(
          child: Divider(
            height: 24,
            thickness: 1,
            color: Theme.of(context).dividerColor.withOpacity(0.3),
          ),
        ),
      ],
    );
  }
}

class _EmptyRow extends StatelessWidget {
  const _EmptyRow(this.message);
  final String message;
  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.check_circle_outline),
      title: Text(message),
    );
  }
}

class _WriteOffResult {
  final int count;
  final double amount;
  _WriteOffResult({required this.count, required this.amount});
}
