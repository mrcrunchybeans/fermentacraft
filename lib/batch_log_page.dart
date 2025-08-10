// lib/batch_log_page.dart
import 'package:fermentacraft/widgets/show_paywall.dart';
import 'package:flutter/material.dart';
import 'package:fermentacraft/batch_detail_page.dart';
import 'package:fermentacraft/models/batch_model.dart';
import 'package:fermentacraft/widgets/add_batch_dialog.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

// gating + counts + paywall
import 'package:fermentacraft/services/feature_gate.dart';
import 'package:fermentacraft/services/counts_service.dart';

class BatchLogPage extends StatefulWidget {
  const BatchLogPage({super.key});

  @override
  State<BatchLogPage> createState() => _BatchLogPageState();
}

class _BatchLogPageState extends State<BatchLogPage> {
  final DateFormat _dateFormat = DateFormat('MMM d, yyyy');
  bool _showArchived = false;

  Future<void> _toggleArchiveStatus(BatchModel batch) async {
    final isArchiving = !batch.isArchived;

    // Enforce archived cap for Free
    if (isArchiving && !FeatureGate.instance.isPremium) {
      final archived = CountsService.instance.archivedBatchCount();
      if (archived >= FeatureGate.instance.archivedBatchLimitFree) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Free allows ${FeatureGate.instance.archivedBatchLimitFree} archived batches')),
        );
showPaywall(context);

        return;
      }
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isArchiving ? "Archive Batch?" : "Unarchive Batch?"),
        content: Text(
          'Are you sure you want to ${isArchiving ? 'archive' : 'unarchive'} "${batch.name}"?',
        ),
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
      batch.isArchived = isArchiving;
      await batch.save();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isArchiving ? 'Archived "${batch.name}"' : 'Unarchived "${batch.name}"')),
      );
      setState(() {});
    }
  }

  Future<void> _deleteBatchWithUndo(BatchModel batch) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Batch?"),
        content: Text('This will permanently delete "${batch.name}" and its data.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final backup = batch; // keep in memory
    final key = batch.key;
    final name = batch.name;

    await batch.delete();
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Deleted "$name"'),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: 'UNDO',
          onPressed: () async {
            final box = Hive.box<BatchModel>('batches');
            try {
              await box.put(key, backup);
            } catch (_) {
              await box.add(backup);
            }
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Batch restored')),
            );
          },
        ),
      ),
    );
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
        PopupMenuItem(
          value: _BatchAction.delete,
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

  void _onAddBatchPressed() async {
    // Enforce Free limit: max 1 active batch
    final fg = FeatureGate.instance;
    final currentActive = CountsService.instance.activeBatchCount();
    if (!fg.canAddActiveBatch(currentActive)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Free allows ${fg.activeBatchLimitFree} active batch')),
      );
showPaywall(context);

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
        valueListenable: Hive.box<BatchModel>('batches').listenable(),
        builder: (context, box, _) {
          final batches = box.values.where((b) => b.isArchived == _showArchived).toList();

          if (batches.isEmpty) {
            return Center(
              child: Text(
                _showArchived ? 'No archived batches.' : 'No batches yet. Tap + to create one.',
              ),
            );
          }

          final active = batches.where((b) => b.status != 'Completed').toList();
          final completed = batches.where((b) => b.status == 'Completed').toList();

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
          final sg = batch.safeMeasurements.isNotEmpty
              ? batch.safeMeasurements.last.gravity?.toStringAsFixed(3)
              : '—';

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
                return false; // keep in place; list will rebuild
              } else {
                await _deleteBatchWithUndo(batch);
                return false;
              }
            },
            child: ListTile(
              title: Text(batch.name),
              subtitle: Text(
                'Started: ${_dateFormat.format(batch.startDate)}\n'
                'Status: ${batch.status}\n'
                'Current SG: $sg',
              ),
              isThreeLine: true,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => BatchDetailPage(batchKey: batch.key)),
                );
              },
              trailing: _moreMenu(batch),
              onLongPress: () => _toggleArchiveStatus(batch),
            ),
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
    final color = danger ? cs.error : cs.primary;
    final onColor = danger ? cs.onError : cs.onPrimary;

    return Container(
      color: color.withValues(alpha:0.90), // safer across SDKs
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
