import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Minimal device POJO used by this screen. Replace with your real model.
class DeviceLite {
  final String id;
  final String name;
  final String? assignedBatchName; // null if unassigned
  final DateTime? lastReadingAt;
  final String? endpointUrl;
  final bool online;

  DeviceLite({
    required this.id,
    required this.name,
    this.assignedBatchName,
    this.lastReadingAt,
    this.endpointUrl,
    this.online = false,
  });
}

/// Replace these with your real repository/services (Hive/Firestore/etc.)
abstract class DevicesRepo {
  Future<List<DeviceLite>> listDevices();
  Future<void> addDevice({required String name, String? endpointUrl});
  Future<void> renameDevice(String deviceId, String newName);
  Future<void> deleteDevice(String deviceId);
  Future<void> testPing(String deviceId);
  Future<void> calibrate(String deviceId); // stub for your flow
}

class DevicesPage extends StatefulWidget {
  final DevicesRepo repo;
  const DevicesPage({super.key, required this.repo});

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  late Future<List<DeviceLite>> _future;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _future = widget.repo.listDevices();
  }

  Future<void> _reload() async {
    setState(() {
      _future = widget.repo.listDevices();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Devices')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search devices',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<DeviceLite>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final items = (snap.data ?? [])
                    .where((d) => _q.isEmpty || d.name.toLowerCase().contains(_q))
                    .toList();

                if (items.isEmpty) {
                  return const Center(child: Text('No devices yet'));
                }

                return RefreshIndicator(
                  onRefresh: _reload,
                  child: ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      final d = items[i];
                      final assigned = d.assignedBatchName;
                      return ListTile(
                        leading: Icon(
                          d.online ? Icons.sensors : Icons.sensors_off,
                          color: d.online ? theme.colorScheme.primary : null,
                        ),
                        title: Text(d.name),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (assigned != null)
                              Text('Assigned to: $assigned'),
                            if (d.lastReadingAt != null)
                              Text('Last reading: ${d.lastReadingAt}'),
                            if (d.endpointUrl != null)
                              Text(
                                d.endpointUrl!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall,
                              ),
                          ],
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) async {
                            final messenger = ScaffoldMessenger.of(context);
                            if (value == 'rename') {
                              final newName = await _promptText(context, 'Rename device', d.name);
                              if (newName == null || newName.trim().isEmpty) return;
                              await widget.repo.renameDevice(d.id, newName.trim());
                              await _reload();
                              messenger.showSnackBar(const SnackBar(content: Text('Device renamed')));
                            } else if (value == 'calibrate') {
                              await widget.repo.calibrate(d.id);
                              messenger.showSnackBar(const SnackBar(content: Text('Calibration started')));
                            } else if (value == 'ping') {
                              await widget.repo.testPing(d.id);
                              messenger.showSnackBar(const SnackBar(content: Text('Ping sent')));
                              // inside onSelected for 'copyUrl'
                              } else if (value == 'copyUrl') {
                                final messenger = ScaffoldMessenger.of(context); // capture BEFORE awaits
                                final endpoint = d.endpointUrl; // local final => promotable
                                if (endpoint != null) {
                                  await Clipboard.setData(ClipboardData(text: endpoint));
                                  messenger.showSnackBar(const SnackBar(content: Text('URL copied')));
                                } else {
                                  messenger.showSnackBar(const SnackBar(content: Text('No URL to copy')));
                                }


                            } else if (value == 'delete') {
                              final ok = await _confirm(context, 'Delete device?', 'This cannot be undone.');
                              if (ok == true) {
                                await widget.repo.deleteDevice(d.id);
                                await _reload();
                                messenger.showSnackBar(const SnackBar(content: Text('Device deleted')));
                              }
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(value: 'rename', child: Text('Rename')),
                            const PopupMenuItem(value: 'calibrate', child: Text('Calibrate')),
                            const PopupMenuItem(value: 'ping', child: Text('Test ping')),
                            const PopupMenuItem(value: 'copyUrl', child: Text('Copy endpoint URL')),
                            const PopupMenuDivider(),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Text('Delete', style: TextStyle(color: Colors.red)),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
floatingActionButton: FloatingActionButton.extended(
  icon: const Icon(Icons.add),
  label: const Text('Add device'),
  onPressed: () async {
    final messenger = ScaffoldMessenger.of(context); // capture first
    final name = await _promptText(context, 'Device name');
    if (name == null || name.trim().isEmpty) return;

    await widget.repo.addDevice(name: name.trim());
    await _reload();
    messenger.showSnackBar(const SnackBar(content: Text('Device added')));
  },
),

    );
  }

  Future<String?> _promptText(BuildContext context, String title, [String initial = '']) async {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(controller.text), child: const Text('Save')),
        ],
      ),
    );
  }

  Future<bool?> _confirm(BuildContext context, String title, String body) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('No')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Yes')),
        ],
      ),
    );
  }
}
