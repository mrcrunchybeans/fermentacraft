// lib/widgets/devices_selection.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:fermentacraft/services/firestore_paths.dart';
import 'package:fermentacraft/widgets/link_device_dialog.dart';

// For batch picker (local list)
import 'package:fermentacraft/utils/boxes.dart';
import 'package:fermentacraft/models/batch_model.dart';

// Ingest base URL helper; returns https://log.fermentacraft.com
import 'package:fermentacraft/utils/firebase_env.dart';

enum _LinkFilter { all, linked, unlinked }

class DevicesSelection extends StatefulWidget {
  const DevicesSelection({
    super.key,
    required this.uid,
    this.batchId,
  });

  final String uid;
  final String? batchId;

  @override
  State<DevicesSelection> createState() => _DevicesSelectionState();

  static Future<void> openWithCurrentUser(
    BuildContext context, {
    String? batchId,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      await showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(
          title: Text('Sign in required'),
          content: Text('Please sign in to manage devices.'),
        ),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DevicesSelection(uid: user.uid, batchId: batchId)),
    );
  }
}

class _DevicesSelectionState extends State<DevicesSelection> {
  String _query = '';
  _LinkFilter _filter = _LinkFilter.all;
  bool get _isDesktopLike =>
      kIsWeb ||
      {
        TargetPlatform.windows,
        TargetPlatform.linux,
        TargetPlatform.macOS,
      }.contains(defaultTargetPlatform);

  @override
  Widget build(BuildContext context) {
    // batchId -> batchName (from Hive)
    final batchBox = Hive.box<BatchModel>(Boxes.batches);
    final Map<String, String> batchNameById = {
      for (final b in batchBox.values)
        if ((b as dynamic).id is String)
          ((b as dynamic).id as String): (((b as dynamic).name as String?) ?? '(unnamed)'),
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.batchId == null ? 'Devices' : 'Devices (link to batch)'),
        actions: [
          if (_isDesktopLike)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Tooltip(
                message: 'Add device',
                child: IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () => _openAddDevice(context),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: !_isDesktopLike
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text('Add device'),
              onPressed: () => _openAddDevice(context),
            )
          : null,
      body: Column(
        children: [
          const SizedBox(height: 8),
          _HelpBanner(batchMode: widget.batchId != null),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                // Search
                Expanded(
                  child: _SearchField(
                    initial: _query,
                    hint: 'Search name or ID…',
                    onChanged: (v) => setState(() => _query = v.trim()),
                  ),
                ),
                const SizedBox(width: 12),
                // Filter
                SegmentedButton<_LinkFilter>(
                  segments: const [
                    ButtonSegment(value: _LinkFilter.all, label: Text('All'), icon: Icon(Icons.list_alt)),
                    ButtonSegment(value: _LinkFilter.linked, label: Text('Linked'), icon: Icon(Icons.link)),
                    ButtonSegment(value: _LinkFilter.unlinked, label: Text('Unlinked'), icon: Icon(Icons.link_off)),
                  ],
                  selected: <_LinkFilter>{_filter},
                  onSelectionChanged: (s) => setState(() => _filter = s.first),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirestorePaths
                  .devicesColl(widget.uid)
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return _CenteredInfo(
                    icon: Icons.error_outline,
                    title: 'Something went wrong',
                    subtitle: '${snap.error}',
                  );
                }

                final docs = snap.data?.docs ?? const [];
                if (docs.isEmpty) return const _EmptyDevices();

                // Prefer unlinked at top when linking to a specific batch
                final ordered = [...docs];
                if (widget.batchId != null) {
                  int linkedToInt(String? id) => (id?.isNotEmpty ?? false) ? 1 : 0;
                  ordered.sort((a, b) {
                    final aLinked = linkedToInt(a.data()['linkedBatchId'] as String?);
                    final bLinked = linkedToInt(b.data()['linkedBatchId'] as String?);
                    return aLinked.compareTo(bLinked);
                  });
                }

                // Filter + search
                List<QueryDocumentSnapshot<Map<String, dynamic>>> items = ordered.where((d) {
                  final data = d.data();
                  final name = ((data['name'] as String?) ?? (data['displayName'] as String?) ?? d.id).toLowerCase();
                  final id = d.id.toLowerCase();
                  final link = (data['linkedBatchId'] as String?) ?? '';
                  final passesFilter = switch (_filter) {
                    _LinkFilter.all => true,
                    _LinkFilter.linked => link.isNotEmpty,
                    _LinkFilter.unlinked => link.isEmpty,
                  };
                  final passesQuery = _query.isEmpty || name.contains(_query.toLowerCase()) || id.contains(_query.toLowerCase());
                  return passesFilter && passesQuery;
                }).toList();

                if (items.isEmpty) {
                  return const _CenteredInfo(
                    icon: Icons.search_off,
                    title: 'No matches',
                    subtitle: 'Try a different search or filter.',
                  );
                }

                return LayoutBuilder(
                  builder: (context, c) {
                    // Grid on wide screens
                    final width = c.maxWidth;
                    final columns = width >= 1200
                        ? 4
                        : width >= 900
                            ? 3
                            : width >= 640
                                ? 2
                                : 1;

                    if (columns == 1) {
                      // List on phones
                      return ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const Divider(height: 0),
                        itemBuilder: (context, i) {
                          final doc = items[i];
                          return _DeviceTile(
                            uid: widget.uid,
                            doc: doc,
                            batchNameById: batchNameById,
                            batchId: widget.batchId,
                          );
                        },
                      );
                    }

                    // Grid on tablet/desktop/web
                    return GridView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        childAspectRatio: 1.8,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemCount: items.length,
                      itemBuilder: (context, i) {
                        final doc = items[i];
                        return _DeviceCard(
                          uid: widget.uid,
                          doc: doc,
                          batchNameById: batchNameById,
                          batchId: widget.batchId,
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openAddDevice(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (_) => LinkDeviceDialog(batchId: widget.batchId),
    );
  }
}

/* -------------------------------------------------------------------------- */
/*  Pieces                                                                     */
/* -------------------------------------------------------------------------- */

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.uid,
    required this.doc,
    required this.batchNameById,
    required this.batchId,
  });

  final String uid;
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final Map<String, String> batchNameById;
  final String? batchId;

@override
Widget build(BuildContext context) {
  final data = doc.data();
  final deviceId = doc.id;
  final name = (data['name'] as String?) ?? (data['displayName'] as String?) ?? deviceId;
  final battery = (data['battery'] as num?)?.toDouble();
  final lastSeen = (data['lastSeen'] as Timestamp?)?.toDate();
  final linkedBid = (data['linkedBatchId'] as String?) ?? '';
  final secret = (data['secret'] as String?) ?? '';

  final subtitle = _buildSubtitle(
    battery: battery,
    lastSeen: lastSeen,
    batchName: linkedBid.isEmpty ? null : batchNameById[linkedBid],
  );

  final messenger = ScaffoldMessenger.of(context);

  return Dismissible(
    key: ValueKey(deviceId),
    direction: DismissDirection.endToStart,
    background: Container(
      alignment: Alignment.centerRight,
      color: Colors.red,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: const Icon(Icons.delete, color: Colors.white),
    ),
    confirmDismiss: (_) => _confirmDelete(context, name),
    onDismissed: (_) async {
      await FirestorePaths.deviceDoc(uid, deviceId).delete();
      messenger.showSnackBar(SnackBar(content: Text('Deleted "$name"')));
    },

    // ✅ Wrap the tile so we can handle right-clicks properly
    child: GestureDetector(
      onSecondaryTapDown: (details) {
        // Only show on desktop/web
        if (!(kIsWeb ||
            {
              TargetPlatform.windows,
              TargetPlatform.linux,
              TargetPlatform.macOS,
            }.contains(defaultTargetPlatform))) {
          return;
        }
        _showContextMenu(context, details.globalPosition);
      },

      child: ListTile(
        leading: const Icon(Icons.sensors),
        title: kIsWeb ? SelectableText(name) : Text(name),
        subtitle: subtitle == null ? null : Text(subtitle),
        onTap: () => _showDeviceDetailsSheet(
          context: context,
          uid: uid,
          deviceId: deviceId,
          secret: secret,
          currentBatchId: linkedBid,
          requestedBatchId: batchId,
          onLinked: () => messenger.showSnackBar(const SnackBar(content: Text('Device linked'))),
        ),
        trailing: _MoreMenu(
          onSelected: (value) => _onMenu(
            context: context,
            value: value,
            uid: uid,
            deviceId: deviceId,
            deviceName: name, // 👈 add this
            batchId: batchId,
            linkedBid: linkedBid,
            onLinked: () => messenger.showSnackBar(const SnackBar(content: Text('Linked'))),
            onUnlinked: () => messenger.showSnackBar(const SnackBar(content: Text('Unlinked'))),
            onDeleted: () => messenger.showSnackBar(SnackBar(content: Text('Deleted "$name"'))),
          ),
          entries: [
            if (batchId != null && linkedBid != batchId)
              const PopupMenuItem(value: 'link-here', child: Text('Link to this batch')),
            if (batchId == null)
              const PopupMenuItem(value: 'link-pick', child: Text('Link to…')),
            if (linkedBid.isNotEmpty)
              const PopupMenuItem(value: 'unlink', child: Text('Unlink')),
            const PopupMenuItem(
              value: 'calibrate',
              child: Row(
                children: [
                  Icon(Icons.tune, size: 18),
                  SizedBox(width: 8),
                  Text('Calibrate offsets'),
                ],
              ),
            ),
            const PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
onLongPress: () async {
  await Clipboard.setData(ClipboardData(text: deviceId));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Device ID copied')),
  );
},
      ),
    ),
  );
}


  void _showContextMenu(BuildContext context, Offset globalPos) async {
    if (!(kIsWeb ||
        {
          TargetPlatform.windows,
          TargetPlatform.linux,
          TargetPlatform.macOS,
        }.contains(defaultTargetPlatform))) {
      return;
    }
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(Rect.fromLTWH(globalPos.dx, globalPos.dy, 0, 0), Offset.zero & overlay.size),
      items: const [
        PopupMenuItem(value: 'copy-id', child: Text('Copy Device ID')),
      ],
    ).then((v) {
      if (v == 'copy-id') Clipboard.setData(ClipboardData(text: doc.id));
    });
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.uid,
    required this.doc,
    required this.batchNameById,
    required this.batchId,
  });

  final String uid;
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final Map<String, String> batchNameById;
  final String? batchId;

  @override
  Widget build(BuildContext context) {
    final data = doc.data();
    final deviceId = doc.id;
    final name = (data['name'] as String?) ?? (data['displayName'] as String?) ?? deviceId;
    final battery = (data['battery'] as num?)?.toDouble();
    final lastSeen = (data['lastSeen'] as Timestamp?)?.toDate();
    final linkedBid = (data['linkedBatchId'] as String?) ?? '';
    final secret = (data['secret'] as String?) ?? '';

    final subtitle = _buildSubtitle(
      battery: battery,
      lastSeen: lastSeen,
      batchName: linkedBid.isEmpty ? null : batchNameById[linkedBid],
    );

    return Card(
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        onTap: () => _showDeviceDetailsSheet(
          context: context,
          uid: uid,
          deviceId: deviceId,
          secret: secret,
          currentBatchId: linkedBid,
          requestedBatchId: batchId,
          onLinked: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Device linked'))),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Icon(Icons.sensors, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _RowWrap(children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if ((linkedBid).isNotEmpty)
                        const Padding(
                          padding: EdgeInsets.only(left: 8),
                          child: Tooltip(
                            message: 'Linked',
                            child: Chip(
                              label: Text('Linked'),
                              padding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        ),
                    ]),
                    const SizedBox(height: 2),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _BatteryChip(battery: battery),
              _MoreMenu(
                entries: [
                  if (batchId != null && linkedBid != batchId) const PopupMenuItem(value: 'link-here', child: Text('Link to this batch')),
                  if (batchId == null) const PopupMenuItem(value: 'link-pick', child: Text('Link to…')),
                  if (linkedBid.isNotEmpty) const PopupMenuItem(value: 'unlink', child: Text('Unlink')),
                  const PopupMenuItem(
                    value: 'calibrate',
                    child: Row(
                      children: [
                        Icon(Icons.tune, size: 18),
                        SizedBox(width: 8),
                        Text('Calibrate offsets'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
                onSelected: (value) => _onMenu(
                  context: context,
                  value: value,
                  uid: uid,
                  deviceId: deviceId,
                  deviceName: name, // 👈 add this
                  batchId: batchId,
                  linkedBid: linkedBid,
                  onLinked: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Linked'))),
                  onUnlinked: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unlinked'))),
                  onDeleted: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Deleted "$name"'))),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ---------- Small widgets -------------------------------------------------- */

class _SearchField extends StatefulWidget {
  const _SearchField({required this.initial, required this.hint, required this.onChanged});
  final String initial;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  late final TextEditingController _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _c,
      onChanged: widget.onChanged,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search),
        hintText: widget.hint,
        isDense: true,
        filled: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        suffixIcon: _c.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear',
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _c.clear();
                  widget.onChanged('');
                  setState(() {});
                },
              ),
      ),
    );
  }
}

class _MoreMenu extends StatelessWidget {
  const _MoreMenu({required this.entries, required this.onSelected});
  final List<PopupMenuEntry<String>> entries;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'More',
      child: PopupMenuButton<String>(
        onSelected: onSelected,
        itemBuilder: (_) => entries,
      ),
    );
    }
}

class _BatteryChip extends StatelessWidget {
  const _BatteryChip({required this.battery});
  final double? battery;

  @override
  Widget build(BuildContext context) {
    final pct = battery == null ? null : (battery! > 1 ? battery : battery! * 100);
    final color = pct == null
        ? Colors.grey
        : pct >= 66
            ? Colors.green
            : pct >= 33
                ? Colors.orange
                : Colors.red;
    return Tooltip(
      message: pct == null ? 'Battery: —' : 'Battery: ${pct.toStringAsFixed(0)}%',
      child: Chip(
        label: Text(pct == null ? '—%' : '${pct.toStringAsFixed(0)}%'),
        backgroundColor: color.withOpacity(.12),
        visualDensity: VisualDensity.compact,
        side: BorderSide(color: color.withOpacity(.4)),
      ),
    );
  }
}

class _RowWrap extends StatelessWidget {
  const _RowWrap({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
  }
}

class _CenteredInfo extends StatelessWidget {
  const _CenteredInfo({required this.icon, required this.title, this.subtitle});
  final IconData icon;
  final String title;
  final String? subtitle;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle!, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).hintColor)),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyDevices extends StatelessWidget {
  const _EmptyDevices();

  @override
  Widget build(BuildContext context) {
    return const _CenteredInfo(
      icon: Icons.sensors,
      title: 'No devices yet',
      subtitle: 'Tap “Add device” to generate a link URL or QR code.',
    );
  }
}

class _HelpBanner extends StatelessWidget {
  const _HelpBanner({required this.batchMode});
  final bool batchMode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Material(
        color: theme.colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        child: ListTile(
          dense: true,
          leading: const Icon(Icons.info_outline),
          title: Text(
            batchMode
                ? 'Tip: When linking a device, unlinked ones are shown first.'
                : 'Tip: iSpindel/Nautilis “Run push test” may show an error even when live pushes work.',
            style: theme.textTheme.bodyMedium,
          ),
          trailing: TextButton(
            child: const Text('LEARN MORE'),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const AlertDialog(
                title: Text('About device pushes'),
                content: Text(
                  'Supported devices (iSpindel, GravityMon, Tilt, '
                  'Nautilis iRelay, Nautilis iPressure, HYDROM, and more) '
                  'should POST JSON to the shown URL with:\n'
                  '• Content-Type: application/json\n'
                  '• X-Device-Secret: <secret>\n\n'
                  'The “Run push test” button in some firmware/relay UI may '
                  'show an error even though live background pushes succeed. '
                  'Watch the device card for “Seen just now” to confirm.\n',
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/* ---------- Existing helpers (unchanged logic) ---------------------------- */

String? _buildSubtitle({
  double? battery,
  DateTime? lastSeen,
  String? batchName,
}) {
  final bits = <String>[];

  if (battery != null) {
    final pct = battery > 1 ? battery : battery * 100;
    bits.add('Battery ${pct.toStringAsFixed(0)}%');
  }
  if (lastSeen != null) {
    final mins = DateTime.now().difference(lastSeen).inMinutes;
    final s = mins < 1
        ? 'just now'
        : mins < 60
            ? '${mins}m ago'
            : mins < 60 * 24
                ? '${(mins / 60).floor()}h ago'
                : '${(mins / 1440).floor()}d ago';
    bits.add('Seen $s');
  }
  if ((batchName ?? '').isNotEmpty) {
    bits.add('Linked to $batchName');
  }
  return bits.isEmpty ? null : bits.join(' · ');
}

Future<bool> _confirmDelete(
  BuildContext context,
  String deviceName,
) async {
  final t = Theme.of(context);
  return await showDialog<bool>(
        context: context,
        barrierDismissible: false, // avoid accidental tap-to-dismiss
        builder: (ctx) => AlertDialog(
          title: const Text('Delete device?'),
          content: Text('This will remove “$deviceName”. You can add it again later.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.delete_forever),
              style: ElevatedButton.styleFrom(
                backgroundColor: t.colorScheme.error,
                foregroundColor: t.colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              label: const Text('Delete'),
            ),
          ],
        ),
      ) ??
      false;
}


Future<void> _onMenu({
  required BuildContext context,
  required String value,
  required String uid,
  required String deviceId,
  required String deviceName, // NEW
  required String? batchId,
  required String linkedBid,
  required VoidCallback onLinked,
  required VoidCallback onUnlinked,
  required VoidCallback onDeleted,
}) async {

  final messenger = ScaffoldMessenger.of(context);

  switch (value) {
    case 'link-here':
      await FirestorePaths.deviceDoc(uid, deviceId).update({'linkedBatchId': batchId});
      onLinked();
      break;
    case 'link-pick':
      final String? targetBatchId = await _pickBatchId(context);
      if (targetBatchId == null || targetBatchId.isEmpty) return;
      await FirestorePaths.deviceDoc(uid, deviceId).update({'linkedBatchId': targetBatchId});
      onLinked();
      break;
    case 'unlink':
      await FirestorePaths.deviceDoc(uid, deviceId).update({'linkedBatchId': ''});
      onUnlinked();
      break;
    case 'calibrate':
      await _showCalibrationDialog(context, uid: uid, deviceId: deviceId, deviceName: deviceName);
      break;
    case 'delete':
    final ok = await _confirmDelete(context, deviceName);
      if (!ok) return;
      await FirestorePaths.deviceDoc(uid, deviceId).delete();
      onDeleted();
      break;
    default:
      messenger.showSnackBar(const SnackBar(content: Text('Unknown action')));
  }
}

/// Dialog to set gravity, temperature and pressure calibration offsets for a device.
/// Offsets are stored in Firestore as `gravityOffset`, `tempOffset`, and `pressureOffset`.
/// They are applied at display-time in the full log view (raw data is unchanged).
Future<void> _showCalibrationDialog(
  BuildContext context, {
  required String uid,
  required String deviceId,
  required String deviceName,
}) async {
  // Fetch current offsets
  final docSnap = await FirestorePaths.deviceDoc(uid, deviceId).get();
  final data = docSnap.data() ?? {};
  final currentGravity = (data['gravityOffset'] as num?)?.toDouble() ?? 0.0;
  final currentTemp = (data['tempOffset'] as num?)?.toDouble() ?? 0.0;
  final currentPressure = (data['pressureOffset'] as num?)?.toDouble() ?? 0.0;

  double gravity = currentGravity;
  double temp = currentTemp;
  double pressure = currentPressure;

  final gravityCtrl = TextEditingController(
    text: currentGravity == 0.0 ? '' : currentGravity.toStringAsFixed(4),
  );
  final tempCtrl = TextEditingController(
    text: currentTemp == 0.0 ? '' : currentTemp.toStringAsFixed(2),
  );
  final pressureCtrl = TextEditingController(
    text: currentPressure == 0.0 ? '' : currentPressure.toStringAsFixed(3),
  );

  // ignore: use_build_context_synchronously – we guard with a mounted-equivalent
  // check; top-level fns have no `mounted`, so we rely on the dialog guard below.
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Row(
        children: [
          Icon(Icons.tune, color: Theme.of(ctx).colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(child: Text('Calibrate "$deviceName"')),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Gravity offset
            Text('Gravity offset (SG)', style: Theme.of(ctx).textTheme.titleSmall),
            const SizedBox(height: 4),
            TextField(
              controller: gravityCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                signed: true,
                decimal: true,
              ),
              decoration: InputDecoration(
                hintText: '0.0000 (e.g. −0.0002)',
                border: const OutlineInputBorder(),
                helperText:
                    'Added to every device gravity reading.\n'
                    'Tip: open the full log (4 d.p.) to find the true reading.',
                helperMaxLines: 3,
                prefixIcon: const Icon(Icons.water_drop_outlined),
                suffixText: 'SG',
              ),
              onChanged: (v) => gravity = double.tryParse(v) ?? 0.0,
            ),
            const SizedBox(height: 16),

            // Temperature offset
            Text('Temperature offset (°C)', style: Theme.of(ctx).textTheme.titleSmall),
            const SizedBox(height: 4),
            TextField(
              controller: tempCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                signed: true,
                decimal: true,
              ),
              decoration: InputDecoration(
                hintText: 'e.g. −0.5 or −0.35',
                border: const OutlineInputBorder(),
                helperText: 'Added to every device temperature reading.\n'
                    'Any decimal is accepted, e.g. −0.35.',
                helperMaxLines: 3,
                prefixIcon: const Icon(Icons.thermostat_outlined),
                suffixText: '°C',
              ),
              onChanged: (v) => temp = double.tryParse(v) ?? 0.0,
            ),

            const SizedBox(height: 16),

            // Pressure offset (Nautilis iPressure / iRelay+P)
            Text('Pressure offset (bar)', style: Theme.of(ctx).textTheme.titleSmall),
            const SizedBox(height: 4),
            TextField(
              controller: pressureCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                signed: true,
                decimal: true,
              ),
              decoration: InputDecoration(
                hintText: 'e.g. −0.050 or +0.100',
                border: const OutlineInputBorder(),
                helperText: 'Added to every Nautilis pressure reading (bar).\n'
                    'Leave blank or 0 if no pressure sensor is attached.',
                helperMaxLines: 3,
                prefixIcon: const Icon(Icons.compress_outlined),
                suffixText: 'bar',
              ),
              onChanged: (v) => pressure = double.tryParse(v) ?? 0.0,
            ),

            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.surfaceVariant.withOpacity(.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Offsets apply to all past and future readings from this device — '
                'charts, ABV, attenuation, and the full log all reflect the corrected values. '
                'Raw data is never modified.',
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                  color: Theme.of(ctx).hintColor,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel'),
        ),
        OutlinedButton(
          onPressed: () async {
            final nav = Navigator.of(ctx);
            // Reset to zero
            await FirestorePaths.deviceDoc(uid, deviceId).update({
              'gravityOffset': 0.0,
              'tempOffset': 0.0,
              'pressureOffset': 0.0,
            });
            nav.pop();
            if (ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(content: Text('Offsets reset to zero')),
              );
            }
          },
          child: const Text('Reset'),
        ),
        FilledButton(
          onPressed: () async {
            // Read final values from text fields (in case onChanged wasn't called)
            gravity = double.tryParse(gravityCtrl.text) ?? 0.0;
            temp = double.tryParse(tempCtrl.text) ?? 0.0;
            pressure = double.tryParse(pressureCtrl.text) ?? 0.0;
            final nav = Navigator.of(ctx);
            await FirestorePaths.deviceDoc(uid, deviceId).update({
              'gravityOffset': gravity,
              'tempOffset': temp,
              'pressureOffset': pressure,
            });
            nav.pop();
            if (ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                SnackBar(
                  content: Text(
                    'Saved: gravity ${gravity >= 0 ? "+" : ""}${gravity.toStringAsFixed(4)} SG · '
                    'temp ${temp >= 0 ? "+" : ""}${temp.toStringAsFixed(2)}°C · '
                    'pressure ${pressure >= 0 ? "+" : ""}${pressure.toStringAsFixed(3)} bar',
                  ),
                ),
              );
            }
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );

  gravityCtrl.dispose();
  tempCtrl.dispose();
}

/// Polished, responsive bottom sheet with sections, copy rows, and QR.
Future<void> _showDeviceDetailsSheet({
  required BuildContext context,
  required String uid,
  required String deviceId,
  required String secret,
  required String currentBatchId,
  required String? requestedBatchId,
  required VoidCallback onLinked,
}) async {
  final base = functionsBaseUrl(); // https://log.fermentacraft.com

  String buildShortUrl(String? batchId) {
    final b = (batchId != null && batchId.isNotEmpty) ? '?b=${Uri.encodeComponent(batchId)}' : '';
    return '$base/u/$uid/d/$deviceId$b';
  }

  String ckHost() {
    final uri = Uri.tryParse(base);
    return (uri != null && uri.host.isNotEmpty)
        ? uri.host
        : base.replaceFirst(RegExp(r'^https?://'), '');
  }

  String ckPath(String? batchId) {
    final b = (batchId != null && batchId.isNotEmpty) ? '?b=${Uri.encodeComponent(batchId)}' : '';
    return '/u/$uid/d/$deviceId$b';
  }

  final theme = Theme.of(context);
  final effectiveBatch = (currentBatchId.isNotEmpty ? currentBatchId : requestedBatchId);
  final fullUrl = buildShortUrl(effectiveBatch);
  final host = ckHost();
  final path = ckPath(effectiveBatch);

  const contentHeader = 'Content-Type: application/json';
  final secretHeader = 'X-Device-Secret: $secret';

  const bodyTemplate = r'''{
  "name": "${mdns}",
  "ID": "${id}",
  "token": "${token}",
  "interval": ${sleep-interval},
  "temperature": ${temp},
  "temp_units": "${temp-unit}",
  "gravity": ${gravity},
  "velocity": ${velocity},
  "angle": ${angle},
  "battery": ${battery-percent},
  "RSSI": ${rssi},
  "corr-gravity": ${corr-gravity},
  "gravity-unit": "${gravity-unit}",
  "run-time": ${run-time}
}''';

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: theme.colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (ctx) {
      final size = MediaQuery.of(ctx).size;
      final maxH = size.height * 0.9; // cap to 90% of screen height

      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: theme.colorScheme.primary.withOpacity(.12),
                      child: Icon(Icons.sensors, color: theme.colorScheme.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Device URLs',
                        style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    // Quick actions
_IconTextButton(
  icon: Icons.copy,
  label: 'Copy URL',
  onPressed: () async {
    // Capture what you need from context first.
    final messenger = ScaffoldMessenger.of(context);

    await Clipboard.setData(ClipboardData(text: fullUrl));

    // Now you’re not using context after the await.
    messenger.showSnackBar(const SnackBar(content: Text('URL copied')));
  },
),

                    const SizedBox(width: 8),
                    _IconTextButton(
                      icon: Icons.qr_code,
                      label: 'QR',
                      onPressed: () {
                        final isDark = Theme.of(ctx).brightness == Brightness.dark;
                        showDialog<void>(
                          context: ctx,
                          builder: (_) => AlertDialog(
                            title: const Text('Scan URL'),
                            content: SizedBox(
                              width: 240,
                              height: 240,
                              child: Center(
                                child: QrImageView(
                                  data: fullUrl,
                                  gapless: true,
                                  eyeStyle: QrEyeStyle(
                                    eyeShape: QrEyeShape.square,
                                    color: isDark ? Colors.white : Colors.black,
                                  ),
                                  dataModuleStyle: QrDataModuleStyle(
                                    dataModuleShape: QrDataModuleShape.square,
                                    color: isDark ? Colors.white : Colors.black,
                                  ),
                                ),
                              ),
                            ),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Section: BrewFather / GravityMon (preferred)
                _Section(
                  title: 'BrewFather / GravityMon (short URL)',
                  icon: Icons.link,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _Label('Endpoint URL'),
                      _MonoBox(fullUrl, maxLines: 3),
                      const SizedBox(height: 12),
                      const _Label('Headers'),
                      _MonoBox('$contentHeader\n$secretHeader', maxLines: 2),
                      _CopyRow(values: const [
                        ('Copy Content-Type', contentHeader),
                      ], extra: [
                        ('Copy Secret', secretHeader),
                      ]),
                      const SizedBox(height: 12),
                      const _Label('POST JSON body template'),
                      const _MonoBox(bodyTemplate, maxLines: 8),
                      const _CopyRow(values: [
                        ('Copy Body', bodyTemplate),
                      ]),
                      const SizedBox(height: 8),
                      Text(
                        'Use POST with JSON. Some firmwares (“Run push test”) may show an error even when real pushes work. Watch the device card for “Seen just now” to confirm.',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Section: CKBrew Custom
                _Section(
                  title: 'CKBrew (Custom) settings',
                  icon: Icons.dns_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _KeyValueChips(items: {
                        'Server': host,
                        'Port': '443',
                      }),
                      const SizedBox(height: 8),
                      const _Label('Path'),
                      _MonoBox(path, maxLines: 2),
                      const SizedBox(height: 12),
                      const _Label('Headers'),
                      _MonoBox('$contentHeader\n$secretHeader', maxLines: 2),
                      _CopyRow(values: [
                        ('Copy Host', host),
                        ('Copy Path', path),
                      ], extra: [
                        ('Copy Headers', '$contentHeader\n$secretHeader'),
                      ]),
                      const SizedBox(height: 8),
                      Text(
                        'CKBrew → Third-Party → Custom: HTTPS, Port 443, Path shown above. Method: POST with JSON + both headers.',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // Section: Nautilis iRelay / iPressure
                _Section(
                  title: 'Nautilis iRelay / iPressure',
                  icon: Icons.sensors_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Nautilis devices (iRelay+, iRelay Premium, iPressure) use the '
                        'same HTTP endpoint as iSpindel. Select "HTTP" service in the '
                        'Nautilis web interface (192.168.4.1) and enter:',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
                      ),
                      const SizedBox(height: 10),
                      _KeyValueChips(items: {
                        'Server': host,
                        'Port': '443',
                        'Protocol': 'HTTPS',
                      }),
                      const SizedBox(height: 8),
                      const _Label('Path / URI'),
                      _MonoBox(path, maxLines: 2),
                      const SizedBox(height: 8),
                      const _Label('Headers'),
                      _MonoBox('$contentHeader\n$secretHeader', maxLines: 2),
                      _CopyRow(values: [
                        ('Copy Host', host),
                        ('Copy Path', path),
                      ], extra: [
                        ('Copy Secret header', secretHeader),
                      ]),
                      const SizedBox(height: 8),
                      Text(
                        'Pressure readings from iPressure / iRelay+P are stored '
                        'automatically and appear in the "Open full log" view '
                        'alongside gravity and temperature.',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                if ((requestedBatchId?.isNotEmpty ?? false) && requestedBatchId != currentBatchId)
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      icon: const Icon(Icons.link),
                      label: const Text('Link to this batch'),
                      onPressed: () async {
                        final nav = Navigator.of(ctx);
                        await FirestorePaths.deviceDoc(uid, deviceId).update({'linkedBatchId': requestedBatchId});
                        onLinked();
                        if (nav.mounted && nav.canPop()) nav.pop();
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/* ──────────────── Tiny, reusable UI bits ──────────────── */

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.icon, required this.child});
  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withOpacity(.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.dividerColor.withOpacity(.25)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}

class _MonoBox extends StatelessWidget {
  const _MonoBox(this.text, {this.maxLines});
  final String text;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withOpacity(.9),
        border: Border.all(color: theme.dividerColor.withOpacity(.35)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: SelectableText(
        text,
        maxLines: maxLines,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 13.5, height: 1.28),
      ),
    );
  }
}

class _CopyRow extends StatelessWidget {
  const _CopyRow({required this.values, this.extra});
  final List<(String, String)> values;
  final List<(String, String)>? extra;

  @override
  Widget build(BuildContext context) {
    final all = [...values, ...?extra];
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
           for (final (label, value) in all)
    OutlinedButton.icon(
      icon: const Icon(Icons.copy, size: 18),
      label: Text(label),
      onPressed: () async {
        final messenger = ScaffoldMessenger.of(context); // capture before await
        await Clipboard.setData(ClipboardData(text: value));
        messenger.showSnackBar(
          SnackBar(content: Text('$label copied')),
        );
      },
            ),
        ],
      ),
    );
  }
}

class _KeyValueChips extends StatelessWidget {
  const _KeyValueChips({required this.items});
  final Map<String, String> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: items.entries
          .map(
            (e) => Chip(
              label: Text('${e.key}: ${e.value}'),
              visualDensity: VisualDensity.compact,
              backgroundColor: theme.colorScheme.surface.withOpacity(.6),
              side: BorderSide(color: theme.dividerColor.withOpacity(.35)),
            ),
          )
          .toList(),
    );
  }
}

class _IconTextButton extends StatelessWidget {
  const _IconTextButton({required this.icon, required this.label, required this.onPressed});
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      icon: Icon(icon, size: 18),
      label: Text(label),
      onPressed: onPressed,
    );
  }
}

/// Pick a batch from local Hive and return its id (or null if none/aborted).
Future<String?> _pickBatchId(BuildContext context) async {
  final box = Hive.box<BatchModel>(Boxes.batches);
  final batches = box.values.toList();

  if (batches.isEmpty) {
    await showDialog<void>(
      context: context,
      builder: (_) => const AlertDialog(
        title: Text('No batches found'),
        content: Text('Create a batch first, then link your device.'),
      ),
    );
    return null;
  }

  return showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Link to which batch?'),
      content: SizedBox(
        width: 420,
        height: 360,
        child: ListView.builder(
          itemCount: batches.length,
          itemBuilder: (ctx, i) {
            final b = batches[i];
            final id = (b as dynamic).id as String?;
            final name = (b as dynamic).name as String? ?? '(unnamed batch)';
            return ListTile(
              title: Text(name),
              subtitle: id == null ? null : Text(id, style: Theme.of(ctx).textTheme.bodySmall),
              onTap: () => Navigator.pop(ctx, id),
            );
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      ],
    ),
  );
}
