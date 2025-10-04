// lib/widgets/link_device_dialog.dart
import 'dart:math';
import 'package:fermentacraft/utils/firebase_env.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/firestore_paths.dart';

String _rand(int len) {
  const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  final r = Random.secure();
  return List.generate(len, (_) => chars[r.nextInt(chars.length)]).join();
}

enum DeviceType { ispindel, tilt, other }
enum TargetMode { genericUrl, ckbrewCustom }
enum PayloadFormat { json, form }

// ---------- URL builders (short path; no secret in URL) ---------------------

// BrewFather/GravityMon style endpoint, short path:
//   https://log.fermentacraft.com/u/<uid>/d/<deviceId>[?b=<batchId>]
String _buildShortIngestUrl({
  required String base,
  required String uid,
  required String deviceId,
  String? batchId,
}) {
  final b = (batchId != null && batchId.isNotEmpty) ? '?b=${Uri.encodeComponent(batchId)}' : '';
  return '$base/u/$uid/d/$deviceId$b';
}

/// Host for CKBrew Custom (no scheme)
String _ckbrewHost(String base) {
  final uri = Uri.tryParse(base);
  if (uri != null && uri.host.isNotEmpty) return uri.host;
  return base.replaceFirst(RegExp(r'^https?://'), '');
}

/// Path for CKBrew Custom (short path; no secret in URL)
String _ckbrewPath({
  required String uid,
  required String deviceId,
  String? batchId,
}) {
  final b = (batchId != null && batchId.isNotEmpty) ? '?b=${Uri.encodeComponent(batchId)}' : '';
  return '/u/$uid/d/$deviceId$b';
}

// ---------- Small UI helpers ------------------------------------------------

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child, this.trailing});
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.titleMedium;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(top: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: titleStyle)),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

class _CodeField extends StatelessWidget {
  const _CodeField(this.text, {this.maxLines});
  final String text;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(.7),
        borderRadius: BorderRadius.circular(10),
      ),
      child: SelectableText(
        text,
        maxLines: maxLines,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 13.5),
      ),
    );
  }
}

class _CopyBtn extends StatelessWidget {
  const _CopyBtn({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      icon: const Icon(Icons.copy, size: 18),
      label: Text(label),
      onPressed: () async {
        final messenger = ScaffoldMessenger.of(context);
        await Clipboard.setData(ClipboardData(text: value));
        messenger.showSnackBar(SnackBar(content: Text('$label copied')));
      },
    );
  }
}

// Label + code + copy
class _LabeledCodeField extends StatelessWidget {
  const _LabeledCodeField({
    required this.label,
    required this.value,
    this.maxLines,
    this.copyLabel,
  });

  final String label;
  final String value;
  final int? maxLines;
  final String? copyLabel;

  @override
  Widget build(BuildContext context) {
    final copy = copyLabel ?? 'Copy';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        _CodeField(value, maxLines: maxLines),
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _CopyBtn(label: copy, value: value),
          ),
        ),
      ],
    );
  }
}

// ---------- Main dialog -----------------------------------------------------

class LinkDeviceDialog extends StatefulWidget {
  const LinkDeviceDialog({
    super.key,
    this.batchId,
    this.functionsBaseUrl,
  });

  final String? batchId;
  final String? functionsBaseUrl;

  @override
  State<LinkDeviceDialog> createState() => _LinkDeviceDialogState();
}

class _LinkDeviceDialogState extends State<LinkDeviceDialog> {
  final _name = TextEditingController(text: 'Fermenter iSpindel');
  DeviceType _type = DeviceType.ispindel;
  TargetMode _mode = TargetMode.genericUrl;
  PayloadFormat _format = PayloadFormat.json;

  bool _busy = false;
  String? _error;

  String? _deviceId;
  String? _shortUrl; // short ingest URL (no secret)
  String? _ckHost;  // CKBrew Custom host
  String? _ckPath;  // CKBrew Custom path
  String? _secret;  // for headers display

  String get _baseUrl =>
      (widget.functionsBaseUrl?.trim().isNotEmpty ?? false)
          ? widget.functionsBaseUrl!.trim()
          : functionsBaseUrl();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('You must be signed in to link a device.');
      }
      final uid = user.uid;

      // New device id + secret
      final id = FirebaseFirestore.instance.collection('_').doc().id;
      final secret = _rand(32);

      final now = FieldValue.serverTimestamp();
      final name = _name.text.trim().isEmpty ? 'My Device' : _name.text.trim();

      await FirestorePaths.deviceDoc(uid, id).set({
        'id': id,
        'ownerUid': uid,
        'type': switch (_type) {
          DeviceType.ispindel => 'ispindel',
          DeviceType.tilt => 'tilt',
          DeviceType.other => 'other',
        },
        'name': name,
        'displayName': name,
        'secret': secret,
        'linkedBatchId': widget.batchId ?? '',
        'createdAt': now,
        'updatedAt': now,
        'lastSeen': null,
        'lastSg': null,
        'lastTempC': null,
        'battery': null,
      });

      // Compute outputs (short path; no secret in URL)
      final fullUrl = _buildShortIngestUrl(
        base: _baseUrl,
        uid: uid,
        deviceId: id,
        batchId: widget.batchId,
      );
      final host = _ckbrewHost(_baseUrl);
      final path = _ckbrewPath(
        uid: uid,
        deviceId: id,
        batchId: widget.batchId,
      );

      if (!mounted) return;
      setState(() {
        _deviceId = id;
        _shortUrl = fullUrl;
        _ckHost = host;
        _ckPath = path;
        _secret = secret;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showQrCodeDialog() {
    final url = _shortUrl;
    if (url == null) return;
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          title: const Text('Scan URL'),
          content: QrImageView(
            data: url,
            size: 240,
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
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          ],
        );
      },
    );
  }

  String get _contentHeader =>
      _format == PayloadFormat.json
          ? 'Content-Type: application/json'
          : 'Content-Type: application/x-www-form-urlencoded';

  String get _bodyTemplateJson => r'''{
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

  String get _bodyTemplateForm =>
      r'gravity=${gravity}&gravity_unit=SG&temp=${temp}&temp_unit=C&battery=${battery}&angle=${angle}';

  // Sample payloads for curl
  String get _sampleJson =>
      '{"gravity":1.012,"gravity-unit":"G","temp":20.5,"temp_units":"C","battery":3.7,"angle":30}';

  String get _sampleForm =>
      'gravity=1.012&gravity_unit=SG&temp=20.5&temp_unit=C&battery=3.7&angle=30';

  String _curlMacLinux(String url, String secret) {
    final data = _format == PayloadFormat.json ? _sampleJson : _sampleForm;
    return 'curl -i -X POST "$url" '
        '-H "$_contentHeader" '
        '-H "X-Device-Secret: $secret" '
        '--data \'$data\'';
  }

  String _curlWindowsCmd(String url, String secret) {
    final data = _format == PayloadFormat.json
        ? _sampleJson.replaceAll('"', r'\"')
        : _sampleForm;
    return 'curl -i -X POST "$url" '
        '-H "$_contentHeader" '
        '-H "X-Device-Secret: $secret" '
        '--data "$data"';
  }

  @override
  Widget build(BuildContext context) {
    final help = TextStyle(fontSize: 12, color: Theme.of(context).hintColor);
    final hasOutputs = _deviceId != null;

    return AlertDialog(
      title: const Text('Add / Link a Device'),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      actionsPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Tip banner
            Material(
              color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(.6),
              borderRadius: BorderRadius.circular(12),
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.info_outline),
                title: const Text('Heads up'),
                subtitle: Text(
                  'Some firmware UIs show “Test failed (0)” even when live pushes work. '
                  'Use the URL + headers below; your readings will still ingest.',
                  style: help,
                ),
              ),
            ),
            const SizedBox(height: 10),

            if (widget.batchId != null && widget.batchId!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('Batch: ${widget.batchId}', style: help),
              ),

            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Device name',
                hintText: 'e.g. Fermenter #1',
              ),
            ),
            const SizedBox(height: 12),

            // Type + Target
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<DeviceType>(
                    value: _type,
                    items: const [
                      DropdownMenuItem(value: DeviceType.ispindel, child: Text('iSpindel / GravityMon')),
                      DropdownMenuItem(value: DeviceType.tilt, child: Text('Tilt (via bridge)')),
                      DropdownMenuItem(value: DeviceType.other, child: Text('Other / Custom')),
                    ],
                    onChanged: (v) => setState(() => _type = v ?? DeviceType.ispindel),
                    decoration: const InputDecoration(labelText: 'Type'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<TargetMode>(
                    value: _mode,
                    items: const [
                      DropdownMenuItem(value: TargetMode.genericUrl, child: Text('BrewFather URL')),
                      DropdownMenuItem(value: TargetMode.ckbrewCustom, child: Text('CKBrew (Custom)')),
                    ],
                    onChanged: (v) => setState(() => _mode = v ?? TargetMode.genericUrl),
                    decoration: const InputDecoration(labelText: 'Target'),
                  ),
                ),
              ],
            ),

            // Payload format toggle (JSON recommended)
            const SizedBox(height: 12),
            _SectionCard(
              title: 'Payload Format',
              trailing: const Tooltip(
                message: 'JSON recommended. Form is for older bridges.',
                child: Icon(Icons.help_outline, size: 18),
              ),
              child: SegmentedButton<PayloadFormat>(
                segments: const [
                  ButtonSegment(value: PayloadFormat.json, label: Text('JSON (recommended)')),
                  ButtonSegment(value: PayloadFormat.form, label: Text('Form (legacy)')),
                ],
                selected: <PayloadFormat>{_format},
                onSelectionChanged: (s) => setState(() => _format = s.first),
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],

            // ---------- Outputs ----------
            if (hasOutputs) ...[
              const SizedBox(height: 12),

              // Device credentials card
              _SectionCard(
                title: 'Your device credentials',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _LabeledCodeField(label: 'Device ID', value: _deviceId!),
                    const SizedBox(height: 10),
                    _LabeledCodeField(label: 'Secret (header value)', value: _secret!),
                  ],
                ),
              ),

              // Endpoint configuration
              _OutputPanel(
                mode: _mode,
                shortUrl: _shortUrl ?? '',
                ckHost: _ckHost ?? '',
                ckPath: _ckPath ?? '',
                secret: _secret ?? '',
                bodyTemplate: _format == PayloadFormat.json ? _bodyTemplateJson : _bodyTemplateForm,
                contentHeader: _contentHeader,
                onShowQr: _showQrCodeDialog,
              ),

              // Curl test (optional)
              _SectionCard(
                title: 'Optional: test with curl',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('macOS / Linux', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 6),
                    _CodeField(_curlMacLinux(_shortUrl!, _secret!)),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: _CopyBtn(label: 'Copy curl (mac/linux)', value: _curlMacLinux(_shortUrl!, _secret!)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text('Windows CMD', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 6),
                    _CodeField(_curlWindowsCmd(_shortUrl!, _secret!)),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: _CopyBtn(label: 'Copy curl (Windows CMD)', value: _curlWindowsCmd(_shortUrl!, _secret!)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tip: GravityMon’s “Run push test” may show an error even though real background pushes succeed. '
                      'Use these commands to verify the endpoint quickly.',
                      style: help,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        FilledButton.icon(
          icon: _busy
              ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.add),
          label: Text(_deviceId == null ? 'Create device' : 'Create another'),
          onPressed: _busy ? null : _create,
        ),
      ],
    );
  }
}

// New widget to handle the output panels for each mode (uses current format/header)
class _OutputPanel extends StatelessWidget {
  const _OutputPanel({
    required this.mode,
    required this.shortUrl,
    required this.ckHost,
    required this.ckPath,
    required this.secret,
    required this.bodyTemplate,
    required this.contentHeader,
    required this.onShowQr,
  });

  final TargetMode mode;
  final String shortUrl;
  final String ckHost;
  final String ckPath;
  final String secret;
  final String bodyTemplate;
  final String contentHeader;
  final VoidCallback onShowQr;

  @override
  Widget build(BuildContext context) {
    final help = TextStyle(fontSize: 12, color: Theme.of(context).hintColor);
    final secretHeader = 'X-Device-Secret: $secret';

    if (mode == TargetMode.ckbrewCustom) {
      return _SectionCard(
        title: 'CKBrew (Custom) configuration',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _LabeledCodeField(label: 'Server Address', value: ckHost, copyLabel: 'Copy Host'),
            const SizedBox(height: 12),
            _LabeledCodeField(label: 'Path / URL', value: ckPath, maxLines: 3, copyLabel: 'Copy Path'),
            const SizedBox(height: 12),
            _LabeledCodeField(
              label: 'Headers',
              value: '$contentHeader\n$secretHeader',
              maxLines: 2,
              copyLabel: 'Copy Headers',
            ),
            const SizedBox(height: 12),
            _LabeledCodeField(label: 'Body template', value: bodyTemplate, maxLines: 8, copyLabel: 'Copy Body'),
            const SizedBox(height: 8),
            Text(
              'CKBrew → Third-Party → Custom: HTTPS, port 443, POST method. '
              'Add both headers. Body as shown.',
              style: help,
            ),
          ],
        ),
      );
    } else {
      return _SectionCard(
        title: 'BrewFather / GravityMon configuration',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _LabeledCodeField(label: 'Endpoint URL', value: shortUrl, maxLines: 4, copyLabel: 'Copy URL'),
            const SizedBox(height: 12),
            _LabeledCodeField(
              label: 'Headers',
              value: '$contentHeader\n$secretHeader',
              maxLines: 2,
              copyLabel: 'Copy Headers',
            ),
            const SizedBox(height: 12),
            _LabeledCodeField(label: 'Body template', value: bodyTemplate, maxLines: 8, copyLabel: 'Copy Body'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.qr_code, size: 18),
                    label: const Text('Show QR Code'),
                    onPressed: onShowQr,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Paste this URL where the endpoint is requested. Use POST with the headers above. '
              'If your app asks for “Brewfather URL”, this is it.',
              style: help,
            ),
          ],
        ),
      );
    }
  }
}
