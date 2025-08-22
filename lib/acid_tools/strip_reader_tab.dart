// lib/widgets/strip_reader_tab.dart
// ΔE2000 color distance, commit-on-release sampling with fixed 3.2× loupe,
// custom strips with UUIDs (duplicate names OK), remembers last selection,
// clearer help & inline instructions, smooth drag loupe with immediate capture,
// blocks tab/page scrolling while interacting with the image, centered HUD.

import 'dart:async';
import 'dart:io' show File, Platform;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

/// ========= CIELAB + ΔE2000 (top-level, private) =========

class _Lab {
  final double l, a, b;
  const _Lab(this.l, this.a, this.b);
}

final Map<int, _Lab> _labCache = {}; // Color.value -> Lab

_Lab _labFor(Color c) {
  return _labCache.putIfAbsent(c.value, () {
    double sr = c.red / 255.0, sg = c.green / 255.0, sb = c.blue / 255.0;
    double lin(double u) =>
        (u <= 0.04045) ? (u / 12.92) : math.pow((u + 0.055) / 1.055, 2.4).toDouble();
    final r = lin(sr), g = lin(sg), b = lin(sb);

    final x = 0.4124564 * r + 0.3575761 * g + 0.1804375 * b;
    final y = 0.2126729 * r + 0.7151522 * g + 0.0721750 * b;
    final z = 0.0193339 * r + 0.1191920 * g + 0.9503041 * b;

    double f(double t) {
      const e = 216.0 / 24389.0;
      const k = 24389.0 / 27.0;
      return t > e ? math.pow(t, 1.0 / 3.0).toDouble() : (k * t + 16.0) / 116.0;
    }

    final fx = f(x / 0.95047);
    final fy = f(y / 1.00000);
    final fz = f(z / 1.08883);

    final l = 116.0 * fy - 16.0;
    final a = 500.0 * (fx - fy);
    final b2 = 200.0 * (fy - fz);
    return _Lab(l, a, b2);
  });
}

double _deltaE2000(_Lab p, _Lab q) {
  final l1 = p.l, a1 = p.a, b1 = p.b;
  final l2 = q.l, a2 = q.a, b2 = q.b;

  final avgLp = 0.5 * (l1 + l2);
  final c1 = math.sqrt(a1 * a1 + b1 * b1);
  final c2 = math.sqrt(a2 * a2 + b2 * b2);
  final avgC = 0.5 * (c1 + c2);

  // FIXED: removed one trailing ')' here
  final g = 0.5 * (1 - math.sqrt(
    math.pow(avgC, 7) / (math.pow(avgC, 7) + math.pow(25.0, 7)),
  ));
  final a1p = (1 + g) * a1;
  final a2p = (1 + g) * a2;
  final c1p = math.sqrt(a1p * a1p + b1 * b1);
  final c2p = math.sqrt(a2p * a2p + b2 * b2);
  final avgCp = 0.5 * (c1p + c2p);

  double hp(double a, double b) {
    if (a == 0 && b == 0) return 0;
    final h = math.atan2(b, a) * 180 / math.pi;
    return (h >= 0) ? h : (h + 360);
  }

  final h1p = hp(a1p, b1);
  final h2p = hp(a2p, b2);

  double dHp;
  final dh = h2p - h1p;
  if (c1p * c2p == 0) {
    dHp = 0;
  } else if (dh.abs() <= 180) {
    dHp = dh;
  } else if (dh > 180) {
    dHp = dh - 360;
  } else {
    dHp = dh + 360;
  }

  final dLp = l2 - l1;
  final dCp = c2p - c1p;
  final dHpPrime = 2 * math.sqrt(c1p * c2p) * math.sin((dHp * math.pi / 180) / 2);

  double avgHp;
  if (c1p * c2p == 0) {
    avgHp = h1p + h2p;
  } else if ((h1p - h2p).abs() <= 180) {
    avgHp = 0.5 * (h1p + h2p);
  } else {
    avgHp = 0.5 * (h1p + h2p + 360 * ((h1p + h2p) < 360 ? 1 : -1));
  }

  final t = 1
      - 0.17 * math.cos((avgHp - 30) * math.pi / 180)
      + 0.24 * math.cos((2 * avgHp) * math.pi / 180)
      + 0.32 * math.cos((3 * avgHp + 6) * math.pi / 180)
      - 0.20 * math.cos((4 * avgHp - 63) * math.pi / 180);

  final dRo = 30 * math.exp(-math.pow((avgHp - 275) / 25, 2));
  // FIXED: removed one trailing ')' here
  final rc = 2 * math.sqrt(
    math.pow(avgCp, 7) / (math.pow(avgCp, 7) + math.pow(25.0, 7)),
  );
  final sl = 1 + (0.015 * math.pow(avgLp - 50, 2)) / math.sqrt(20 + math.pow(avgLp - 50, 2));
  final sc = 1 + 0.045 * avgCp;
  final sh = 1 + 0.015 * avgCp * t;
  final rt = -math.sin(2 * dRo * math.pi / 180) * rc;

  const kL = 1.0, kC = 1.0, kH = 1.0;
  final termL = dLp / (kL * sl);
  final termC = dCp / (kC * sc);
  final termH = dHpPrime / (kH * sh);

  return math.sqrt(termL * termL + termC * termC + termH * termH + rt * termC * termH);
}


class _RefLab {
  final ReferencePoint ref;
  final _Lab lab;
  _RefLab(this.ref, this.lab);
}

/// -----------------------------
/// Model for custom strips (stored as Maps in Hive)
/// -----------------------------
class PHStrip {
  final String id;           // UUID
  String name;               // display label (not unique)
  List<double> phValues;     // low → high
  String? brand;

  PHStrip({
    required this.id,
    required this.name,
    required this.phValues,
    this.brand,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'ph': phValues,
        'brand': brand,
      };

  static PHStrip fromMap(Map data) => PHStrip(
        id: data['id'] as String,
        name: data['name'] as String,
        phValues: (data['ph'] as List).map((e) => (e as num).toDouble()).toList(),
        brand: data['brand'] as String?,
      );
}

class StripPreset {
  final String name;
  final List<double> phValues;
  const StripPreset(this.name, this.phValues);
}

class ReferencePoint {
  final double ph;
  Color? color;
  Offset? location;
  ReferencePoint({required this.ph, this.color, this.location});
}

const List<StripPreset> kStripPresets = [
  StripPreset('Vintner\'s Best pH 2.8–4.4', [2.8, 3.2, 3.6, 4.0, 4.4]),
  StripPreset('Viva pH 4.0–7.0', [4.0, 4.5, 5.0, 5.5, 6.0, 6.5, 7.0]),
  StripPreset('Hydrion pH 3.0–5.5', [3.0, 3.4, 3.8, 4.2, 4.6, 5.0, 5.5]),
  StripPreset('Universal pH 1.0–14.0', [1, 3, 5, 7, 9, 11, 14]),
];

class TapSquareOverlay extends StatelessWidget {
  final Offset location;
  final Color color;
  final Color borderColor;
  const TapSquareOverlay({
    super.key,
    required this.location,
    required this.color,
    this.borderColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: location.dx - 10,
      top: location.dy - 10,
      child: Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: color,
          border: Border.all(color: borderColor, width: 2.0),
          borderRadius: BorderRadius.circular(2),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
        ),
      ),
    );
  }
}

/// --------------------------------------
/// Magnifier (loupe) painter
/// --------------------------------------
class _LoupePainter extends CustomPainter {
  final ui.Image image;
  final Rect imageRect;
  final Offset tapPos;
  final double zoom; // fixed 3.2×
  final double size;

  _LoupePainter({
    required this.image,
    required this.imageRect,
    required this.tapPos,
    required this.zoom,
    required this.size,
  });

  @override
  void paint(Canvas canvas, Size s) {
    final r = Rect.fromLTWH(0, 0, size, size);
    final clipPath = Path()..addRRect(RRect.fromRectAndRadius(r, const Radius.circular(14)));
    canvas.save();
    canvas.clipPath(clipPath);

    final dx = (tapPos.dx - imageRect.left).clamp(0, imageRect.width);
    final dy = (tapPos.dy - imageRect.top).clamp(0, imageRect.height);
    final px = dx / imageRect.width * image.width;
    final py = dy / imageRect.height * image.height;

    final srcW = image.width / zoom;
    final srcH = image.height / zoom;
    final srcLeft = (px - srcW / 2).clamp(0.0, image.width - srcW);
    final srcTop  = (py - srcH / 2).clamp(0.0, image.height - srcH);
    final src = Rect.fromLTWH(srcLeft, srcTop, srcW, srcH);

    final paint = Paint()..isAntiAlias = true;
    canvas.drawImageRect(image, src, r, paint);

    final cross = Paint()
      ..color = Colors.white
      ..strokeWidth = 2;
    final mid = size / 2;
    canvas.drawLine(Offset(mid, 4), Offset(mid, size - 4), cross);
    canvas.drawLine(Offset(4, mid), Offset(size - 4, mid), cross);

    final border = Paint()
      ..color = Colors.black.withOpacity(0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(14)), border);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LoupePainter old) =>
      old.image != image ||
      old.imageRect != imageRect ||
      old.tapPos != tapPos ||
      old.zoom != zoom ||
      old.size != size;
}

class _StripChoice {
  final String id;    // 'preset:<name>' | 'custom:<uuid>' | 'divider' | 'custom:new'
  final String label; // display text
  final bool enabled;
  const _StripChoice(this.id, this.label, {this.enabled = true});
}

/// --------------------------------------
/// Main widget
/// --------------------------------------
class StripReaderTab extends StatefulWidget {
  const StripReaderTab({super.key});
  @override
  State<StripReaderTab> createState() => _StripReaderTabState();
}

class _StripReaderTabState extends State<StripReaderTab> {
  final ImagePicker _picker = ImagePicker();
  final GlobalKey _imageContainerKey = GlobalKey();
  final _uuid = const Uuid();

Widget _buildQuickStartCard(BuildContext context) {
  return Container(
    padding: const EdgeInsets.all(12),
    margin: const EdgeInsets.only(bottom: 16),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primary.withAlpha(13),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(
        color: Theme.of(context).colorScheme.primary.withAlpha(51),
      ),
    ),
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Quick Start 🧪', style: TextStyle(fontWeight: FontWeight.bold)),
        SizedBox(height: 8),
        Text('1) Choose a preset or saved custom.'),
        Text('2) Upload one photo with BOTH strip and color key.'),
        Text('3) Long-press to aim the crosshair; lift to record.'),
        SizedBox(height: 6),
        Text('Need details? Tap the Help icon ↑ for the full guide.'),
      ],
    ),
  );
}

void _showCustomsDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (dialogCtx) => AlertDialog(
      title: const Text('Custom pH strips'),
      content: SizedBox(
        width: 520,
        height: 360,
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('New'),
                onPressed: () => _promptCustomStripSetup(),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: _customs.length,
                itemBuilder: (_, i) {
                  final s = _customs[i];
                  return ListTile(
                    title: Text(s.name),
                    subtitle: Text(
                      'pH: ${s.phValues.map((e) => e.toStringAsFixed(1)).join(' • ')}'
                      '${s.brand == null ? '' : ' · ${s.brand}'}',
                    ),
                    trailing: Wrap(
                      spacing: 8,
                      children: [
                        IconButton(
                          tooltip: 'Edit',
                          icon: const Icon(Icons.edit),
                          onPressed: () => _promptCustomStripSetup(existing: s),
                        ),
                        IconButton(
                          tooltip: 'Delete',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            final ok = await showDialog<bool>(
                              context: dialogCtx,
                              builder: (confirmCtx) => AlertDialog(
                                title: const Text('Delete strip?'),
                                content: Text('Remove “${s.name}” permanently?'),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(confirmCtx).pop(false),
                                    child: const Text('Cancel'),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.of(confirmCtx).pop(true),
                                    child: const Text('Delete'),
                                  ),
                                ],
                              ),
                            );
                            if (ok == true) {
                              await _deleteCustom(s.id);
                              if (_selectedChoiceId == 'custom:${s.id}') {
                                setState(() {
                                  _selectedChoiceId = null;
                                  _prefsBox.delete(_prefsLastChoiceKey);
                                  _refs.clear();
                                  _testPoint = null;
                                  _estimatedPH = null;
                                });
                              }
                            }
                          },
                        ),
                      ],
                    ),
                    onTap: () {
                      Navigator.of(dialogCtx).pop();
                      _applySelectedChoice('custom:${s.id}');
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogCtx).pop(),
          child: const Text('Close'),
        )
      ],
    ),
  );
}

Widget _buildControlsRow(BuildContext context) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // LEFT: dropdown + Custom Strips button directly underneath
      Expanded(
        flex: 3,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              value: _selectedChoiceId,
              isExpanded: true,
              items: _choices.map((c) {
                return DropdownMenuItem<String>(
                  value: c.enabled ? c.id : null,
                  enabled: c.enabled,
                  child: Text(
                    c.label,
                    style: TextStyle(color: c.enabled ? null : Colors.grey),
                  ),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) _applySelectedChoice(val);
              },
              decoration: const InputDecoration(
                labelText: 'Select Strip Brand / Custom',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.settings),
                label: const Text('Custom Strips'),
                onPressed: () => _showCustomsDialog(context),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(width: 12),
      // RIGHT: Upload + Reset
      Column(
        children: [
          ElevatedButton(
            onPressed: _getImage,
            child: const Text('Upload Image'),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: _resetAll,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade100,
              foregroundColor: Colors.red.shade800,
            ),
            child: const Text('Reset'),
          ),
        ],
      ),
    ],
  );
}


  Uint8List? _imageBytes;
  img.Image? _decoded;
  ui.Image? _uiImage;

  String? _selectedChoiceId;
  List<ReferencePoint> _refs = [];
  ReferencePoint? _testPoint;
  double? _estimatedPH;

  late final Box _customBox;
  late final Box _prefsBox;
  static const _customBoxName = 'ph_strips';
  static const _prefsBoxName = 'ph_reader_prefs';
  static const _prefsLastChoiceKey = 'last_choice_id';

  List<PHStrip> _customs = [];

  bool _showLoupe = false;
  bool _isSampling = false;
  Offset _loupeAnchor = const Offset(0, 0);
  static const double _loupeSize = 140;
  static const double _loupeZoom = 3.2;

  List<_StripChoice> get _choices {
    final items = <_StripChoice>[
      ...kStripPresets.map((p) => _StripChoice('preset:${p.name}', p.name)),
    ];
    if (_customs.isNotEmpty) {
      items.add(const _StripChoice('divider', '— Saved custom —', enabled: false));
      items.addAll(_customs.map((c) => _StripChoice('custom:${c.id}', c.name)));
    }
    items.add(const _StripChoice('custom:new', 'Custom / Not Listed'));
    return items;
  }

  ReferencePoint? get _nextRef {
    try { return _refs.firstWhere((p) => p.color == null); } catch (_) { return null; }
  }

  @override
  void initState() {
    super.initState();
    _initBoxes();
  }

  Future<void> _initBoxes() async {
    _customBox = await Hive.openBox(_customBoxName);
    _prefsBox  = await Hive.openBox(_prefsBoxName);

    _loadCustoms();
    _customBox.watch().listen((_) => _loadCustoms());

    final saved = _prefsBox.get(_prefsLastChoiceKey) as String?;
    if (saved != null) {
      _applySelectedChoice(saved, persist: false);
    }
  }

  void _loadCustoms() {
    final list = <PHStrip>[];
    for (final k in _customBox.keys) {
      final m = _customBox.get(k);
      if (m is Map) list.add(PHStrip.fromMap(m));
    }
    setState(() => _customs = list);

    if (_selectedChoiceId?.startsWith('custom:') == true) {
      final id = _selectedChoiceId!.substring(7);
      final exists = _customs.any((c) => c.id == id);
      if (!exists) {
        setState(() {
          _selectedChoiceId = null;
          _prefsBox.delete(_prefsLastChoiceKey);
          _refs.clear();
          _testPoint = null;
          _estimatedPH = null;
        });
      }
    }
  }

  Future<void> _saveCustom(PHStrip s) async => _customBox.put(s.id, s.toMap());
  Future<void> _deleteCustom(String id) async => _customBox.delete(id);

  void _applySelectedChoice(String choiceId, {bool persist = true}) {
    if (choiceId == 'custom:new') {
      _promptCustomStripSetup();
      return;
    }

    if (choiceId.startsWith('preset:')) {
      final name = choiceId.substring(7);
      final preset = kStripPresets.firstWhere(
        (e) => e.name == name,
        orElse: () => const StripPreset('Custom', []),
      );
      setState(() {
        _selectedChoiceId = choiceId;
        _refs = preset.phValues.map((ph) => ReferencePoint(ph: ph)).toList();
        _testPoint = null;
        _estimatedPH = null;
      });
    } else if (choiceId.startsWith('custom:')) {
      final id = choiceId.substring(7);
      final c = _customs.firstWhere(
        (e) => e.id == id,
        orElse: () => PHStrip(id: '', name: '', phValues: const []),
      );
      if (c.id.isEmpty) return;
      setState(() {
        _selectedChoiceId = choiceId;
        _refs = c.phValues.map((ph) => ReferencePoint(ph: ph)).toList();
        _testPoint = null;
        _estimatedPH = null;
      });
    } else if (choiceId == 'divider') {
      return;
    }

    if (persist) _prefsBox.put(_prefsLastChoiceKey, _selectedChoiceId);
  }

  void _resetAll() {
    setState(() {
      _estimatedPH = null;
      _refs = _refs.map((r) => ReferencePoint(ph: r.ph)).toList();
      _testPoint = null;
    });
  }

  void _showHelp() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: ListView(
          children: [
            Text('How to read a pH test strip', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text(
              '1) Put BOTH the test strip and the printed color key in the SAME photo.\n'
              '2) Use even, neutral lighting. Keep both flat and parallel to the camera.\n'
              '3) Select a preset or saved custom, then upload the photo.\n'
              '4) Record key squares: press & drag to aim the crosshair, then LIFT to save.\n'
              '   • Go left→right (or low→high). Tap a swatch to clear mistakes.\n'
              '5) Measure the strip: press & drag to aim, then LIFT to save.\n'
              '6) Estimated pH appears centered. Re-sample anytime.',
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset('assets/phstrip_help.png', fit: BoxFit.contain),
            ),
            const SizedBox(height: 8),
            const Text('Reference: strip and color key in the same shot.', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            const Text(
              'Tips:\n'
              '• If colors look “off”, try daylight or change surfaces.\n'
              '• Save your own strip keys under “Custom Strips” — duplicate names are OK.\n'
              '• You can drag immediately; the page won’t scroll while you’re over the photo.',
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _processPickedFile(XFile? pickedFile) async {
    if (pickedFile == null) return;
    final file = File(pickedFile.path);
    final bytes = await file.readAsBytes();

    final im = img.decodeImage(bytes);
    final completer = Completer<ui.Image>();
    ui.decodeImageFromList(bytes, (ui.Image v) => completer.complete(v));
    final uimg = await completer.future;

    if (im != null) {
      setState(() {
        _imageBytes = bytes;
        _decoded = im;
        _uiImage = uimg;
      });
    }
  }

  Future<void> _getImage() async {
    if (kIsWeb) return;
    if (Platform.isAndroid || Platform.isIOS) {
      await showModalBottomSheet<void>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Wrap(children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Camera'),
              onTap: () async {
                Navigator.of(ctx).pop();
                final pf = await _picker.pickImage(source: ImageSource.camera, maxWidth: 1600);
                await _processPickedFile(pf);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Gallery'),
              onTap: () async {
                Navigator.of(ctx).pop();
                final pf = await _picker.pickImage(source: ImageSource.gallery, maxWidth: 1600);
                await _processPickedFile(pf);
              },
            ),
          ]),
        ),
      );
    } else {
      final result = await FilePicker.platform.pickFiles(type: FileType.image);
      if (result != null && result.files.single.path != null) {
        await _processPickedFile(XFile(result.files.single.path!));
      }
    }
  }

  Rect? _imageRect() {
    final rb = _imageContainerKey.currentContext?.findRenderObject() as RenderBox?;
    if (rb == null || _decoded == null) return null;

    final box = rb.size;
    final imgAR = _decoded!.width / _decoded!.height;
    final boxAR = box.width / box.height;

    double w, h;
    if (imgAR > boxAR) { w = box.width; h = w / imgAR; }
    else { h = box.height; w = h * imgAR; }
    final ox = (box.width - w) / 2;
    final oy = (box.height - h) / 2;
    return Rect.fromLTWH(ox, oy, w, h);
  }

  Color _regionColor(img.Image image, int cx, int cy, {int radius = 2}) {
    num r = 0, g = 0, b = 0;
    int count = 0;
    for (int dx = -radius; dx <= radius; dx++) {
      for (int dy = -radius; dy <= radius; dy++) {
        final x = cx + dx, y = cy + dy;
        if (x >= 0 && x < image.width && y >= 0 && y < image.height) {
          final p = image.getPixel(x, y);
          r += math.pow(p.r / 255.0, 2.2);
          g += math.pow(p.g / 255.0, 2.2);
          b += math.pow(p.b / 255.0, 2.2);
          count++;
        }
      }
    }
    if (count == 0) return Colors.transparent;
    return Color.fromARGB(
      255,
      (math.pow(r / count, 1 / 2.2) * 255).round().clamp(0, 255),
      (math.pow(g / count, 1 / 2.2) * 255).round().clamp(0, 255),
      (math.pow(b / count, 1 / 2.2) * 255).round().clamp(0, 255),
    );
  }

  Offset _globalToLocal(Offset global) {
    final rb = _imageContainerKey.currentContext?.findRenderObject() as RenderBox?;
    return rb?.globalToLocal(global) ?? global;
  }

  void _startSample(Offset localPosition) {
    setState(() {
      _isSampling = true;
      _loupeAnchor = localPosition;
      _showLoupe = true;
    });
  }

  void _moveSample(Offset localPosition) {
    if (!_isSampling) return;
    setState(() { _loupeAnchor = localPosition; });
  }

  Color _colorAtLocal(Offset localPosition) {
    if (_decoded == null) return Colors.transparent;
    final rect = _imageRect();
    if (rect == null || !rect.contains(localPosition)) return Colors.transparent;

    final dx = localPosition.dx - rect.left;
    final dy = localPosition.dy - rect.top;
    final x = (dx * (_decoded!.width / rect.width)).round();
    final y = (dy * (_decoded!.height / rect.height)).round();
    if (x < 0 || y < 0 || x >= _decoded!.width || y >= _decoded!.height) return Colors.transparent;

    return _regionColor(_decoded!, x, y);
  }

  void _commitSample() {
    if (!_isSampling) return;
    if (_decoded == null) {
      setState(() { _isSampling = false; _showLoupe = false; });
      return;
    }
    final color = _colorAtLocal(_loupeAnchor);
    setState(() {
      if (color != Colors.transparent) {
        final nextRef = _nextRef;
        if (nextRef != null) {
          nextRef.color = color;
          nextRef.location = _loupeAnchor;
        } else {
          _testPoint = ReferencePoint(ph: 0, color: color, location: _loupeAnchor);
        }
        _updatePH();
      }
      _isSampling = false;
      _showLoupe = false;
    });
  }

  void _cancelSample() {
    if (!_isSampling) return;
    setState(() { _isSampling = false; _showLoupe = false; });
  }

  void _updatePH() {
    final refs = _refs.where((r) => r.color != null).toList();
    if (_testPoint?.color != null && refs.length >= 2) {
      final v = _interpolatePH(_testPoint!.color!, refs);
      _estimatedPH = v >= 0 ? v : null;
    } else {
      _estimatedPH = null;
    }
  }

  double _interpolatePH(Color target, List<ReferencePoint> refs) {
    if (refs.length < 2) return -1;

    final labTarget = _labFor(target);
    final pairs = <_RefLab>[];
    for (final r in refs) {
      if (r.color == null) continue;
      pairs.add(_RefLab(r, _labFor(r.color!)));
    }
    if (pairs.length < 2) return -1;

    pairs.sort((a, b) =>
        _deltaE2000(labTarget, a.lab).compareTo(_deltaE2000(labTarget, b.lab)));

    final r1 = pairs[0].ref;
    final r2 = pairs[1].ref;
    final d1 = _deltaE2000(labTarget, pairs[0].lab);
    final d2 = _deltaE2000(labTarget, pairs[1].lab);

    if (d1 + d2 < 1e-6) return r1.ph;

    final w1 = 1 / (d1 + 1e-9);
    final w2 = 1 / (d2 + 1e-9);
    return (r1.ph * w1 + r2.ph * w2) / (w1 + w2);
  }

  void _promptCustomStripSetup({PHStrip? existing}) {
    final name  = TextEditingController(text: existing?.name ?? '');
    final brand = TextEditingController(text: existing?.brand ?? '');
    final phTxt = TextEditingController(
      text: (existing?.phValues ?? []).map((e) => e.toStringAsFixed(1)).join(', '),
    );

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(existing == null ? 'New custom strip' : 'Edit custom strip'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(decoration: const InputDecoration(labelText: 'Name'),  controller: name),
              TextField(decoration: const InputDecoration(labelText: 'Brand (optional)'), controller: brand),
              TextField(
                controller: phTxt,
                decoration: const InputDecoration(
                  labelText: 'pH values (comma-separated, low→high)',
                  hintText: 'e.g. 2.8, 3.2, 3.6, 4.0, 4.4',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogCtx).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final nav = Navigator.of(dialogCtx);

              final parts = phTxt.text
                  .split(',')
                  .map((s) => double.tryParse(s.trim()))
                  .whereType<double>()
                  .toList()
                ..sort();

              if (parts.isEmpty || name.text.trim().isEmpty) return;

              late final PHStrip s;
              if (existing == null) {
                s = PHStrip(
                  id: _uuid.v4(),
                  name: name.text.trim(),
                  phValues: parts,
                  brand: brand.text.trim().isEmpty ? null : brand.text.trim(),
                );
              } else {
                s = existing
                  ..name = name.text.trim()
                  ..phValues = parts
                  ..brand = brand.text.trim().isEmpty ? null : brand.text.trim();
              }

              await _saveCustom(s);

              setState(() {
                _selectedChoiceId = 'custom:${s.id}';
                _refs = s.phValues.map((e) => ReferencePoint(ph: e)).toList();
                _testPoint = null;
                _estimatedPH = null;
              });
              _prefsBox.put(_prefsLastChoiceKey, _selectedChoiceId);

              nav.pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  String _instructionText() {
    if (_selectedChoiceId == null) {
      return 'Select your strip brand (or a saved custom), then upload a photo.';
    }
    if (_imageBytes == null) {
      return 'Upload a photo that shows BOTH the test strip and the color key.';
    }
    final next = _nextRef;
    if (next != null) {
      return 'Press, drag to aim at the square for pH ${next.ph.toStringAsFixed(2)}, then LIFT to record.';
    }
    if (_testPoint == null) {
      return 'All reference colors recorded. Press, drag to aim at your strip pad, then LIFT to measure.';
    }
    return 'Measurement saved. Drag again to re-sample, or tap a swatch to clear.';
  }

  @override
  Widget build(BuildContext context) {
    // Note: keep page scroll enabled globally, but we EAGERLY capture drags over the image
    // by handling both horizontal & vertical drag gestures below.
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
  children: [
    Text('pH Strip Reader', style: Theme.of(context).textTheme.titleLarge),
    const Spacer(),
    IconButton(
      tooltip: 'How this tool works',
      icon: const Icon(Icons.help_outline),
      onPressed: _showHelp,
    ),
  ],
),

// Shorter Quick Start
_buildQuickStartCard(context),

// Controls with Custom Strips under the dropdown
_buildControlsRow(context),

          const SizedBox(height: 16),

          if (_refs.isNotEmpty)
            SizedBox(
              height: 64,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _refs.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final p = _refs[i];
                  final isNext = p == _nextRef;
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        p.color = null;
                        p.location = null;
                        _updatePH();
                      });
                    },
                    child: Column(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: p.color ?? Colors.grey.shade300,
                            border: Border.all(
                              color: isNext ? Theme.of(context).primaryColor : Colors.black26,
                              width: isNext ? 2.5 : 1.0,
                            ),
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(p.ph.toStringAsFixed(2), style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  );
                },
              ),
            ),

          const SizedBox(height: 8),

          Center(
            child: Text(
              _instructionText(),
              style: TextStyle(fontStyle: FontStyle.italic, color: Theme.of(context).colorScheme.secondary),
              textAlign: TextAlign.center,
            ),
          ),

          const SizedBox(height: 8),

          if (_imageBytes != null && _decoded != null && _uiImage != null)
            AspectRatio(
              aspectRatio: _decoded!.width / _decoded!.height,
              child: RepaintBoundary(
                key: _imageContainerKey,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,

                  // Claim BOTH axes immediately so TabBarView / ScrollView won't steal the gesture:
                  onHorizontalDragStart: (d) => _startSample(_globalToLocal(d.globalPosition)),
                  onHorizontalDragUpdate: (d) => _moveSample(_globalToLocal(d.globalPosition)),
                  onHorizontalDragEnd: (_) => _commitSample(),

                  onVerticalDragStart: (d) => _startSample(_globalToLocal(d.globalPosition)),
                  onVerticalDragUpdate: (d) => _moveSample(_globalToLocal(d.globalPosition)),
                  onVerticalDragEnd: (_) => _commitSample(),

                  // Optional: long-press path still supported
                  onLongPressStart: (d) => _startSample(_globalToLocal(d.globalPosition)),
                  onLongPressMoveUpdate: (d) => _moveSample(_globalToLocal(d.globalPosition)),
                  onLongPressEnd: (_) => _commitSample(),

                  // Single tap commit
                  onTapDown: (d) => _startSample(d.localPosition),
                  onTapUp: (_) => _commitSample(),
                  onTapCancel: _cancelSample,

                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.memory(_imageBytes!, fit: BoxFit.contain),

                      ..._refs
                          .where((r) => r.color != null && r.location != null)
                          .map((r) => TapSquareOverlay(location: r.location!, color: r.color!, borderColor: Colors.white)),

                      if (_testPoint?.location != null)
                        GestureDetector(
                          onTap: () => setState(() { _testPoint = null; _updatePH(); }),
                          child: TapSquareOverlay(
                            location: _testPoint!.location!,
                            color: _testPoint!.color!,
                            borderColor: Colors.greenAccent,
                          ),
                        ),

                      if (_showLoupe)
                        Positioned(
                          left: (_loupeAnchor.dx - _loupeSize / 2).clamp(0, double.infinity),
                          top: (_loupeAnchor.dy - _loupeSize - 16).clamp(0, double.infinity),
                          child: CustomPaint(
                            size: const Size(_loupeSize, _loupeSize),
                            painter: _LoupePainter(
                              image: _uiImage!,
                              imageRect: _imageRect()!,
                              tapPos: _loupeAnchor,
                              zoom: _loupeZoom,
                              size: _loupeSize,
                            ),
                          ),
                        ),

                      if (!_showLoupe && _estimatedPH != null && _testPoint?.color != null)
                        Positioned.fill(
                          child: IgnorePointer(
                            ignoring: true,
                            child: Container(color: Colors.black.withOpacity(0.12)),
                          ),
                        ),

                      if (!_showLoupe && _estimatedPH != null && _testPoint?.color != null)
                        Align(
                          alignment: Alignment.center,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.60),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 28, height: 28,
                                  decoration: BoxDecoration(
                                    color: _testPoint!.color!,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: Colors.white, width: 2),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  'pH ${_estimatedPH!.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            )
          else
            Container(height: 200, alignment: Alignment.center, child: const Text('Upload an image to begin.')),
        ],
      ),
    );
  }
}
