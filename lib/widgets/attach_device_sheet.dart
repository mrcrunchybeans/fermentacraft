import 'package:flutter/material.dart';
import 'package:fermentacraft/widgets/link_device_dialog.dart';
import 'package:fermentacraft/services/feature_gate.dart';
import 'package:fermentacraft/widgets/show_paywall.dart';

class AttachDeviceResult {
  final String? deviceId; // null means detach
  AttachDeviceResult(this.deviceId);
}

class DevicePickItem {
  final String id;
  final String name;
  final bool online;
  final bool assignedElsewhere;
  final String? assignedBatchName;
  DevicePickItem({
    required this.id,
    required this.name,
    this.online = false,
    this.assignedElsewhere = false,
    this.assignedBatchName,
  });
}

/// Provide the list via `fetchDevices()`; optionally filter to unassigned.
/// Returns `AttachDeviceResult(deviceId)` or `AttachDeviceResult(null)` if detached,
/// or null if dismissed.
Future<AttachDeviceResult?> showAttachDeviceSheet({
  required BuildContext context,
  required Future<List<DevicePickItem>> Function() fetchDevices,
  required String? currentlyAttachedDeviceId,
  bool showAssignedToo = true,
  String? batchId,
}) {
  return showModalBottomSheet<AttachDeviceResult?>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _AttachDeviceSheetBody(
      fetchDevices: fetchDevices,
      currentlyAttachedDeviceId: currentlyAttachedDeviceId,
      showAssignedToo: showAssignedToo,
      batchId: batchId,
    ),
  );
}

class _AttachDeviceSheetBody extends StatefulWidget {
  final Future<List<DevicePickItem>> Function() fetchDevices;
  final String? currentlyAttachedDeviceId;
  final bool showAssignedToo;
  final String? batchId;

  const _AttachDeviceSheetBody({
    required this.fetchDevices,
    required this.currentlyAttachedDeviceId,
    required this.showAssignedToo,
    this.batchId,
  });

  @override
  State<_AttachDeviceSheetBody> createState() => _AttachDeviceSheetBodyState();
}

class _AttachDeviceSheetBodyState extends State<_AttachDeviceSheetBody> {
  late Future<List<DevicePickItem>> _future;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _future = widget.fetchDevices();
  }

Future<void> _refresh() async {
  if (!mounted) return;
  setState(() {
    _future = widget.fetchDevices(); // callback returns void now
  });
}


  Future<void> _openAddDevice() async {
    // 🔒 Premium gate
    if (!FeatureGate.instance.allowDevices) {
      if (!mounted) return;
      showPaywall(context);
      return;
    }

    final dialogContext = context; // capture before await
    await showDialog<void>(
      context: dialogContext,
      builder: (_) => LinkDeviceDialog(batchId: widget.batchId),
    );

    // After closing, refresh list
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with Refresh + Add buttons
            ListTile(
              title: const Text('Attach a device'),
              subtitle: const Text('Devices stream SG, Temp, and more into this batch'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Refresh',
                    icon: const Icon(Icons.refresh),
                    onPressed: _refresh,
                  ),
                  IconButton(
                    tooltip: 'Add device',
                    icon: const Icon(Icons.add),
                    onPressed: _openAddDevice,
                  ),
                ],
              ),
            ),

            // Search
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search devices',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
              ),
            ),

            // List
            FutureBuilder<List<DevicePickItem>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                var items = snap.data ?? [];
                if (!widget.showAssignedToo) {
                  items = items.where((d) => !d.assignedElsewhere).toList();
                }
                items = items
                    .where((d) => _q.isEmpty || d.name.toLowerCase().contains(_q))
                    .toList();

                if (items.isEmpty) {
                  // Empty → encourage adding a device right here
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: Column(
                      children: [
                        const Text('No devices available'),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.add),
                          label: const Text('Add a device'),
                          onPressed: _openAddDevice,
                        ),
                      ],
                    ),
                  );
                }

                return Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final d = items[i];
                      final isCurrent = d.id == widget.currentlyAttachedDeviceId;
                      return ListTile(
                        leading: Icon(
                          d.online ? Icons.sensors : Icons.sensors_off,
                          color: d.online ? theme.colorScheme.primary : null,
                        ),
                        title: Text(d.name),
                        subtitle: d.assignedElsewhere
                            ? Text(
                                'Assigned to ${d.assignedBatchName}',
                                style: TextStyle(color: theme.colorScheme.error),
                              )
                            : null,
                        trailing: isCurrent
                            ? FilledButton.icon(
                                icon: const Icon(Icons.check),
                                label: const Text('Attached'),
                                onPressed: null,
                              )
                            : FilledButton(
                                onPressed: () {
                                  Navigator.of(context)
                                      .pop(AttachDeviceResult(d.id));
                                },
                                child: const Text('Attach'),
                              ),
                      );
                    },
                  ),
                );
              },
            ),

            const SizedBox(height: 8),

            // Footer actions
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.link_off),
                      label: const Text('Detach from batch'),
                      onPressed: widget.currentlyAttachedDeviceId == null
                          ? null
                          : () =>
                              Navigator.of(context).pop(AttachDeviceResult(null)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      child: const Text('Close'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
