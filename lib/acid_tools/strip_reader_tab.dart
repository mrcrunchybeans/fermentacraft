import 'dart:io' show File, Platform;
import 'dart:typed_data';
import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;

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

class StripReaderTab extends StatefulWidget {
  const StripReaderTab({super.key});

  @override
  State<StripReaderTab> createState() => _StripReaderTabState();
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

const List<StripPreset> stripPresets = [
  StripPreset('Vintner\'s Best pH 2.8–4.4', [2.8, 3.2, 3.6, 4.0, 4.4]),
  StripPreset('Viva pH 4.0–7.0', [4.0, 4.5, 5.0, 5.5, 6.0, 6.5, 7.0]),
  StripPreset('Hydrion pH 3.0–5.5', [3.0, 3.4, 3.8, 4.2, 4.6, 5.0, 5.5]),
  StripPreset('Universal pH 1.0–14.0', [1, 3, 5, 7, 9, 11, 14]),
];

class _StripReaderTabState extends State<StripReaderTab> {
  String? selectedBrand;
  File? selectedImage;
  Uint8List? selectedImageBytes;
  img.Image? decodedImage;
  List<ReferencePoint> referencePoints = [];
  double? estimatedPH;
  final GlobalKey _imageContainerKey = GlobalKey();
  ReferencePoint? testStripPoint;

  ReferencePoint? get _nextReferenceToSelect {
    try {
      return referencePoints.firstWhere((p) => p.color == null);
    } catch (e) {
      return null;
    }
  }

  void _resetAll() {
    setState(() {
      estimatedPH = null;
      referencePoints =
          referencePoints.map((r) => ReferencePoint(ph: r.ph)).toList();
      testStripPoint = null;
    });
  }

  final List<String> knownBrands = [
    'Vintner\'s Best pH 2.8–4.4',
    'Viva pH 4.0–7.0',
    'Hydrion pH 3.0–5.5',
    'Universal pH 1.0–14.0',
    'Custom / Not Listed',
  ];

  final ImagePicker _picker = ImagePicker();

  void _promptCustomStripSetup() {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Custom Strip Setup"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: "Enter pH values (comma-separated)",
            hintText: "e.g. 3.2,3.6,4.0",
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        actions: [
          TextButton(
            child: const Text("Cancel"),
            onPressed: () => Navigator.of(context).pop(),
          ),
          TextButton(
            child: const Text("OK"),
            onPressed: () {
              final parts = controller.text
                  .split(',')
                  .map((s) => double.tryParse(s.trim()))
                  .whereType<double>()
                  .toList();
              
              parts.sort();

              setState(() {
                referencePoints =
                    parts.map((ph) => ReferencePoint(ph: ph)).toList();
              });

              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }

  Future<void> _processPickedFile(XFile? pickedFile) async {
    if (pickedFile == null) return;
    
    final file = File(pickedFile.path);
    final bytes = await file.readAsBytes();
    final image = img.decodeImage(bytes);
    if (image != null) {
      setState(() {
        selectedImage = file;
        selectedImageBytes = bytes;
        decodedImage = image;
      });
    }
  }

  Future<void> _getImage() async {
    if (kIsWeb) return;

    if (Platform.isAndroid || Platform.isIOS) {
      await showModalBottomSheet<void>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: const Text('Camera'),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  final pickedFile = await _picker.pickImage(
                      source: ImageSource.camera, maxWidth: 800);
                  await _processPickedFile(pickedFile);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Gallery'),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  final pickedFile = await _picker.pickImage(
                      source: ImageSource.gallery, maxWidth: 800);
                  await _processPickedFile(pickedFile);
                },
              ),
            ],
          ),
        ),
      );
    } else {
      final result = await FilePicker.platform.pickFiles(type: FileType.image);
      if (result != null && result.files.single.path != null) {
        await _processPickedFile(XFile(result.files.single.path!));
      }
    }
  }

  Color _imgColorToFlutterFromRegion(img.Image image, int centerX, int centerY,
      {int radius = 2}) {
    num r = 0, g = 0, b = 0;
    int count = 0;

    for (int dx = -radius; dx <= radius; dx++) {
      for (int dy = -radius; dy <= radius; dy++) {
        int x = centerX + dx;
        int y = centerY + dy;

        if (x >= 0 && x < image.width && y >= 0 && y < image.height) {
          final pixel = image.getPixel(x, y);
          r += pow(pixel.r / 255.0, 2.2);
          g += pow(pixel.g / 255.0, 2.2);
          b += pow(pixel.b / 255.0, 2.2);
          count++;
        }
      }
    }

    if (count == 0) return Colors.transparent;

    return Color.fromARGB(
      255,
      (pow(r / count, 1 / 2.2) * 255).round().clamp(0, 255),
      (pow(g / count, 1 / 2.2) * 255).round().clamp(0, 255),
      (pow(b / count, 1 / 2.2) * 255).round().clamp(0, 255),
    );
  }

  Rect? _getImageDisplayRect() {
    final RenderBox? renderBox =
        _imageContainerKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || decodedImage == null) return null;

    final Size boxSize = renderBox.size;
    final double imageAspectRatio = decodedImage!.width / decodedImage!.height;
    final double containerAspectRatio = boxSize.width / boxSize.height;

    double displayWidth, displayHeight;

    if (imageAspectRatio > containerAspectRatio) {
      displayWidth = boxSize.width;
      displayHeight = boxSize.width / imageAspectRatio;
    } else {
      displayHeight = boxSize.height;
      displayWidth = boxSize.height * imageAspectRatio;
    }

    final double offsetX = (boxSize.width - displayWidth) / 2;
    final double offsetY = (boxSize.height - displayHeight) / 2;

    return Rect.fromLTWH(offsetX, offsetY, displayWidth, displayHeight);
  }

  void _handleTapOnImage(Offset localPosition, BuildContext context) {
    if (decodedImage == null) return;

    final Rect? imageRect = _getImageDisplayRect();
    if (imageRect == null || !imageRect.contains(localPosition)) {
      return;
    }

    final double tappedXInImageRect = localPosition.dx - imageRect.left;
    final double tappedYInImageRect = localPosition.dy - imageRect.top;
    final int x =
        (tappedXInImageRect * (decodedImage!.width / imageRect.width)).round();
    final int y = (tappedYInImageRect * (decodedImage!.height / imageRect.height))
        .round();

    if (x >= 0 &&
        x < decodedImage!.width &&
        y >= 0 &&
        y < decodedImage!.height) {
      final color = _imgColorToFlutterFromRegion(decodedImage!, x, y);

      setState(() {
        final nextRef = _nextReferenceToSelect;
        if (nextRef != null) {
          nextRef.color = color;
          nextRef.location = localPosition;
        } else {
          testStripPoint =
              ReferencePoint(ph: 0, color: color, location: localPosition);
        }
        _updatePhEstimate();
      });
    }
  }
  
  void _updatePhEstimate() {
    final validRefs = referencePoints.where((r) => r.color != null).toList();

    if (testStripPoint?.color != null && validRefs.length >= 2) {
      final interpolated = _interpolatePH(testStripPoint!.color!, validRefs);
      if (interpolated >= 0) {
        estimatedPH = interpolated;
      }
    } else {
      estimatedPH = null;
    }
  }
  
  String _getInstructionText() {
    if (selectedBrand == null) {
      return 'First, select your test strip brand.';
    }
    if (selectedImage == null) {
      return 'Next, upload an image of your test strip and its color chart.';
    }
    final nextRef = _nextReferenceToSelect;
    if (nextRef != null) {
      return 'Tap the reference color for pH: ${nextRef.ph.toStringAsFixed(2)}';
    }
    if (testStripPoint == null) {
      return 'All references set! Now, tap your test strip to get the pH.';
    }
    return 'Done! Tap the test strip again to re-sample.';
  }

  double _colorDistance(Color a, Color b) {
    final rDiff = a.red - b.red; // ignore: deprecated_member_use
    final gDiff = a.green - b.green; // ignore: deprecated_member_use
    final bDiff = a.blue - b.blue; // ignore: deprecated_member_use
    return sqrt((rDiff * rDiff + gDiff * gDiff + bDiff * bDiff));
  }

  double _interpolatePH(Color target, List<ReferencePoint> refs) {
    final validRefs = refs.where((r) => r.color != null).toList();
    if (validRefs.length < 2) return -1;

    validRefs.sort((a, b) =>
        _colorDistance(target, a.color!).compareTo(_colorDistance(target, b.color!)));

    final r1 = validRefs[0];
    final r2 = validRefs[1];

    final d1 = _colorDistance(target, r1.color!);
    final d2 = _colorDistance(target, r2.color!);

    if (d1 + d2 < 1e-4) return r1.ph;

    final weight1 = 1 / (d1 + 1e-9);
    final weight2 = 1 / (d2 + 1e-9);

    return (r1.ph * weight1 + r2.ph * weight2) / (weight1 + weight2);
  }

  Widget _buildInstructions() {
    return Container(
      padding: const EdgeInsets.all(12.0),
      margin: const EdgeInsets.only(bottom: 16.0),
      decoration: BoxDecoration(
        // MODIFIED: Replaced .withOpacity() with .withAlpha() for consistency.
        color: Theme.of(context).colorScheme.primary.withAlpha(13), // ~5% opacity
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(
          // MODIFIED: Replaced .withOpacity() with .withAlpha() for consistency.
          color: Theme.of(context).colorScheme.primary.withAlpha(51), // ~20% opacity
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "How to Use 🧪",
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            )
          ),
          const SizedBox(height: 8),
          const Text("1. Select your strip brand and upload an image."),
          const SizedBox(height: 4),
          const Text("2. Tap the reference colors on your image in order."),
          const SizedBox(height: 4),
          const Text("3. Tap your test strip's color to get the pH estimate."),
          const SizedBox(height: 4),
          const Text("4. To start over, tap a color swatch or the 'Reset' button."),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildInstructions(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<String>(
                  value: selectedBrand,
                  items: knownBrands
                      .map((brand) =>
                          DropdownMenuItem(value: brand, child: Text(brand)))
                      .toList(),
                  onChanged: (val) {
                    setState(() {
                      selectedBrand = val;
                      final preset = stripPresets.firstWhere((e) => e.name == val,
                          orElse: () => const StripPreset('Custom', []));
                      referencePoints = preset.phValues
                          .map((ph) => ReferencePoint(ph: ph))
                          .toList();
                      _resetAll();
                      if (val == 'Custom / Not Listed') {
                        _promptCustomStripSetup();
                      }
                    });
                  },
                  decoration: const InputDecoration(
                    labelText: "Select Strip Brand",
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                children: [
                  ElevatedButton(
                    onPressed: _getImage,
                    child: const Text("Upload Image"),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: _resetAll,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade100,
                      foregroundColor: Colors.red.shade800,
                    ),
                    child: const Text("Reset"),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (referencePoints.isNotEmpty)
            SizedBox(
              height: 60,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: referencePoints.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, index) {
                  final point = referencePoints[index];
                  final bool isNext = point == _nextReferenceToSelect;
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        point.color = null;
                        point.location = null;
                        _updatePhEstimate();
                      });
                    },
                    child: Column(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: point.color ?? Colors.grey.shade300,
                            border: Border.all(
                                color: isNext
                                    ? Theme.of(context).primaryColor
                                    : Colors.black26,
                                width: isNext ? 2.5 : 1.0),
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          point.ph.toStringAsFixed(2),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              _getInstructionText(),
              style: TextStyle(
                  fontStyle: FontStyle.italic,
                  color: Theme.of(context).colorScheme.secondary),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 8),
          if (selectedImageBytes != null)
            AspectRatio(
              aspectRatio: decodedImage!.width / decodedImage!.height,
              child: RepaintBoundary(
                key: _imageContainerKey,
                child: GestureDetector(
                  onTapDown: (details) =>
                      _handleTapOnImage(details.localPosition, context),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.memory(
                        selectedImageBytes!,
                        fit: BoxFit.contain,
                      ),
                      ...referencePoints
                          .where((r) => r.color != null && r.location != null)
                          .map((r) => TapSquareOverlay(
                                location: r.location!,
                                color: r.color!,
                                borderColor: Colors.white,
                              )),
                      if (testStripPoint?.location != null)
                        GestureDetector(
                          onTap: () => setState(() {
                            testStripPoint = null;
                            _updatePhEstimate();
                          }),
                          child: TapSquareOverlay(
                            location: testStripPoint!.location!,
                            color: testStripPoint!.color!,
                            borderColor: Colors.greenAccent,
                          ),
                        ),
                      if (estimatedPH != null)
                        Positioned(
                          bottom: 10,
                          left: 10,
                          right: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                vertical: 8, horizontal: 12),
                            decoration: BoxDecoration(
                              color: const Color.fromARGB(221, 0, 0, 0),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              "Estimated pH: ${estimatedPH!.toStringAsFixed(2)}",
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            )
          else
            Container(
              height: 200,
              alignment: Alignment.center,
              child: const Text("Please upload an image to begin.")
            ),
        ],
      ),
    );
  }
}