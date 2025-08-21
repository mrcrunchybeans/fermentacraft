// lib/batch_log_page.dart
// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:fermentacraft/widgets/show_paywall.dart';
import 'package:fermentacraft/pages/batch_detail_page.dart';
import 'package:fermentacraft/models/batch_model.dart';
import 'package:fermentacraft/widgets/add_batch_dialog.dart';
import 'package:fermentacraft/utils/snacks.dart';
import 'package:fermentacraft/services/feature_gate.dart';
import 'package:fermentacraft/services/counts_service.dart';
// ❌ no direct sync-service calls needed
// import 'package:fermentacraft/services/firestore_sync_service.dart';

import '../utils/boxes.dart';

class BatchLogPage extends StatefulWidget {
  const BatchLogPage({super.key});

  @override
  State<BatchLogPage> createState() => _BatchLogPageState();
}

class _BatchLogPageState extends State<BatchLogPage> {
  final DateFormat _dateFormat = DateFormat('MMM d, yyyy');
  bool _showArchived = false;

  String _safeName(BatchModel b) {
    final t = b.name.trim();
    return t.isNotEmpty ? t : 'Untitled batch';
  }

  String _safeStatus(BatchModel b) {
    final t = b.status.trim();
    return t.isNotEmpty ? t : 'Unknown';
  }

  String _safeStartDate(BatchModel b) => _dateFormat.format(b.startDate);

  String _safeCurrentSg(BatchModel b) {
    try {
      final ms = b.safeMeasurements;
      if (ms.isNotEmpty) {
        final g = ms.last.gravity;
        if (g != null) return g.toStringAsFixed(3);
      }
    } catch (_) {}
    return '—';
  }

  bool _isCompleted(BatchModel b) => b.status.toLowerCase() == 'completed';

  Future<void> _toggleArchiveStatus(BatchModel batch) async {
    final isArchiving = !batch.isArchived;

    final gate = context.read<FeatureGate>();
    if (isArchiving && !gate.isPremium) {
      final archived = CountsService.instance.archivedBatchCount();
      if (archived >= gate.archivedBatchLimitFree) {
        if (!mounted) return;
        final messenger = snacks;
        messenger.show(
          SnackBar(content: Text('Free allows ${gate.archivedBatchLimitFree} archived batches')),
        );
        await showPaywall(context);
        return;
      }
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isArchiving ? "Archive Batch?" : "Unarchive Batch?"),
        content: Text('Are you sure you want to ${isArchiving ? 'archive' : 'unarchive'} "${_safeName(batch)}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(isArchiving ? "Archive" : "Unarchive"),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      batch.isArchived = isArchiving;   // set first
      await batch.save();               // then persist
      if (!mounted) return;
      final messenger = snacks;
      messenger.show(
        SnackBar(
          content: Text(
            isArchiving ? 'Archived "${_safeName(batch)}"' : 'Unarchived "${_safeName(batch)}"',
          ),
        ),
      );
      setState(() {});
    }
  }

  // Robust local delete for both key styles (stable string id or auto-int)
  Future<bool> _deleteBatchLocally(BatchModel batch) async {
    final box = Hive.box<BatchModel>(Boxes.batches);

    final dynamic k = batch.key;
    if (k != null && box.containsKey(k)) {
      await box.delete(k);        // 🔁 FirestoreSyncService sees this and writes tombstone
      return true;
    }

    final id = batch.id;
    if (box.containsKey(id)) {
      await box.delete(id);       // 🔁 watcher handles remote tombstone
      return true;
    }

    for (final key in box.keys) {
      final v = box.get(key);
      if (v is BatchModel && v.id == id) {
        await box.delete(key);    // 🔁 watcher handles remote tombstone
        return true;
      }
    }
    return false;
  }

  Future<void> _deleteBatchWithUndo(BatchModel batch) async {
    final messenger = snacks;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Batch?"),
        content: Text('This will permanently delete "${_safeName(batch)}" and its data.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Delete"),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final backup = batch;
    final id = batch.id;
    final name = _safeName(batch);

    final deleted = await _deleteBatchLocally(batch);
    if (!mounted) return;

    if (deleted) {
      // 👍 No direct sync calls: watchers will write tombstone remotely.
      messenger.show(
        SnackBar(
          content: Text('Deleted "$name"'),
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'UNDO',
            onPressed: () async {
              final box = Hive.box<BatchModel>(Boxes.batches);
              final usesStringKeys = box.isEmpty ? true : box.keys.first is String;
              if (usesStringKeys) {
                await box.put(id, backup); // 🔁 watcher pushes non-deleted doc
              } else {
                await box.add(backup);
              }
              if (!mounted) return;
              messenger.show(const SnackBar(content: Text('Batch restored')));
            },
          ),
        ),
      );
    } else {
      messenger.show(
        const SnackBar(content: Text('Delete failed. Item not found locally.')),
      );
    }
  }

  PopupMenuButton<_BatchAction> _moreMenu(BatchModel batch) {
    return PopupMenuButton<_BatchAction>(
      onSelected: (action) {
        switch (action) {
          case _BatchAction.archiveToggle:
            _toggleArchiveStatus(batch);
            break;
          case _BatchAction.delete:
            _deleteBatchWithUndo(batch);
            break;
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _BatchAction.archiveToggle,
          child: Text(batch.isArchived ? 'Unarchive' : 'Archive'),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: _BatchAction.delete,
          child: Row(
            children: [
              Icon(Icons.delete_outline),
              SizedBox(width: 8),
              Text('Delete'),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _onAddBatchPressed() async {
    final fg = context.read<FeatureGate>();
    final currentActive = CountsService.instance.activeBatchCount();
    if (!fg.canAddActiveBatch(currentActive)) {
      if (!mounted) return;
      final messenger = snacks;
      messenger.show(
        SnackBar(content: Text('Free allows ${fg.activeBatchLimitFree} active batch${fg.activeBatchLimitFree == 1 ? '' : 'es'}')),
      );
      await showPaywall(context);
      return;
    }

    await showDialog(context: context, builder: (_) => const AddBatchDialog());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_showArchived ? 'Archived Batches' : 'Batches'),
        actions: [
          IconButton(
            icon: Icon(_showArchived ? Icons.inventory_2_outlined : Icons.archive_outlined),
            tooltip: _showArchived ? 'View Active Batches' : 'View Archived',
            onPressed: () => setState(() => _showArchived = !_showArchived),
          ),
        ],
      ),
      body: ValueListenableBuilder<Box<BatchModel>>(
        valueListenable: Hive.box<BatchModel>(Boxes.batches).listenable(),
        builder: (context, box, _) {
          final list = box.values.toList();
          final batches = list.where((b) => b.isArchived == _showArchived).toList();

          if (batches.isEmpty) {
            return Center(
              child: Text(_showArchived ? 'No archived batches.' : 'No batches yet. Tap + to create one.'),
            );
          }

          final active = batches.where((b) => !_isCompleted(b)).toList();
          final completed = batches.where(_isCompleted).toList();

          return ListView(
            children: [
              if (active.isNotEmpty) _buildBatchGroup(context, 'Active', active),
              if (completed.isNotEmpty) _buildBatchGroup(context, 'Completed', completed),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'addBatchFab',
        onPressed: _onAddBatchPressed,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBatchGroup(BuildContext context, String title, List<BatchModel> batches) {
    return Card(
      margin: const EdgeInsets.all(12.0),
      child: ExpansionTile(
        title: Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        initiallyExpanded: true,
        children: batches.map((batch) {
          final sg = _safeCurrentSg(batch);
          return Dismissible(
            key: ValueKey(batch.key),
            background: _swipeBg(
              context,
              icon: batch.isArchived ? Icons.unarchive : Icons.archive_outlined,
              label: batch.isArchived ? 'Unarchive' : 'Archive',
              alignment: Alignment.centerLeft,
            ),
            secondaryBackground: _swipeBg(
              context,
              icon: Icons.delete_outline,
              label: 'Delete',
              alignment: Alignment.centerRight,
              danger: true,
            ),
            confirmDismiss: (direction) async {
              if (direction == DismissDirection.startToEnd) {
                await _toggleArchiveStatus(batch);
                return false;
              } else {
                await _deleteBatchWithUndo(batch);
                return false;
              }
            },
            child: ListTile(
              title: Text(_safeName(batch)),
              subtitle: Text(
                'Started: ${_safeStartDate(batch)}\n'
                'Status: ${_safeStatus(batch)}\n'
                'Current SG: $sg',
              ),
              isThreeLine: true,
  onTap: () {
    // Coerce Hive’s key (could be int/String/null) to a String
    final String keyStr = (batch.key ?? batch.id ?? '').toString();
    if (keyStr.isEmpty) return; // optional: guard if neither exists

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BatchDetailPage(batchKey: keyStr),
      ),
    );
  },
  trailing: _moreMenu(batch),
  onLongPress: () => _toggleArchiveStatus(batch),
)
          );
        }).toList(),
      ),
    );
  }

  Widget _swipeBg(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Alignment alignment,
    bool danger = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    final base = danger ? cs.error : cs.primary;
    final onColor = danger ? cs.onError : cs.onPrimary;

    return Container(
      color: base.withOpacity(0.90),
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
}

enum _BatchAction { archiveToggle, delete }
