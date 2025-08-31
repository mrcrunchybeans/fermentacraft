
import 'dart:async';
import 'package:fermentacraft/utils/inventory_item_extensions.dart';
import 'package:fermentacraft/widgets/show_paywall.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fermentacraft/models/recipe_model.dart';
import 'package:fermentacraft/widgets/add_measurement_dialog.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../models/batch_model.dart';
import '../models/inventory_item.dart';
import '../models/purchase_transaction.dart';
import '../utils/boxes.dart';
import '../utils/unit_conversion.dart';
import '../widgets/add_ingredient_dialog.dart';
import '../widgets/add_additive_dialog.dart';
import '../utils/batch_utils.dart';
import '../widgets/add_yeast_dialog.dart';
import '../widgets/fermentation_chart.dart';
import '../widgets/manage_stages_dialog.dart';
import '../models/fermentation_stage.dart';
import '../models/measurement.dart';
import '../widgets/add_inventory_dialog.dart';
import '../models/unit_type.dart';
import 'package:intl/intl.dart';
import '../models/shopping_list_item.dart';
import 'package:fermentacraft/services/feature_gate.dart';
import 'package:fermentacraft/services/counts_service.dart';
import 'package:fermentacraft/services/gravity_service.dart';
import 'package:fermentacraft/services/batch_extras_repo.dart';
import 'package:fermentacraft/models/settings_model.dart';
import 'package:provider/provider.dart';
import '../utils/temp_display.dart';
import 'package:fermentacraft/utils/snacks.dart';
import 'package:fermentacraft/services/review_prompter.dart';
import 'package:fermentacraft/utils/recipe_to_batch.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fermentacraft/services/firestore_paths.dart';
import 'package:fermentacraft/utils/export_csv.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fermentacraft/widgets/attach_device_sheet.dart';
import 'package:fermentacraft/utils/gravity_utils.dart';






// Import the unique ID generator
import '../utils/id.dart';

// ---- Top-level: visible to both pages ----
Measurement fromRemoteDoc(Map<String, dynamic> m, {String? docId}) {
  final ts = (m['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();

  // ----- Gravity -----
  double? sg = (m['sg'] as num?)?.toDouble()
            ?? (m['corrSG'] as num?)?.toDouble()
            ?? (m['corr_gravity'] as num?)?.toDouble()
            ?? (m['corr-gravity'] as num?)?.toDouble();

  double? brix = (m['brix'] as num?)?.toDouble();

  if (sg == null && m['gravity'] != null) {
    final gVal = (m['gravity'] as num).toDouble();
    final gUnit = (m['gravity_unit'] ?? m['gravity-unit'] ?? m['gravityUnit'])
        ?.toString().toLowerCase(); // ← no generic "unit" here
    if (gUnit == 'brix' || gUnit == '°brix' || gUnit == 'bx') {
      brix = gVal;
      sg = brixToSg(gVal);
    } else {
      sg = gVal;
    }
  }
  sg ??= (brix != null) ? brixToSg(brix) : null;

  // ----- Temperature -----
  double? tempC;
  if (m['tempC'] is num) {
    tempC = (m['tempC'] as num).toDouble();
  } else if (m['tempF'] is num) {
    tempC = ((m['tempF'] as num).toDouble() - 32) * 5 / 9;
  } else {
    final rawTemp = (m['temperature'] ?? m['temp']) as num?;
    final tUnit = (m['temperature_unit'] ?? m['temp_units'] ?? m['tempUnit'])
        ?.toString().toUpperCase(); // ← no generic "unit" here either
    if (rawTemp != null) {
      final t = rawTemp.toDouble();
      tempC = (tUnit != null && tUnit.contains('F')) ? ((t - 32) * 5 / 9) : t;
    }
  }

  final deviceLabel = (m['deviceName'] ?? m['device_name'] ?? m['source'] ?? m['deviceId'])?.toString();

  return Measurement(
    id: docId ?? 'device_${ts.millisecondsSinceEpoch}',
    timestamp: ts,
    gravity: sg,
    brix: brix,
    temperature: tempC,
    fromDevice: true,
    notes: (deviceLabel == null || deviceLabel.isEmpty) ? 'device' : deviceLabel,
  );
}


class BatchDetailPage extends StatefulWidget {
  const BatchDetailPage({
    super.key,
    required this.batchKey,
    this.firebaseUid,
  });

  final String batchKey;
  final String? firebaseUid;

  @override
  State<BatchDetailPage> createState() => _BatchDetailPageState();
}

class _BatchDetailPageState extends State<BatchDetailPage>
    with SingleTickerProviderStateMixin {
  // How "recent" to consider a device online
static const _onlineGrace = Duration(minutes: 10);

  // ---- Model / key ----
  BatchModel? _batch;

// Cache a one-shot device snapshot for non-premium view
Future<QuerySnapshot<Map<String, dynamic>>>? _deviceOnceFuture;

  late final TextEditingController _finalNotesController;
  late final TextEditingController _finalYieldController;
    Timer? _finalYieldDebounce;
  final FocusNode _finalYieldFocus = FocusNode(); 
  String _finalYieldUnit = 'gal';
  late final Object _hiveKey;
  bool _isBrewModeEnabled = false;
  late final TextEditingController _prepNotesController;
 // int or String, depending on your box keys

  // ---- UI state ----
  late final TabController _tabController;

  late final TextEditingController _tastingAppearanceController;
  late final TextEditingController _tastingAromaController;
  late final TextEditingController _tastingFlavorController;
  int _tastingRating = 0;

  @override
  void dispose() {
    if (_isBrewModeEnabled) {
      WakelockPlus.disable();
    }
    _tabController.dispose();
    _prepNotesController.dispose();
    _tastingAromaController.dispose();
    _tastingAppearanceController.dispose();
    _tastingFlavorController.dispose();
    _finalYieldDebounce?.cancel();
    _finalYieldFocus.dispose();
    _finalYieldController.dispose();
    _finalNotesController.dispose();
    super.dispose();
  }

  // ---------------- lifecycle ----------------

  @override
void initState() {
  super.initState();

  // widget.batchKey is a String; convert to int if your box uses int keys
  _hiveKey = int.tryParse(widget.batchKey) ?? widget.batchKey;

  final box = Hive.box<BatchModel>(Boxes.batches);
  _batch = box.get(_hiveKey);

  final initialTabIndex = _initialTabIndexFor(_batch?.status);
  _tabController = TabController(length: 4, vsync: this, initialIndex: initialTabIndex);

_initControllersFrom(_batch);



_finalYieldFocus.addListener(() {
  if (!_finalYieldFocus.hasFocus) _persistFinalYield(); // <-- add
});

}

/// Render [builder] only when a UID is available; otherwise return SizedBox.shrink().
Widget ifSignedIn(Widget Function(String uid) builder) {
  final uid = _uid;
  if (uid == null) return const SizedBox.shrink();
  return builder(uid);
}

/// Recalculate batch.plannedOg from ingredients + target volume.
Future<void> recalcPlannedOg(BatchModel batch) async {
  final v = (batch.batchVolume ?? 0);
  if (v <= 0) return;

  final items = batch.safeIngredients;
  final liquidOg = _blendedOgFromLiquids(items);
  final liquidGU = (liquidOg == null ? 0.0 : (liquidOg - 1.0) * 1000.0) * v;
  final massGU   = _sumMassFermentablesGU(items);

  final totalGU  = liquidGU + massGU;
  final newOg    = 1.0 + (totalGU / v) / 1000.0;

  batch.plannedOg = double.parse(newOg.toStringAsFixed(3));
  await batch.save();
  if (mounted) setState(() {}); // reflect in UI immediately
}

Future<String?> _currentDeviceIdForBatch(String uid, String batchId) async {
  final snap = await FirestorePaths
      .devicesColl(uid)
      .where('linkedBatchId', isEqualTo: batchId)
      .limit(1)
      .get();

  if (snap.docs.isEmpty) return null;
  return snap.docs.first.id;
}

Future<List<DevicePickItem>> _fetchDevicePickItems({
  required String uid,
  required String batchId,
}) async {
  final qs = await FirestorePaths.devicesColl(uid).get();
  final now = DateTime.now();
  final batchBox = Hive.box<BatchModel>(Boxes.batches);

  String? nameForBatchId(String? id) {
    if (id == null || id.isEmpty) return null;
    final local = batchBox.get(id);
    if (local != null) return local.name;
    return 'Batch $id';
  }

  return qs.docs.map((doc) {
    final data = doc.data();
    final name = (data['name'] as String?) ?? 'Device';
    final linkedBatchId = data['linkedBatchId'] as String?;
    final lastSeenTs = data['lastSeen'];
    DateTime? lastSeen;
    if (lastSeenTs is Timestamp) lastSeen = lastSeenTs.toDate();

    final online = lastSeen != null && now.difference(lastSeen) <= _onlineGrace;
    final assignedElsewhere =
        linkedBatchId != null && linkedBatchId.isNotEmpty && linkedBatchId != batchId;

    return DevicePickItem(
      id: doc.id,
      name: name,
      online: online,
      assignedElsewhere: assignedElsewhere,
      assignedBatchName: assignedElsewhere
          ? (nameForBatchId(linkedBatchId) ?? 'Another batch')
          : (linkedBatchId == batchId ? 'This batch' : null),
    );
  }).toList();
}

Future<void> _attachDeviceToBatch({
  required String uid,
  required String batchId,
  required String? deviceId, // null = detach
}) async {
  // Detach any currently linked device first
  final currentId = await _currentDeviceIdForBatch(uid, batchId);
  if (currentId != null) {
    await FirestorePaths.deviceDoc(uid, currentId).update({'linkedBatchId': FieldValue.delete()});
  }

  // Attach the chosen one (unless we're just detaching)
  if (deviceId != null) {
    await FirestorePaths.deviceDoc(uid, deviceId).update({'linkedBatchId': batchId});
  }
}

  /// The page reads UID itself when needed. If the constructor-provided UID exists,
/// it wins; otherwise we fall back to FirebaseAuth.
String? get _uid => widget.firebaseUid ?? FirebaseAuth.instance.currentUser?.uid;

IconData _batteryIconForPercent(double? pct) {
  final p = (pct ?? -1).toDouble();
  if (p < 0) return Icons.battery_unknown;
  if (p >= 0.95) return Icons.battery_full;
  if (p >= 0.75) return Icons.battery_5_bar;
  if (p >= 0.55) return Icons.battery_4_bar;
  if (p >= 0.35) return Icons.battery_3_bar;
  if (p >= 0.15) return Icons.battery_2_bar;
  return Icons.battery_alert;
}

String _timeAgoShort(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 60) return '${d.inSeconds}s ago';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  return '${d.inDays}d ago';
}

  // ---------------- helpers ----------------

  Box<BatchModel> get _batchBox => Hive.box<BatchModel>(Boxes.batches);

Future<void> _mutateBatch(void Function(BatchModel b) update) async {
  final b = _batchBox.get(_hiveKey);
  if (b == null) return;            // batch might have been deleted elsewhere
  update(b);                        // mutate the *attached* instance
  await b.save();                   // safe: b.isInBox == true
  if (mounted) setState(() {});     // refresh UI
}

  int _initialTabIndexFor(String? status) {
    switch (status) {
      case 'Preparation':
        return 1;
      case 'Fermenting':
        return 2;
      case 'Completed':
        return 3;
      default:
        return 0;
    }
  }

  void _initControllersFrom(BatchModel? b) {
    _prepNotesController = TextEditingController(text: b?.prepNotes ?? '');
    _tastingRating = b?.tastingRating ?? 0;
    _tastingAromaController =
        TextEditingController(text: b?.tastingNotes?['aroma'] ?? '');
    _tastingAppearanceController =
        TextEditingController(text: b?.tastingNotes?['appearance'] ?? '');
    _tastingFlavorController =
        TextEditingController(text: b?.tastingNotes?['flavor'] ?? '');
    _finalYieldController =
        TextEditingController(text: (b?.finalYield)?.toString() ?? '');
    _finalYieldUnit = b?.finalYieldUnit ?? 'gal';
    _finalNotesController = TextEditingController(text: b?.finalNotes ?? '');
  }

void _persistFinalYield() {
  final parsed = double.tryParse(_finalYieldController.text.trim());

  // pull the freshest batch from Hive (ValueListenableBuilder may have newer)
  final box = Hive.box<BatchModel>(Boxes.batches);
  final b = box.get(_hiveKey);
  if (b == null) return;

  if (parsed != b.finalYield) {
    b.finalYield = parsed;
    b.save();
  }
}

  // ---------------- ABV math ----------------

  double? _computeAbv({
    required BatchModel batch,
    required bool useMeasured,
    required double? measuredOg,
  }) {
    final double? og = (useMeasured && measuredOg != null && measuredOg > 1.0)
        ? measuredOg
        : (batch.og ?? batch.plannedOg);

    if (og == null || og <= 1.0) return null;

    final double fg = (batch.fg ??
            (batch.safeMeasurements.isNotEmpty
                ? (batch.safeMeasurements.last.gravity ?? 1.000)
                : 1.000))
        .toDouble();

    return GravityService.abv(og: og, fg: fg);
  }

  Future<double?> _abvForBatch(BatchModel batch) async {
    final extras = await BatchExtrasRepo().getOrCreate(batch.id);
    return _computeAbv(
      batch: batch,
      useMeasured: extras.useMeasuredOg == true,
      measuredOg: extras.measuredOg,
    );
  }

  // ---------------- archive toggle ----------------

Future<void> _onArchiveToggle(BatchModel batch) async {
  final wantArchive = !batch.isArchived;

  if (wantArchive && !FeatureGate.instance.isPremium) {
    final archived = CountsService.instance.archivedBatchCount();
    if (archived >= FeatureGate.instance.archivedBatchLimitFree) {
      if (!mounted) return;
      snacks.show(
        SnackBar(content: Text('Free allows ${FeatureGate.instance.archivedBatchLimitFree} archived batches')),
      );
      showPaywall(context);
      return;
    }
  }

  

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(wantArchive ? 'Archive Batch?' : 'Unarchive Batch?'),
      content: Text('Are you sure you want to ${wantArchive ? 'archive' : 'unarchive'} "${batch.name}"?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        ElevatedButton(onPressed: () => Navigator.pop(context, true), child: Text(wantArchive ? 'Archive' : 'Unarchive')),
      ],
    ),
  );
  if (confirmed != true) return;

  final box = Hive.box<BatchModel>(Boxes.batches);
  batch.isArchived = wantArchive;
  await box.put(_hiveKey, batch);

  if (!mounted) return;
  setState(() => _batch = batch);
  snacks.show(
    SnackBar(content: Text(wantArchive ? 'Archived "${batch.name}"' : 'Unarchived "${batch.name}"')),
  );
}

  Future<void> _editIngredientDialog(BatchModel batch, int index) async {
    final existing = batch.ingredients[index];
    final correctedMap = Map<String, dynamic>.from(existing);

    if (correctedMap['purchaseDate'] is String) {
      correctedMap['purchaseDate'] =
          DateTime.tryParse(correctedMap['purchaseDate']);
    }
    if (correctedMap['expirationDate'] is String) {
      correctedMap['expirationDate'] =
          DateTime.tryParse(correctedMap['expirationDate']);
    }

    await showDialog(
      context: context,
      builder: (_) => AddIngredientDialog(
        unitType: inferUnitType(correctedMap['unit'] ?? 'g'),
        existing: correctedMap,
        onAddToRecipe: (updated) async {
          batch.ingredients[index] = updated;
          await batch.save();
          await recalcPlannedOg(batch); // ← add

        },
      ),
    );
  }

  Future<void> _editAdditiveDialog(BatchModel batch, int index) async {
    final existing = batch.additives[index];
    await showDialog(
      context: context,
      builder: (_) => AddAdditiveDialog(
        mustPH: 3.4,
        volume: batch.batchVolume ?? 5.0,
        existing: Map<String, dynamic>.from(existing),
        onAdd: (updated) {
          batch.additives[index] = updated;
          batch.save();
        },
      ),
    );
  }

  Future<void> _editYeastDialog(BatchModel batch, int index) async {
    final existing = batch.yeast[index];
    await showDialog(
      context: context,
      builder: (_) => AddYeastDialog(
        existing: Map<String, dynamic>.from(existing),
        onAdd: (updated) {
          batch.yeast[index] = updated;
          batch.save();
        },
      ),
    );
  }

  bool _guardActiveBatchLimit(BuildContext context) {
  final fg = context.read<FeatureGate>(); // or Provider.of<FeatureGate>(context, listen: false)
  if (fg.isPremium) return true;

  final activeCount = CountsService.instance.activeBatchCount();
  if (activeCount >= fg.activeBatchLimitFree) {
    snacks.show(
      SnackBar(content: Text('Free allows ${fg.activeBatchLimitFree} active batches')),
    );
showPaywall(context);

    return false;
  }
  return true;
}

  void _toggleBrewMode() {
    setState(() {
      _isBrewModeEnabled = !_isBrewModeEnabled;
      if (_isBrewModeEnabled) {
        WakelockPlus.enable();
        snacks.show(
          const SnackBar(
            content: Text("Brew Mode Enabled: Screen will stay on."),
            duration: Duration(seconds: 2),
          ),
        );
      } else {
        WakelockPlus.disable();
        snacks.show(
          const SnackBar(
            content: Text("Brew Mode Disabled."),
            duration: Duration(seconds: 2),
          ),
        );
      }
    });
  }

void _updateBatchStatus(BatchModel batch, String newStatus) {
  // Detect FIRST EVER "Completed" (exclude the current batch)
  bool shouldFireFirstCompleted = false;
  if (newStatus == 'Completed') {
    try {
      final box = Hive.box<BatchModel>(Boxes.batches);
      final anyCompletedBefore = box.values.any(
        (b) => b.id != batch.id && (b.status == 'Completed'),
      );
      // If none were completed before, this is the user's first completion.
      if (!anyCompletedBefore) {
        shouldFireFirstCompleted = true;
      }
    } catch (_) {
      // If box not open yet or any error, fail safe: don't trigger.
    }
  }

  _mutateBatch((b) {
    b.status = newStatus;
  });

  int tabIndex = 0;
  switch (newStatus) {
    case 'Preparation':
      tabIndex = 1;
      break;
    case 'Fermenting':
      tabIndex = 2;
      break;
    case 'Completed':
      tabIndex = 3;
      break;
  }
  _tabController.animateTo(tabIndex);

  // After UI settles, fire the review event if applicable.
  if (shouldFireFirstCompleted && mounted) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ReviewPrompter.instance.fireFirstBatchCompleted(context);
    });
  }
}

  Future<void> _showChangeStatusDialog(BatchModel batch) async {
    String currentStatus = batch.status;
    final newStatus = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Change Batch Status'),
          content: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: ['Planning', 'Preparation', 'Fermenting', 'Completed']
                    .map((status) {
                  return RadioListTile<String>(
                    title: Text(status),
                    value: status,
                    groupValue: currentStatus,
                    onChanged: (String? value) {
                      if (value != null) {
                        setState(() {
                          currentStatus = value;
                        });
                      }
                    },
                  );
                }).toList(),
              );
            },
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              child: const Text('Save'),
              onPressed: () => Navigator.of(context).pop(currentStatus),
            ),
          ],
        );
      },
    );

    if (newStatus != null && newStatus != batch.status) {
      _updateBatchStatus(batch, newStatus);
    }
  }

  Widget _buildStatusProgressionButton({
    required BatchModel batch,
    required String currentStatus,
    required String nextStatus,
    required String buttonText,
    IconData? icon,
  }) {
    if (batch.status != currentStatus) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24.0),
      child: Center(
        child: ElevatedButton.icon(
          icon: Icon(icon ?? Icons.arrow_forward_ios),
          label: Text(buttonText),
          onPressed: () => _updateBatchStatus(batch, nextStatus),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            textStyle: Theme.of(context).textTheme.titleMedium,
            backgroundColor: Theme.of(context).primaryColor,
            foregroundColor: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 4.0),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleLarge,
      ),
    );
  }

  Widget _buildPlanningTab(BatchModel batch) {
  final extrasFuture = BatchExtrasRepo().getOrCreate(batch.id);
  
  return SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _recipeSummaryCard(batch),
        const SizedBox(height: 16),

        FutureBuilder(
          future: extrasFuture,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Row(
                    children: [CircularProgressIndicator(), SizedBox(width: 12), Text('Loading…')],
                  ),
                ),
              );
            }

            final extras = snapshot.data!;
            final abvFromThisCard = _computeAbv(
              batch: batch,
              useMeasured: extras.useMeasuredOg == true,
              measuredOg: extras.measuredOg,
            );

            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Measured OG', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    TextFormField(
                      key: ValueKey(extras.measuredOg),
                      initialValue: (extras.measuredOg != null && extras.measuredOg! > 1.0)
                          ? extras.measuredOg!.toStringAsFixed(3)
                          : '',
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Measured OG (e.g., 1.072)',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (val) async {
                        final parsed = double.tryParse(val);
                        final newValue = (parsed != null && parsed > 1.0) ? parsed : null;
                        if (newValue != extras.measuredOg) {
                          await BatchExtrasRepo().setMeasuredOg(batch.id, newValue);
                          if (mounted) setState(() {});
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Use measured OG for ABV'),
                      value: (extras.useMeasuredOg == true),
                      onChanged: (v) async {
                        await BatchExtrasRepo().setUseMeasuredOg(batch.id, v);
                        if (mounted) setState(() {});
                      },
                    ),
                    if (abvFromThisCard != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('ABV (with current setting): ${abvFromThisCard.toStringAsFixed(2)}%'),
                      ),
                  ],
                ),
              ),
            );
          },
        ),

        const SizedBox(height: 16),


          ElevatedButton.icon(
            icon: const Icon(Icons.sync),
            label: const Text('Sync From Recipe'),
            onPressed: () => _showSyncFromRecipeDialog(batch),
          ),
          _sectionTitle('Ingredients'),
          _ingredientsList(batch),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Add Ingredient'),
            onPressed: () async {
              await showDialog<void>(
                context: context,
                builder: (_) => AddIngredientDialog(
                  unitType: UnitType.mass,
                  onAddToRecipe: (ingredient) async {
                    batch.ingredients.add(ingredient);
                    await batch.save();
                    await recalcPlannedOg(batch); // ← add this

                    await _addIngredientToLinkedRecipeIfAny(batch, ingredient);
                  },
                ),
              );
            },

          ),
          const SizedBox(height: 16),
          _sectionTitle('Yeast'),
          _yeastList(batch),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Add Yeast'),
            onPressed: () async {
              await showDialog(
                context: context,
                builder: (_) => AddYeastDialog(
                  onAdd: (newYeast) {
                    batch.yeast.add(newYeast);
                    batch.save();
                  },
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          _sectionTitle('Additives'),
          _additivesList(batch),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Add Additive'),
            onPressed: () async {
              await showDialog<void>(
                context: context,
                builder: (_) => AddAdditiveDialog(
                  mustPH: estimateMustPH(batch),
                  volume: batch.batchVolume ?? 5.0,
                  onAdd: (additive) {
                    batch.additives.add(additive);
                    batch.save();
                  },
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          _sectionTitle('Fermentation Profile'),
          _fermentationStagesList(batch),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            icon: const Icon(Icons.settings),
            label: const Text('Manage Stages'),
            onPressed: () => _manageStages(batch),
          ),
          const SizedBox(height: 16),          
          _buildStatusProgressionButton(
            batch: batch,
            currentStatus: 'Planning',
            nextStatus: 'Preparation',
            buttonText: 'Start Preparation',
          ),
        ],
      ),
    );
  }

Future<bool> _confirmDelete({
  required String title,
  required String message,
}) async {
  return await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      ) ??
      false;
}

void _showUndoSnackBar({
  required String label,
  required VoidCallback onUndo,
}) {
  snacks.show(
    SnackBar(
      content: Text(label),
      action: SnackBarAction(label: 'Undo', onPressed: onUndo),
      duration: const Duration(seconds: 4),
    ),
  );
}

// Delete + Undo for Ingredients
Future<void> _deleteIngredient(BatchModel batch, int index) async {
  final map = Map<String, dynamic>.from(batch.ingredients[index]);
  final name = (map['name'] as String?) ?? 'ingredient';
  final confirmed = await _confirmDelete(
    title: 'Remove Ingredient',
    message: 'Remove "$name" from this batch?',
  );
  if (!confirmed) return;

  final removed = batch.ingredients.removeAt(index);
  await batch.save();
  await recalcPlannedOg(batch); // ← add
  if (!mounted) return;

  _showUndoSnackBar(
    label: 'Removed $name',
    onUndo: () async {
      batch.ingredients.insert(index, removed);
      await batch.save();
      await recalcPlannedOg(batch); // ← add
      if (mounted) setState(() {});
    },
  );
  setState(() {});
}

// Delete + Undo for Yeast
Future<void> _deleteYeast(BatchModel batch, int index) async {
  final map = Map<String, dynamic>.from(batch.yeast[index]);
  final name = (map['name'] as String?) ?? 'yeast';
  final confirmed = await _confirmDelete(
    title: 'Remove Yeast',
    message: 'Remove "$name" from this batch?',
  );
  if (!confirmed) return;

  final removed = batch.yeast.removeAt(index);
  await batch.save();
  if (!mounted) return;

  _showUndoSnackBar(
    label: 'Removed $name',
    onUndo: () async {
      batch.yeast.insert(index, removed);
      await batch.save();
      if (mounted) setState(() {});
    },
  );
  setState(() {});
}

// Delete + Undo for Additives
Future<void> _deleteAdditive(BatchModel batch, int index) async {
  final map = Map<String, dynamic>.from(batch.additives[index]);
  final name = (map['name'] as String?) ?? 'additive';
  final confirmed = await _confirmDelete(
    title: 'Remove Additive',
    message: 'Remove "$name" from this batch?',
  );
  if (!confirmed) return;

  final removed = batch.additives.removeAt(index);
  await batch.save();
  if (!mounted) return;

  _showUndoSnackBar(
    label: 'Removed $name',
    onUndo: () async {
      batch.additives.insert(index, removed);
      await batch.save();
      if (mounted) setState(() {});
    },
  );
  setState(() {});
}

  // --- PLANNING TAB LIST WIDGETS ---

  Widget _ingredientsList(BatchModel batch) {
    if (batch.ingredients.isEmpty) return const Text('No ingredients added.');
    final inventoryBox = Hive.box<InventoryItem>(Boxes.inventory);
    return Column(
      children: batch.ingredients.asMap().entries.map((entry) {
        final index = entry.key;
        final ingredientMap = entry.value;
        final ingredient = Map<String, dynamic>.from(ingredientMap);
        final name = ingredient['name'] as String? ?? 'Unnamed';
        final amount = (ingredient['amount'] as num?)?.toDouble() ?? 0;
        final unit = ingredient['unit'] as String? ?? '';
        final note = ingredient['note'] as String? ?? '';
        final inventoryItem = inventoryBox.values.firstWhere(
          (item) => item.name.toLowerCase() == name.toLowerCase(),
          orElse: () => InventoryItem(
            id: 'placeholder',
            name: '',
            unit: '',
            unitType: UnitType.volume,
            category: '',
            purchaseHistory: const [],
          ),
        );
        final inStock = inventoryItem.amountInStock;
        final sufficient = inStock >= amount;

return InkWell(
  onLongPress: () => _editIngredientDialog(batch, index),
  child: ListTile(
    leading: const Icon(Icons.liquor_outlined),
    title: Text('$amount $unit $name'),
    subtitle: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (note.isNotEmpty) Text(note),
        if (inventoryItem.name.isNotEmpty)
          Text(
            'In stock: ${inStock.toStringAsFixed(2)} $unit',
            style: TextStyle(
              color: sufficient ? Colors.green : Colors.red,
              fontWeight: FontWeight.w500,
            ),
          )
        else
          const Text('Not in inventory', style: TextStyle(color: Colors.grey)),
      ],
    ),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Edit',
          icon: const Icon(Icons.edit),
          onPressed: () => _editIngredientDialog(batch, index),
        ),
        IconButton(
          tooltip: 'Delete',
          icon: const Icon(Icons.delete, color: Colors.red),
          onPressed: () => _deleteIngredient(batch, index),
        ),
      ],
    ),
  ),
);

      }).toList(),
    );
  }

  Widget _additivesList(BatchModel batch) {
    if (batch.additives.isEmpty) return const Text('No additives added.');
    final inventoryBox = Hive.box<InventoryItem>(Boxes.inventory);
    return Column(
      children: batch.additives.asMap().entries.map((entry) {
        final index = entry.key;
        final additiveMap = entry.value;
        final additive = Map<String, dynamic>.from(additiveMap);
        final name = additive['name'] as String? ?? 'Unnamed';
        final amount = (additive['amount'] as num?)?.toDouble() ?? 0;
        final unit = additive['unit'] as String? ?? '';
        final note = additive['note'] as String? ?? '';
        final inventoryItem = inventoryBox.values.firstWhere(
          (item) => item.name.toLowerCase() == name.toLowerCase(),
          orElse: () => InventoryItem(
            id: 'placeholder',
            name: '',
            unit: '',
            unitType: UnitType.volume,
            category: '',
            purchaseHistory: const [],
          ),
        );
        final inStock = inventoryItem.amountInStock;
        final sufficient = inStock >= amount;

        return InkWell(
  onLongPress: () => _editAdditiveDialog(batch, index),
  child: ListTile(
    leading: const Icon(Icons.science),
    title: Text('$amount $unit $name'),
    subtitle: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (note.isNotEmpty) Text(note),
        if (inventoryItem.name.isNotEmpty)
          Text(
            'In stock: ${inStock.toStringAsFixed(2)} $unit',
            style: TextStyle(
              color: sufficient ? Colors.green : Colors.red,
              fontWeight: FontWeight.w500,
            ),
          )
        else
          const Text('Not in inventory', style: TextStyle(color: Colors.grey)),
      ],
    ),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Edit',
          icon: const Icon(Icons.edit),
          onPressed: () => _editAdditiveDialog(batch, index),
        ),
        IconButton(
          tooltip: 'Delete',
          icon: const Icon(Icons.delete, color: Colors.red),
          onPressed: () => _deleteAdditive(batch, index),
        ),
      ],
    ),
  ),
);

      }).toList(),
    );
  }

  Widget _yeastList(BatchModel batch) {
    if (batch.yeast.isEmpty) return const Text('No yeast added.');
    final inventoryBox = Hive.box<InventoryItem>(Boxes.inventory);
    return Column(
      children: batch.yeast.asMap().entries.map((entry) {
        final index = entry.key;
        final yeastMap = entry.value;
        final yeast = Map<String, dynamic>.from(yeastMap);
        final name = yeast['name'] as String? ?? 'Unnamed Yeast';
        final amount = (yeast['amount'] as num?)?.toDouble() ?? 0;
        final unit = yeast['unit'] as String? ?? '';
        final inventoryItem = inventoryBox.values.firstWhere(
          (item) => item.name.toLowerCase() == name.toLowerCase(),
          orElse: () => InventoryItem(
            id: 'placeholder',
            name: '',
            unit: '',
            unitType: UnitType.mass,
            category: '',
            purchaseHistory: const [],
          ),
        );
        final inStock = inventoryItem.amountInStock;
        final sufficient = inStock >= amount;

        return InkWell(
  onLongPress: () => _editYeastDialog(batch, index),
  child: ListTile(
    leading: const Icon(Icons.bubble_chart),
    title: Text('$amount $unit $name'),
    subtitle: inventoryItem.name.isNotEmpty
        ? Text(
            'In stock: ${inStock.toStringAsFixed(2)} $unit',
            style: TextStyle(
              color: sufficient ? Colors.green : Colors.red,
              fontWeight: FontWeight.w500,
            ),
          )
        : const Text('Not in inventory', style: TextStyle(color: Colors.grey)),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Edit',
          icon: const Icon(Icons.edit),
          onPressed: () => _editYeastDialog(batch, index),
        ),
        IconButton(
          tooltip: 'Delete',
          icon: const Icon(Icons.delete, color: Colors.red),
          onPressed: () => _deleteYeast(batch, index),
        ),
      ],
    ),
  ),
);

      }).toList(),
    );
  }

  Widget _recipeSummaryCard(BatchModel batch) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Recipe Summary',
                    style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
            Row(
              children: [
                Text('Status: ', style: Theme.of(context).textTheme.titleMedium),
                Text(batch.status,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                OutlinedButton(
                  onPressed: () => _showChangeStatusDialog(batch),
                  child: const Text('Change Stage'),
                ),
              ],
            ),
            const Divider(),

            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Target Volume: ${batch.batchVolume?.toStringAsFixed(1) ?? '—'} gal'),
                    const SizedBox(height: 4),
                    Text('Target OG: ${batch.plannedOg?.toStringAsFixed(3) ?? '—'}'),
                    const SizedBox(height: 4),
                    FutureBuilder(
                      future: BatchExtrasRepo().getOrCreate(batch.id),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) return const Text('Estimated ABV: —');
                        final extras = snapshot.data!;
                        final abv = _computeAbv(batch: batch, useMeasured: extras.useMeasuredOg == true, measuredOg: extras.measuredOg,);
                        final s = (abv == null) ? '—' : abv.toStringAsFixed(1);
                        return Text('Estimated ABV: $s%');
                      },
                    ),
                  ],
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton(
                    onPressed: () => _editBatchSummary(batch),
                    child: const Text('Update Targets'),
                  ),
                ),
              ],
            )



          ],
        ),
      ),
    );
  }

  Widget _fermentationStagesList(BatchModel batch) {
    if (batch.safeFermentationStages.isEmpty) {
      return const Text('No fermentation stages planned.');
    }
    return Column(
      children: batch.safeFermentationStages.map((stage) {
        final name = stage.name;
final settings = context.read<SettingsModel>();
final tempLabel = stage.targetTempC?.toDisplay(targetUnit: settings.unit) ?? '—';

        final duration = stage.durationDays.toString();
        return ListTile(
          leading: const Icon(Icons.thermostat),
          title: Text(name),
subtitle: Text('Temp: $tempLabel, Duration: $duration days'),
        );
      }).toList(),
    );
  }

  Future<bool> _confirmInventoryDeduction({
    required BuildContext context,
    required String name,
    required double inStock,
    required double requested,
    required String unit,
  }) async {
    if (inStock >= requested) return true;

    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Not Enough Inventory'),
            content: Text(
              'Only ${inStock.toStringAsFixed(2)} $unit of "$name" in stock, but trying to deduct $requested.\n\nProceed anyway?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Proceed'),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _editBatchSummary(BatchModel batch) {
    final volumeController =
        TextEditingController(text: batch.batchVolume?.toString() ?? '');
    final ogController =
        TextEditingController(text: batch.plannedOg?.toString() ?? '');
    final abvController =
        TextEditingController(text: batch.plannedAbv?.toString() ?? '');

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit Recipe Summary'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: volumeController,
              keyboardType: TextInputType.number,
              decoration:
                  const InputDecoration(labelText: 'Target Volume (gal)'),
            ),
            TextField(
              controller: ogController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Target OG'),
            ),
            TextField(
              controller: abvController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Target ABV (%)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
ElevatedButton(
  onPressed: () async {
    // capture what you need from context BEFORE any awaits
    final nav = Navigator.of(context);

    // snapshot current values for change detection
    final prevVol = batch.batchVolume;
    final ogWasBlank = ogController.text.trim().isEmpty;

    // parse once
    final newVol = double.tryParse(volumeController.text);
    final newOg  = double.tryParse(ogController.text);
    final newAbv = double.tryParse(abvController.text);

    // apply + persist
    batch.batchVolume = newVol;
    batch.plannedOg   = newOg;
    batch.plannedAbv  = newAbv;
    await batch.save();

    // decide if we should recompute planned OG
    final volChanged = (prevVol ?? -1) != (newVol ?? -1);
    if ((newVol ?? 0) > 0 && (ogWasBlank || volChanged)) {
      await recalcPlannedOg(batch);
    }

    if (!mounted) return;
    setState(() {}); // refresh UI
    nav.pop();
  },
  child: const Text('Save'),
),

        ],
      ),
    );
  }

  void _handleDeleteMeasurement(BatchModel batch, Measurement measurement) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Deletion'),
          content: Text(
            'Are you sure you want to delete the measurement from '
            '${DateFormat.yMMMd().add_jm().format(measurement.timestamp.toLocal())}?'
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: const Text('Delete'),
              onPressed: () async { // CHANGE
                Navigator.of(context).pop();
                await _mutateBatch((b) =>
                    b.measurements.removeWhere((x) => x.id == measurement.id));
              },
            ),
          ],
        );
      },
    );
  }

Future<void> _openMeasurementEditor(BatchModel batch, Measurement target) async {
  // figure out "previous" + "first" for FSU/day chips
  final sorted = [...batch.measurements]
    ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  final firstDate = sorted.isNotEmpty ? sorted.first.timestamp : null;
  final idx = sorted.indexWhere((m) => m.id == target.id);
  final prev = (idx > 0) ? sorted[idx - 1] : null;

  final updated = await showDialog<Measurement>(
    context: context,
    builder: (_) => AddMeasurementDialog(
      existingMeasurement: target,
      previousMeasurement: prev,
      firstMeasurementDate: firstDate,
    ),
  );
  if (updated == null) return;

  // replace in-place, keep same id
  await _mutateBatch((bch) {
    final i = bch.measurements.indexWhere((x) => x.id == target.id);
    if (i != -1) {
      bch.measurements[i] = Measurement(
        id: target.id,
        timestamp: updated.timestamp,
        gravityUnit: updated.gravityUnit,
        gravity: updated.gravity,
        brix: updated.brix,
        temperature: updated.temperature,
        notes: updated.notes,
        fsuspeed: updated.fsuspeed,
        ta: updated.ta,
        sgCorrected: updated.sgCorrected,
        interventions: updated.interventions,
        fromDevice: false, // edits are local
      );
    }
  });
}

  void _showSyncFromRecipeDialog(BatchModel batch) async {
    bool syncYeast = true;
    bool syncIngredients = true;
    bool syncAdditives = true;
    bool syncStages = true;
    bool syncTargets = true;
    final recipeBox = Hive.box<RecipeModel>(Boxes.recipes);
    List<RecipeModel> allRecipes = recipeBox.values.toList();
    if (!mounted) return;
    // FIX: Removed unnecessary null check and assertion
    RecipeModel? selectedRecipe =
        (batch.recipeId.isNotEmpty) ? recipeBox.get(batch.recipeId) : null;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Sync From Recipe'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButton<RecipeModel>(
                  hint: const Text("Choose a recipe to sync from"),
                  isExpanded: true,
                  value: selectedRecipe,
                  items: allRecipes.map((recipe) {
                    return DropdownMenuItem<RecipeModel>(
                      value: recipe,
                      child: Text(recipe.name),
                    );
                  }).toList(),
onChanged: (RecipeModel? newValue) {
  if (newValue != null) {
    setState(() {
      selectedRecipe = newValue; // local only; don't mutate batch yet
    });
  }
},

                ),
                if (selectedRecipe != null)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      icon: const Icon(Icons.clear, size: 16),
                      label: const Text('Clear'),
onPressed: () {
  setState(() {
    selectedRecipe = null; // local only; don't touch the batch here
  });
},

                    ),
                  ),
                const SizedBox(height: 12),
                const Text('This will overwrite selected fields in the batch:'),
                const SizedBox(height: 12),
                CheckboxListTile(
                    value: syncYeast,
                    onChanged: (val) => setState(() => syncYeast = val ?? true),
                    title: const Text("Yeast")),
                CheckboxListTile(
                    value: syncIngredients,
                    onChanged: (val) =>
                        setState(() => syncIngredients = val ?? true),
                    title: const Text("Ingredients")),
                CheckboxListTile(
                    value: syncAdditives,
                    onChanged: (val) =>
                        setState(() => syncAdditives = val ?? true),
                    title: const Text("Additives")),
                CheckboxListTile(
                    value: syncStages,
                    onChanged: (val) =>
                        setState(() => syncStages = val ?? true),
                    title: const Text("Fermentation Stages")),
                CheckboxListTile(
                    value: syncTargets,
                    onChanged: (val) =>
                        setState(() => syncTargets = val ?? true),
                    title: const Text("Targets (Volume, OG, ABV)")),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () async {
                  final scaffoldMessenger = snacks;
                  final navigator = Navigator.of(dialogContext);
                  final newRecipe = RecipeModel(
id: generateId(),
name: batch.name,
createdAt: DateTime.now(),
// If your RecipeModel now has category:
category: batch.category ?? 'Uncategorized',
og: batch.og,
fg: batch.fg,
abv: batch.abv,
additives: batch.additives,
ingredients: batch.ingredients,
fermentationStages: batch.safeFermentationStages.toList(),
yeast: batch.yeast,
notes: batch.notes ?? '',
batchVolume: batch.batchVolume,
plannedOg: batch.plannedOg,
plannedAbv: batch.plannedAbv,
);

                  await recipeBox.put(newRecipe.id, newRecipe);

                  if (!mounted) return;

                  batch.recipeId = newRecipe.id;
                  batch.save();
                  await recalcPlannedOg(batch); // ← add

                  navigator.pop();
                  scaffoldMessenger.show(
                    const SnackBar(
                      content: Text('Recipe saved and linked'),
                      duration: Duration(seconds: 3),
                    ),
                  );
                },
                child: const Text('Save as New Recipe')),
            ElevatedButton(
              onPressed: selectedRecipe == null
                  ? null
                  : () => Navigator.pop(dialogContext, true),
              child: const Text('Sync'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;
    final recipe = selectedRecipe;
    if (recipe == null) return;   
    if (syncYeast) {
  batch.yeast = recipe.yeast
      .map<Map<String, dynamic>>((y) => recipeYeastToBatch(y as Map<String, dynamic>))
      .toList();
}
    batch.recipeId = recipe.id;


    
if (syncYeast) {
  final mappedYeast = recipe.yeast
      .map<Map<String, dynamic>>((y) => recipeYeastToBatch(y as Map<String, dynamic>))
      .toList();
  // preserve currently selected yeast by name if present
  if (batch.yeast.isNotEmpty) {
    final selectedName = (batch.yeast.first['name'] ?? '').toString();
    final preserved = mappedYeast.firstWhere(
      (y) => (y['name'] ?? '') == selectedName,
      orElse: () => mappedYeast.isNotEmpty ? mappedYeast.first : <String, dynamic>{},
    );
    batch.yeast = [preserved];
  } else {
    batch.yeast = mappedYeast.isNotEmpty ? [mappedYeast.first] : <Map<String, dynamic>>[];
  }
}

if (syncIngredients) {
  batch.ingredients = recipe.ingredients
      .map<Map<String, dynamic>>((ing) => recipeIngredientToBatch(ing as Map<String, dynamic>))
      .toList();
}

if (syncAdditives) {
  batch.additives = recipe.additives
      .map<Map<String, dynamic>>((a) => recipeAdditiveToBatch(a as Map<String, dynamic>))
      .toList();
}
    if (syncStages) {
      batch.fermentationStages =
          List<FermentationStage>.from(recipe.fermentationStages);
    }

    if (batch.fermentationStages.isNotEmpty) {
      DateTime nextStageStartDate = batch.startDate;
      for (var stage in batch.fermentationStages) {
        stage.startDate = nextStageStartDate;
        nextStageStartDate =
            nextStageStartDate.add(Duration(days: stage.durationDays));
      }
    }

    if (syncTargets) {
      batch.batchVolume = recipe.batchVolume;
      batch.plannedOg = recipe.plannedOg;
      batch.plannedAbv = recipe.plannedAbv;
    }
    batch.save();

    if (!syncTargets) {
      await recalcPlannedOg(batch);
    }
    if (mounted) setState(() {});

    if (mounted) {
      snacks.show(
        const SnackBar(
          content: Text('Batch synced from recipe'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  // ADD: safely add to the linked recipe (if any) using an ATTACHED Hive object
Future<void> _addIngredientToLinkedRecipeIfAny(
  BatchModel batch,
  Map<String, dynamic> ingredient,
) async {
  if (batch.recipeId.isEmpty) return; // no link, nothing to do

  final recipeBox = Hive.box<RecipeModel>(Boxes.recipes);
  final recipe = recipeBox.get(batch.recipeId);
  if (recipe == null) return; // stale link

  // mutate the ATTACHED instance and save
  recipe.ingredients = [...recipe.ingredients, ingredient];
  await recipe.save();

  if (!mounted) return;
  snacks.show(
    const SnackBar(content: Text('Also added to linked recipe')),
  );
}

  void _manageStages(BatchModel batch) async {
    final updatedStages = await showModalBottomSheet<List<FermentationStage>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ManageStagesDialog(
        initialStages: batch.safeFermentationStages,
        anchorStartDate: batch.startDate,
      ),
    );

if (updatedStages != null) {
  await _mutateBatch((b) => b.fermentationStages = updatedStages);
}
  }

  Widget _buildPreparationTab(BatchModel batch) {
    final currentPrepNotes = batch.prepNotes ?? '';
    if (_prepNotesController.text != currentPrepNotes) {
      _prepNotesController.text = currentPrepNotes;
      _prepNotesController.selection = TextSelection.fromPosition(
          TextPosition(offset: _prepNotesController.text.length));
    }

    final inventoryBox = Hive.box<InventoryItem>(Boxes.inventory);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Inventory Checklist'),
          ..._buildInventoryChecklist(batch, inventoryBox),
          const SizedBox(height: 16),
          _sectionTitle('Preparation Notes'),
          _buildPreparationNotesEditor(batch),
          _buildStatusProgressionButton(
            batch: batch,
            currentStatus: 'Preparation',
            nextStatus: 'Fermenting',
            buttonText: 'Start Fermenting',
          ),
        ],
      ),
    );
  }

  List<Widget> _buildInventoryChecklist(
      BatchModel batch, Box<InventoryItem> inventoryBox) {
    return [
      Card(
        margin: const EdgeInsets.symmetric(vertical: 4.0),
        child: ExpansionTile(
          title: const Text("Ingredients",
              style: TextStyle(fontWeight: FontWeight.bold)),
          initiallyExpanded: true,
          children: batch.ingredients.isEmpty
              ? [const ListTile(title: Text('No ingredients added.'))]
              : batch.ingredients
                  .asMap()
                  .entries
                  .map((entry) => _buildChecklistItem(
                        batch: batch,
                        itemData: entry.value,
                        inventoryBox: inventoryBox,
                        onChanged: (newValue) => _handleDeductionChange(
                          batch: batch,
                          itemType: 'ingredient',
                          item: entry.value,
                          index: entry.key,
                          newValue: newValue,
                          inventoryBox: inventoryBox,
                        ),
                      ))
                  .toList(),
        ),
      ),
      Card(
        margin: const EdgeInsets.symmetric(vertical: 4.0),
        child: ExpansionTile(
          title:
              const Text("Yeast", style: TextStyle(fontWeight: FontWeight.bold)),
          initiallyExpanded: true,
          children: batch.yeast.isEmpty
              ? [const ListTile(title: Text('No yeast added.'))]
              : batch.yeast
                  .asMap()
                  .entries
                  .map((entry) => _buildChecklistItem(
                        batch: batch,
                        itemData: Map<String, dynamic>.from(entry.value),
                        inventoryBox: inventoryBox,
                        onChanged: (newValue) => _handleDeductionChange(
                          batch: batch,
                          itemType: 'yeast',
                          item: entry.value,
                          index: entry.key,
                          newValue: newValue,
                          inventoryBox: inventoryBox,
                        ),
                      ))
                  .toList(),
        ),
      ),
      Card(
        margin: const EdgeInsets.symmetric(vertical: 4.0),
        child: ExpansionTile(
          title: const Text("Additives",
              style: TextStyle(fontWeight: FontWeight.bold)),
          initiallyExpanded: true,
          children: batch.additives.isEmpty
              ? [const ListTile(title: Text('No additives added.'))]
              : batch.additives
                  .asMap()
                  .entries
                  .map((entry) => _buildChecklistItem(
                        batch: batch,
                        itemData: entry.value,
                        inventoryBox: inventoryBox,
                        onChanged: (newValue) => _handleDeductionChange(
                          batch: batch,
                          itemType: 'additive',
                          item: entry.value,
                          index: entry.key,
                          newValue: newValue,
                          inventoryBox: inventoryBox,
                        ),
                      ))
                  .toList(),
        ),
      ),
    ];
  }

Widget _buildChecklistItem({
  required BatchModel batch,
  required Map<String, dynamic> itemData,
  required Box<InventoryItem> inventoryBox,
  required Future<void> Function(bool) onChanged,
}) {
  final name = itemData['name'] ?? 'Unnamed';
  final amount = (itemData['amount'] as num?)?.toDouble() ?? 0;
  final unit = itemData['unit'] ?? '';
  final note = itemData['note'] ?? '';
  final shouldDeduct = itemData['deductFromInventory'] ?? false;

  final inventoryItem = inventoryBox.values
      .cast<InventoryItem?>()
      .firstWhere(
        (item) => item?.name.toLowerCase() == name.toLowerCase(),
        orElse: () => null,
      );

  final inStock = inventoryItem?.amountInStock ?? 0;
  final sufficient = inStock >= amount;
  

  // Show the checkbox only if:
  //  - the item exists in inventory, and
  //  - user already deducted (so they can undo), OR there’s enough to deduct now
  final showCheckbox = inventoryItem != null && (shouldDeduct || sufficient);

  return Column(
    children: [
      ListTile(
        enabled: !shouldDeduct,
        title: Text(
          '$amount $unit $name',
          style: TextStyle(
            decoration:
                shouldDeduct ? TextDecoration.lineThrough : TextDecoration.none,
            color: shouldDeduct ? Colors.grey : null,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (note.isNotEmpty) Text(note),
            if (inventoryItem != null)
              Row(
                children: [
                  Text(
                    'In stock: ${inStock.toStringAsFixed(2)} $unit',
                    style: TextStyle(
                      color: sufficient ? Colors.green : Colors.red,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline, size: 20),
                    onPressed: () => _showQuickAddDialog(inventoryItem, unit),
                    tooltip: 'Quick-add to inventory',
                  ),
                  if (!sufficient && !shouldDeduct)
                    const Padding(
                      padding: EdgeInsets.only(left: 6),
                      child: Icon(Icons.warning, color: Colors.red, size: 18),
                    ),
                ],
              )
            else
              Row(
                children: [
                  Text(
                    'Not in Inventory',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    icon: const Icon(Icons.add_box_outlined, size: 20),
                    label: const Text('Create'),
                    onPressed: () => _showCreateInventoryItemDialog(name, unit),
                  ),
                ],
              ),
          ],
        ),
 trailing: (!sufficient && !shouldDeduct)
            ? ElevatedButton(
                onPressed: () {
                  if (!FeatureGate.instance.isPremium) {
                    snacks.show(
                      const SnackBar(
                        content: Text('Shopping List is a Premium feature'),
                      ),
                    );
                    showPaywall(context);
                    return;
                  }
                  final shoppingBox = Hive.box<ShoppingListItem>(Boxes.shoppingList);
                  final amountNeeded = amount - inStock;
                  if (amountNeeded > 0) {
                    final newItem = ShoppingListItem(
                      id: generateId(),
                      name: name,
                      amount: amountNeeded,
                      unit: unit,
                      recipeName: batch.name,
                    );
                    shoppingBox.put(newItem.id, newItem);
                    snacks.show(const SnackBar(
                      content: Text('Added item to shopping list!'),
                      duration: Duration(seconds: 2),
                    ));
                  }
                },
                child: const Icon(Icons.add_shopping_cart),
              )
            : null,
      ),
      if (showCheckbox)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
          child: CheckboxListTile(
            value: shouldDeduct,
            title: const Text('Deduct from Inventory'),
            onChanged: (val) {
              // Only allow turning ON when there’s enough.
              final want = val ?? false;
              if (want && !sufficient) return; // guard (shouldn’t be visible anyway)
              onChanged(want);
            },
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
    ],
  );
}

  void _showQuickAddDialog(InventoryItem item, String unit) async {
    final TextEditingController controller = TextEditingController();
    final amount = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Quick-add to ${item.name}'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: 'Amount to add ($unit)',
            suffixText: unit,
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d*'))
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final value = double.tryParse(controller.text);
              if (value != null && value > 0) {
                Navigator.pop(context, value);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (amount != null) {
      item.addPurchase(PurchaseTransaction(
        date: DateTime.now(),
        amount: amount,
        cost: item.costPerUnit,
      ));
      item.save();
      if (mounted) {
        snacks.show(
          SnackBar(
            content: Text('Added $amount $unit to ${item.name}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

void _showCreateInventoryItemDialog(String name, String unit) {
  final box = Hive.box<InventoryItem>(Boxes.inventory); // must match where you save

  // Allow opening even if it exists (will merge).
  final alreadyExists = box.values.any(
    (i) => i.name.toLowerCase() == name.toLowerCase(),
  );

  if (!alreadyExists) {
    // ✅ don't "watch" here
    final fg = context.read<FeatureGate>();
    final activeCount = box.values.where((i) => !i.isArchived).length;
    final atLimit = !fg.isPremium && activeCount >= fg.inventoryLimitFree;

    if (atLimit) {
      snacks.show(
        SnackBar(
          content: Text('Free limit reached (${fg.inventoryLimitFree}). Upgrade to add more.'),
          duration: const Duration(seconds: 2),
        ),
      );
      showPaywall(context);
      return;
    }
  }

  showDialog<void>(
    context: context,
    builder: (ctx) => AddInventoryDialog(initialData: {'name': name, 'unit': unit}),
  ).then((_) {
    if (!mounted) return;
    setState(() {}); // refresh “Not in inventory” -> “In stock …”
  });
}

  Future<void> _handleDeductionChange({
    required BatchModel batch,
    required String itemType,
    required Map<dynamic, dynamic> item,
    int index = -1,
    required bool newValue,
    required Box<InventoryItem> inventoryBox,
  }) async {
    final scaffoldMessenger = snacks;

    final name = item['name'] as String? ?? 'Unnamed';
    final amount = (item['amount'] as num?)?.toDouble() ?? 0;
    final unit = item['unit'] as String? ?? '';

    final inventoryItem = inventoryBox.values
        .cast<InventoryItem?>()
        .firstWhere(
          (i) => i?.name.toLowerCase() == name.toLowerCase(),
          orElse: () => null,
        );

    if (inventoryItem == null) {
      scaffoldMessenger.show(const SnackBar(
        content: Text('That item is not in inventory yet.'),
        duration: Duration(seconds: 3),
      ));
      return;
    }

    if (newValue) {
      final confirmed = await _confirmInventoryDeduction(
        context: context,
        name: name,
        inStock: inventoryItem.amountInStock,
        requested: amount,
        unit: unit,
      );
      if (!confirmed) return;
    }

    if (!mounted) return;

    switch (itemType) {
      case 'ingredient':
        (batch.ingredients[index])['deductFromInventory'] = newValue;
        break;
      case 'yeast':
        (batch.yeast[index])['deductFromInventory'] = newValue;
        break;
      case 'additive':
        (batch.additives[index])['deductFromInventory'] = newValue;
        break;
    }

    if (newValue) {
      inventoryItem.use(amount);
      scaffoldMessenger.show(SnackBar(
        content: Text('Used $amount $unit from $name'),
        duration: const Duration(seconds: 2),
      ));
    } else {
      inventoryItem.restore(amount);
      scaffoldMessenger.show(SnackBar(
        content: Text('Restored $amount $unit to $name'),
        duration: const Duration(seconds: 2),
      ));
    }
    batch.save();
    inventoryItem.save();
  }

/// Small row showing the linked device’s battery and last-seen.
/// We consider the first device where linkedBatchId == batchId.
Widget _deviceStatusRow({required String uid, required String batchId}) {
  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: FirestorePaths
        .devicesColl(uid)
        .where('linkedBatchId', isEqualTo: batchId)
        .limit(1)
        .snapshots(),
    builder: (context, snap) {
      final doc = (snap.data?.docs.isNotEmpty ?? false) ? snap.data!.docs.first : null;
      if (doc == null) return const SizedBox.shrink();

      final data     = doc.data();
      final name     = (data['name'] as String?) ?? 'Device';
      final battery  = (data['battery'] as num?)?.toDouble();
      final lastSeen = (data['lastSeen'] as Timestamp?)?.toDate();

      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Icon(_batteryIconForPercent(battery)),
            const SizedBox(width: 8),
            Text(name),
            const SizedBox(width: 12),
            Text(
              lastSeen == null ? 'Seen —' : 'Seen ${_timeAgoShort(lastSeen)}',
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    },
  );
}

// Stream the attached device's *name* for this batch (if any)

// Tiny pill shown on measurement rows if they came from a device
Widget _deviceBadge(Measurement m, {String? attachedName}) {
  if (m.fromDevice != true) return const SizedBox.shrink();

  // prefer label carried in the device point; else use the attached device's name; else generic
  final note = (m.notes ?? '').trim();
  final label = (note.isNotEmpty && note.toLowerCase() != 'device')
      ? note
      : (attachedName ?? 'Device');

  return Container(
    margin: const EdgeInsets.only(left: 6),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(label, style: Theme.of(context).textTheme.labelSmall),
  );
}

// Compact list of the most recent measurements with badges + quick actions
Widget _recentMeasurementsCard({
  required List<Measurement> measurements,
  String? deviceName,
  int maxItems = 12,
  required VoidCallback onOpenFullLog,
  required void Function(Measurement) onEdit,
  required void Function(Measurement) onDelete,
}) {
  final items = [...measurements]..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  final recent = items.take(maxItems).toList();
  if (recent.isEmpty) return const SizedBox.shrink();

  String fmt(Measurement m) {
    final t = DateFormat.Md().add_jm().format(m.timestamp.toLocal());
    final g = (m.gravity != null) ? m.gravity!.toStringAsFixed(3)
      : (m.brix != null) ? '${m.brix!.toStringAsFixed(1)}°Bx'
      : '—';
    final temp = (m.temperature != null)
        ? '${m.temperature!.toStringAsFixed(1)}°C'
        : '—';
    return '$t • SG/°Bx: $g • Temp: $temp';
  }

  return Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('Recent measurements',
                  style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              TextButton.icon(
                onPressed: onOpenFullLog,
                icon: const Icon(Icons.list),
                label: const Text('Full log'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: recent.length,
            separatorBuilder: (_, __) => const Divider(height: 8),
            itemBuilder: (_, i) {
              final m = recent[i];
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(fmt(m)),
                leading: Icon(m.fromDevice == true ? Icons.sensors : Icons.edit_note),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _deviceBadge(m, attachedName: deviceName),
                    const SizedBox(width: 6),
                    if (m.fromDevice != true)
                      IconButton(
                        tooltip: 'Edit',
                        icon: const Icon(Icons.edit),
                        onPressed: () => onEdit(m),
                      ),
                    if (m.fromDevice != true)
                      IconButton(
                        tooltip: 'Delete',
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => onDelete(m),
                      ),
                  ],
                ),
                onTap: () {
                  if (m.fromDevice != true) onEdit(m);
                },
              );
            },
          ),
        ],
      ),
    ),
  );
}

/// Merge lists preferring local (manual) points if within +/- 5 minutes of a device point.
List<Measurement> _mergeDeviceAndLocal({
  required List<Measurement> local,
  required List<Measurement> remote,
}) {
  final merged = <Measurement>[];
  int i = 0, j = 0;
  const fiveMin = Duration(minutes: 5);

  final l = [...local]..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  final r = [...remote]..sort((a, b) => a.timestamp.compareTo(b.timestamp));

  while (i < l.length && j < r.length) {
    final a = l[i], b = r[j];
    if (a.timestamp.isBefore(b.timestamp.subtract(fiveMin))) {
      merged.add(a); i++;
    } else if (b.timestamp.isBefore(a.timestamp.subtract(fiveMin))) {
      merged.add(b); j++;
    } else {
      merged.add(a); // close in time -> prefer local
      i++; j++;
    }
  }
  while (i < l.length) {
    merged.add(l[i++]);
  }
  while (j < r.length) {
    merged.add(r[j++]);
  }
  return merged;
}

// Keep only points in the last N days
List<Measurement> _limitByDays(List<Measurement> items, int days) {
  final cutoff = DateTime.now().subtract(Duration(days: days));
  return items.where((m) => m.timestamp.isAfter(cutoff)).toList();
}

// Cap total points for chart readability
List<Measurement> _capPoints(List<Measurement> items, int maxPoints) {
  if (items.length <= maxPoints) return items;
  final step = (items.length / maxPoints).ceil();
  final out = <Measurement>[];
  for (var i = 0; i < items.length; i += step) {
    out.add(items[i]);
  }
  return out;
}

Widget _buildFermentingTab(BatchModel batch) {
  final localSorted = [...batch.measurements]
    ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
final uid = _uid;          // nullable
final batchId = batch.id;  // non-null


  return ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text('Fermentation Progress',
                style: Theme.of(context).textTheme.titleLarge),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Add Measurement'),
            onPressed: () async {
              final sorted = [...batch.measurements]
                ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

              final newM = await showDialog<Measurement>(
                context: context,
                builder: (_) => AddMeasurementDialog(
                  previousMeasurement: sorted.isNotEmpty ? sorted.last : null,
                  firstMeasurementDate: sorted.isNotEmpty ? sorted.first.timestamp : null,
                ),
              );
              if (newM != null) {
                await _mutateBatch((b) => b.measurements.add(newM));
              }
            },
          ),
        ],
      ),
      const SizedBox(height: 12),

// ---- Device status row (only when signed-in) ----
// ---- Device status row (only when signed-in AND Premium) ----
if (uid != null && context.read<FeatureGate>().allowDevices)
  _deviceStatusRow(uid: uid, batchId: batchId),
const SizedBox(height: 4),

Builder(
  builder: (context) {
    final fg = context.read<FeatureGate>();

    // Not signed in -> show local-only chart
    if (uid == null) {
return Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
FermentationChartWidget(
  measurements: _capPoints(_limitByDays(localSorted, 30), 600),
  stages: batch.safeFermentationStages,
  onEditMeasurement: (m) async {
    if (m.fromDevice == true) return;
    await _openMeasurementEditor(batch, m);
  },
  onDeleteMeasurement: (m) => _handleDeleteMeasurement(batch, m),
  onManageStages: () => _manageStages(batch),
),

    const SizedBox(height: 8),
    _recentMeasurementsCard(
      measurements: localSorted,
      deviceName: null,
      onOpenFullLog: () {
        Navigator.of(context).push(MaterialPageRoute(
builder: (_) => MeasurementLogPage(
  batchId: batch.id,
  uid: null, // local-only
  local: localSorted,
  deviceName: null,
  onEditLocal: (m) => _openMeasurementEditor(batch, m),
),

        ));
      },
      onEdit: (m) => _openMeasurementEditor(batch, m),
      onDelete: (m) => _handleDeleteMeasurement(batch, m),
    ),
  ],
);


    }

   // Signed in but not Premium -> upsell + one-time (manual refresh) device data
if (!fg.allowDeviceStreaming) {
  // Lazily create the future only when we need it and uid is non-null
final cutoff30d = DateTime.now().subtract(const Duration(days: 30));
_deviceOnceFuture ??= FirestorePaths
    .batchMeasurements(uid, batchId)
    .where('timestamp', isGreaterThan: cutoff30d)
    .orderBy('timestamp', descending: false)
    .get();

  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Material(
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(.6),
        borderRadius: BorderRadius.circular(12),
        child: ListTile(
          dense: true,
          leading: const Icon(Icons.lock_outline),
          title: const Text('Live device updates are Premium'),
          subtitle: const Text('You can still view current device readings. Upgrade for live streaming.'),
          trailing: TextButton(
            onPressed: () => showPaywall(context),
            child: const Text('UPGRADE'),
          ),
        ),
      ),
      const SizedBox(height: 8),

      FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
        future: _deviceOnceFuture,
        builder: (context, snap) {
final remote = (snap.data?.docs ?? const [])
  .map<Measurement>((d) => fromRemoteDoc(d.data(), docId: d.id))
  .where((m) => m.gravity != null)
  .toList();
          final combined = _mergeDeviceAndLocal(local: localSorted, remote: remote);
          final chartData = _capPoints(_limitByDays(combined, 30), 600);


          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
FermentationChartWidget(
  measurements: chartData,
  stages: batch.safeFermentationStages,
onEditMeasurement: (m) async {
  if (m.fromDevice == true) return; // device points stay read-only
  await _openMeasurementEditor(batch, m);
},
  onDeleteMeasurement: (m) {
    if (m.fromDevice == true) return;
    _handleDeleteMeasurement(batch, m);
  },
  onManageStages: () => _manageStages(batch),
),

              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh device data'),
                  onPressed: () {
final cutoff30d = DateTime.now().subtract(const Duration(days: 30));
_deviceOnceFuture = FirestorePaths
    .batchMeasurements(uid, batchId)
    .where('timestamp', isGreaterThan: cutoff30d)
    .orderBy('timestamp', descending: false)
    .get();
                    setState(() {}); // re-run the FutureBuilder with the new future
                  },
                ),
              ),
            ],
          );
        },
      ),
    ],
  );
}


   // Signed in + Premium -> merge device + local in realtime
final cutoff30d = DateTime.now().subtract(const Duration(days: 30));

return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
  stream: FirestorePaths
      .batchMeasurements(uid, batchId)
      .where('timestamp', isGreaterThan: cutoff30d)
      .orderBy('timestamp', descending: false)
      .snapshots(),
  builder: (context, snap) {
    final remote = (snap.data?.docs ?? const [])
        .map<Measurement>((d) => fromRemoteDoc(d.data(), docId: d.id))
        .where((m) => m.gravity != null || m.brix != null)
        .toList();

    final combined  = _mergeDeviceAndLocal(local: localSorted, remote: remote);
    final chartData = _capPoints(_limitByDays(combined, 30), 600); // keep your client-side guard

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FermentationChartWidget(
          measurements: chartData,                  // <= use filtered data
          stages: batch.safeFermentationStages,
          onEditMeasurement: (m) async {
            if (m.fromDevice == true) return;
            await _openMeasurementEditor(batch, m);
          },
          onDeleteMeasurement: (m) {
            if (m.fromDevice == true) return;
            _handleDeleteMeasurement(batch, m);
          },
          onManageStages: () => _manageStages(batch),
        ),
        const SizedBox(height: 8),
        _recentMeasurementsCard(
          measurements: chartData,                 // <= also use filtered here
          deviceName: null,
          onOpenFullLog: () {
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => MeasurementLogPage(
                batchId: batch.id,
                uid: uid,
                local: localSorted,
                deviceName: null,
                onEditLocal: (m) => _openMeasurementEditor(batch, m),
              ),
            ));
          },
          onEdit: (m) => _openMeasurementEditor(batch, m),
          onDelete: (m) => _handleDeleteMeasurement(batch, m),
        ),
      ],
    );
  },
);

  },
),



      _buildStatusProgressionButton(
        batch: batch,
        currentStatus: 'Fermenting',
        nextStatus: 'Completed',
        buttonText: 'Mark as Completed',
        icon: Icons.check_circle_outline,
      ),
    ],
  );
}

  void _syncTextController(TextEditingController c, String text) {
  if (c.text != text) {
    c.value = c.value.copyWith(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
      composing: TextRange.empty,
    );
  }
}

void _syncCompletedControllersFrom(BatchModel b) {
  // DO NOT sync _finalYieldController here; it breaks typing
  _syncTextController(_tastingAromaController, b.tastingNotes?['aroma'] ?? '');
  _syncTextController(_tastingAppearanceController, b.tastingNotes?['appearance'] ?? '');
  _syncTextController(_tastingFlavorController, b.tastingNotes?['flavor'] ?? '');
  _syncTextController(_finalNotesController, b.finalNotes ?? ''); // optional: move notes sync here
}

  Widget _buildCompletedTab(BatchModel batch) {
    _tastingRating = batch.tastingRating ?? 0;
    _finalYieldUnit = batch.finalYieldUnit ?? 'gal';

final extrasFuture = BatchExtrasRepo().getOrCreate(batch.id);
  _syncCompletedControllersFrom(batch);

    Future<void> editFg() async {
      final c = TextEditingController(text: batch.fg?.toStringAsFixed(3) ?? '');
      final saved = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Edit Final Gravity'),
          content: TextField(
            controller: c,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(hintText: 'e.g., 1.010'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Save')),
          ],
        ),
      );
      if (saved == true) {
        batch.fg = double.tryParse(c.text);
        await batch.save();
        setState(() {});
      }
    }

    final presetChips = [
      {'label': '12 oz bottles', 'unit': '12oz bottle', 'method': 'Bottled'},
      {'label': '16 oz bottles', 'unit': '16oz bottle', 'method': 'Bottled'},
      {'label': '32 oz growlers', 'unit': '32oz growler', 'method': 'Bottled'},
      {'label': '5 gal keg', 'unit': '5gal keg', 'method': 'Kegged'},
      {'label': 'Bulk (gal)', 'unit': 'gal', 'method': 'Aged in Secondary'},
      {'label': 'Bulk (L)', 'unit': 'L', 'method': 'Aged in Secondary'},
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionCard(
          title: 'Final Summary',
          trailing: OutlinedButton.icon(
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Mark Completed'),
            onPressed: batch.status == 'Completed'
                ? null
                : () => _updateBatchStatus(batch, 'Completed'),
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _metricChip(
                icon: Icons.bubble_chart,
                label: 'OG',
                value: batch.og?.toStringAsFixed(3) ?? '—',
              ),
              _metricChip(
                icon: Icons.water_drop,
                label: 'FG',
                value: batch.fg?.toStringAsFixed(3) ?? '—',
                onTap: editFg,
              ),



FutureBuilder(
  future: extrasFuture,
  builder: (context, snap) {
    if (!snap.hasData) {
      return _metricChip(icon: Icons.percent, label: 'ABV', value: '—');
    }
    final extras = snap.data!;
    final abv = _computeAbv(
      batch: batch,
      useMeasured: extras.useMeasuredOg == true,
      measuredOg: extras.measuredOg,
    );
    return _metricChip(
      icon: Icons.percent,
      label: 'ABV',
      value: abv == null ? '—' : '${abv.toStringAsFixed(2)}%',
    );
  },
),


              _metricChip(
                icon: Icons.inventory_2_outlined,
                label: 'Yield',
                value: (batch.finalYield == null)
                    ? '—'
                    : '${batch.finalYield!.toStringAsFixed(2)} ${batch.finalYieldUnit ?? ''}',
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Rating:'),
                  const SizedBox(width: 8),
                  _starRow(
                    value: _tastingRating,
                    onChanged: (v) {
                      setState(() {
                        _tastingRating = v;
                        batch.tastingRating = v;
                        batch.save();
                      });
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        _sectionCard(
          title: 'Packaging & Yield',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_today),
                title: const Text('Packaging Date'),
                subtitle: Text(
                  batch.packagingDate == null
                      ? 'Not set'
                      : DateFormat.yMMMd().format(batch.packagingDate!),
                ),
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: batch.packagingDate ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (date != null) {
                    batch.packagingDate = date;
                    await batch.save();
                    setState(() {});
                  }
                },
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: batch.packagingMethod,
                decoration: const InputDecoration(labelText: 'Method'),
                items: const [
                  DropdownMenuItem(value: 'Bottled', child: Text('Bottled')),
                  DropdownMenuItem(value: 'Kegged', child: Text('Kegged')),
                  DropdownMenuItem(
                      value: 'Aged in Secondary',
                      child: Text('Aged in Secondary')),
                ],
                onChanged: (v) {
                  if (v != null) {
                    batch.packagingMethod = v;
                    batch.save();
                    setState(() {});
                  }
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
  controller: _finalYieldController,
  focusNode: _finalYieldFocus,
  keyboardType: const TextInputType.numberWithOptions(decimal: true),
  textInputAction: TextInputAction.done,            // NEW
  decoration: const InputDecoration(labelText: 'Final Yield'),
  onChanged: (v) {
    setState(() {});
    _finalYieldDebounce?.cancel();
    _finalYieldDebounce = Timer(const Duration(milliseconds: 500), _persistFinalYield);
  },
  onEditingComplete: _persistFinalYield,            // NEW
  onSubmitted: (_) => _persistFinalYield(),
),

                  ),
                  const SizedBox(width: 12),
                  DropdownButton<String>(
                    value: _finalYieldUnit,
                    onChanged: (u) {
                      if (u != null) {
                        setState(() {
                          _finalYieldUnit = u;
                          batch.finalYieldUnit = u;
                          batch.save();
                        });
                      }
                    },
                    items: const [
                      DropdownMenuItem(value: 'gal', child: Text('gal')),
                      DropdownMenuItem(value: 'L', child: Text('L')),
                      DropdownMenuItem(
                          value: '12oz bottle', child: Text('12oz bottle')),
                      DropdownMenuItem(
                          value: '16oz bottle', child: Text('16oz bottle')),
                      DropdownMenuItem(
                          value: '32oz growler', child: Text('32oz growler')),
                      DropdownMenuItem(value: '5gal keg', child: Text('5gal keg')),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: presetChips.map((p) {
                  return ActionChip(
                    avatar: const Icon(Icons.local_drink),
                    label: Text(p['label'] as String),
                    onPressed: () {
                      batch.packagingMethod = p['method'] as String;
                      batch.finalYieldUnit = p['unit'] as String;
                      batch.save();
                      setState(() {});
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              Builder(builder: (_) {
              final fy = double.tryParse(_finalYieldController.text.trim()) ?? batch.finalYield;
              final u  = batch.finalYieldUnit ?? _finalYieldUnit;
                if (fy == null) return const SizedBox.shrink();

                final n12 = _bottlesFromYield(
                    finalYield: fy, finalYieldUnit: u, bottleOz: 12);
                final n16 = _bottlesFromYield(
                    finalYield: fy, finalYieldUnit: u, bottleOz: 16);
                final n25 = _bottlesFromYield(
                    finalYield: fy, finalYieldUnit: u, bottleOz: 25.4);
                final kegs = (_toGallons(fy, u) / 5.0).toStringAsFixed(2);

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Estimated Packages',
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: [
                        Chip(label: Text('$n12 × 12oz')),
                        Chip(label: Text('$n16 × 16oz')),
                        Chip(label: Text('$n25 × 750mL')),
                        Chip(label: Text('$kegs × 5gal kegs')),
                      ],
                    ),
                  ],
                );
              }),
            ],
          ),
        ),
        _sectionCard(
          title: 'Tasting Notes',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                  controller: _tastingAromaController,
  decoration: const InputDecoration(labelText: 'Aroma'),
  onChanged: (v) {
    batch.tastingNotes ??= {};
    batch.tastingNotes!['aroma'] = v;
    batch.save();
  },
),
              TextField(
                controller: _tastingAppearanceController,
  decoration: const InputDecoration(labelText: 'Appearance'),
  onChanged: (v) {
    batch.tastingNotes ??= {};
    batch.tastingNotes!['appearance'] = v;
    batch.save();
  },
),
              TextField(
                controller: _tastingFlavorController,
                decoration: const InputDecoration(labelText: 'Flavor & Mouthfeel'),
                onChanged: (v) {
                  batch.tastingNotes ??= {};
                  batch.tastingNotes!['flavor'] = v;
                  batch.save();
                },
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: [
                  'Crisp',
                  'Dry',
                  'Tart',
                  'Fruity',
                  'Balanced',
                  'Funky',
                  'Sweet'
                ].map((t) {
                  return InputChip(
                    label: Text(t),
                    onPressed: () {
                      final current = _tastingFlavorController.text;
                      final next = current.isEmpty ? t : '$current, $t';
                      _tastingFlavorController.text = next;
                      _tastingFlavorController.selection =
                          TextSelection.fromPosition(
                        TextPosition(offset: next.length),
                      );
                      batch.tastingNotes ??= {};
                      batch.tastingNotes!['flavor'] = next;
                      batch.save();
                      setState(() {});
                    },
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        _sectionCard(
          title: 'Lessons Learned',
          child: TextField(
            controller: _finalNotesController,
            maxLines: 5,
            decoration: const InputDecoration(
              hintText:
                  'What would you do differently next time? What went well?',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) {
              batch.finalNotes = v;
              batch.save();
            },
          ),
        ),
        _sectionCard(
          title: 'Actions',
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.save_alt),
                label: const Text('Save as Recipe'),
onPressed: () async {
  // optional free/premium gate if you want to enforce it here:
  // if (!_guardRecipeLimit(context)) return;

  final abvVal = await _abvForBatch(batch);


  final recipeBox = Hive.box<RecipeModel>(Boxes.recipes);
  final newRecipe = RecipeModel(
    id: generateId(),
    name: '${batch.name} - Final',
    createdAt: DateTime.now(),
    og: batch.og,
    category: batch.category ?? 'Uncategorized',
    fg: batch.fg,
    abv: abvVal, // use calculated ABV (respects measured OG toggle)
    additives: batch.additives,
    ingredients: batch.ingredients,
    fermentationStages: batch.safeFermentationStages.toList(),
    yeast: batch.yeast,
    notes: batch.finalNotes ?? '',
    batchVolume: batch.batchVolume,
    plannedOg: batch.plannedOg,
    plannedAbv: batch.plannedAbv,
  );
  

  await recipeBox.put(newRecipe.id, newRecipe);

  if (!mounted) return;
  snacks.show(
    SnackBar(content: Text('Saved as new recipe: "${newRecipe.name}"')),
  );
},

              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.copy),
                label: const Text('Clone to New Batch'),
                onPressed: () {
                  if (!_guardActiveBatchLimit(context)) return; // <-- gate
                  final batchesBox = Hive.box<BatchModel>(Boxes.batches);

                  final clonedBatch = BatchModel(
                    id: generateId(),
                    createdAt: DateTime.now(),
                    name: '${batch.name} (Clone)',
                    startDate: DateTime.now(),
                    status: 'Planning',
                    recipeId: batch.recipeId,
                    category: batch.category,
                    ingredients:
                        List<Map<String, dynamic>>.from(batch.ingredients)
                            .map((e) {
                      e['deductFromInventory'] = false; // Reset deduction
                      return e;
                    }).toList(),
                    yeast: List<Map<String, dynamic>>.from(batch.yeast)
                        .map((e) {
                      e['deductFromInventory'] = false; // Reset deduction
                      return e;
                    }).toList(),
                    additives:
                        List<Map<String, dynamic>>.from(batch.additives)
                            .map((e) {
                      e['deductFromInventory'] = false; // Reset deduction
                      return e;
                    }).toList(),
                    fermentationStages:
                        List<FermentationStage>.from(batch.safeFermentationStages),
                    plannedEvents: [],
                    measurements: [],
                    batchVolume: batch.batchVolume,
                    plannedOg: batch.plannedOg,
                    plannedAbv: batch.plannedAbv,
                    og: null,
                    fg: null,
                    abv: null,
                    prepNotes: null,
                    finalYield: null,
                    finalYieldUnit: 'gal',
                    packagingDate: null,
                    packagingMethod: null,
                    tastingNotes: {},
                    tastingRating: 0,
                    finalNotes: null,
                  );

                  batchesBox.put(clonedBatch.id, clonedBatch);

                  if (!mounted) return;
                  snacks.show(const SnackBar(
                    content: Text('Batch cloned! Navigating to new batch...'),
                    duration: Duration(seconds: 2),
                  ));

                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (context) =>
                          BatchDetailPage(batchKey: clonedBatch.id),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ===== Helpers: metric chip, section card, star rating =====
  Widget _metricChip({
    required IconData icon,
    required String label,
    required String value,
    VoidCallback? onTap,
  }) {
    final chip = Chip(
      avatar: Icon(icon, size: 18),
      label: Text('$label: $value'),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
    );
    return onTap == null
        ? chip
        : InkWell(
            borderRadius: BorderRadius.circular(16), onTap: onTap, child: chip);
  }

// ---------- gravity & volume helpers ----------

double _volumeGalOf(Map<String, dynamic> item) {
  final unit = ((item['unit'] ?? '') as String).toLowerCase();
  final amt  = ((item['amount'] ?? 0) as num).toDouble();

  if (unit == 'oz') {
    // Bare "oz" here is ambiguous (mass vs volume). Require "fl oz" for volume.
    debugPrint('⚠️ Use "fl oz" for volume, "oz" for mass. Got oz in volume path for ${item['name']}');
    return 0.0;
  }

  switch (unit) {
    case 'gal':   return amt;
    case 'l':     return amt * 0.2641720524;
    case 'ml':    return amt * 0.0002641720524;
    case 'fl oz': return amt / 128.0;
    default:      return 0.0;
  }
}

/// Get an item's OG if present (e.g. a juice), else null.
double? _ogOf(Map<String, dynamic> item) {
  final raw = item['og'];
  if (raw == null) return null;
  final v = (raw is num) ? raw.toDouble() : double.tryParse(raw.toString());
  if (v == null || v <= 1.0) return null;
  return v;
}

/// Try to read known PPG directly from the map (preferred), else guess from name.
double _ppgFor(Map<String, dynamic> item) {
  // If the item already carries ppg/gravityPoints, use it
  final gp = item['ppg'] ?? item['gravityPoints'];
  if (gp is num) return gp.toDouble();

  final name = ((item['name'] ?? '') as String).toLowerCase();
  if (name.contains('table sugar') || name.contains('sucrose')) return 46.0;
  if (name.contains('dme') && name.contains('light')) return 44.0;
  if (name.contains('honey')) return 35.0;
  if (name.contains('corn sugar') || name.contains('dextrose')) return 42.0;
  if (name.contains('brown sugar')) return 46.0;
  if (name.contains('lme')) return 36.0;
  // add any other house defaults you want
  return 0.0;
}

/// Return how many lbs the item represents if it’s a mass unit; else 0.
double _poundsOf(Map<String, dynamic> item) {
  final unit = ((item['unit'] ?? '') as String).toLowerCase();
  final amt  = ((item['amount'] ?? 0) as num).toDouble();

  switch (unit) {
    case 'lb':
    case 'lbs':
      return amt;
    case 'oz': // mass-oz (ambiguous with fl oz; UI should avoid this)
      // If you allow mass-oz anywhere, rename your volume oz to "fl oz".
      return amt / 16.0;
    case 'kg':
      return amt * 2.2046226218;
    case 'g':
      return amt * 0.0022046226;
    default:
      return 0.0;
  }
}

/// GU contributed by *mass* fermentables (no volume added)
double _massGU(Map<String, dynamic> item) {
  final lbs = _poundsOf(item);
  if (lbs <= 0) return 0.0;
  return _ppgFor(item) * lbs; // PPG × pounds => gravity units
}

/// Weighted blend OG from all *liquids* that have an OG.
double? _blendedOgFromLiquids(List<Map<String, dynamic>> items) {
  double totalVolGal = 0.0, totalGU = 0.0;
  for (final it in items) {
    final v  = _volumeGalOf(it);
    final og = _ogOf(it);
    totalVolGal += v;
    if (og != null) totalGU += v * ((og - 1.0) * 1000.0);
  }
  if (totalVolGal <= 0) return null;
  return 1.0 + (totalGU / totalVolGal) / 1000.0;
}

/// Sum GU from all *mass* fermentables.
double _sumMassFermentablesGU(List<Map<String, dynamic>> items) {
  double gu = 0.0;
  for (final it in items) {
    gu += _massGU(it);
  }
  return gu;
}

  Widget _sectionCard({
    required String title,
    Widget? trailing,
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(16),
  }) {
    return Card(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                  child: Text(title,
                      style: Theme.of(context).textTheme.titleMedium)),
              if (trailing != null) trailing,
            ]),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _starRow({
    required int value,
    required ValueChanged<int> onChanged,
  }) {
    return Row(
      children: List.generate(5, (i) {
        final filled = i < value;
        return IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          icon: Icon(filled ? Icons.star : Icons.star_border,
              color: Colors.amber),
          onPressed: () => onChanged(i + 1),
        );
      }),
    );
  }

  // ===== Small utils for packaging math =====
  double _toGallons(double qty, String unit) {
    switch (unit) {
      case 'gal':
        return qty;
      case 'L':
        return qty * 0.264172;
      case '12oz bottle':
        return (qty * 12.0) / 128.0;
      case '16oz bottle':
        return (qty * 16.0) / 128.0;
      case '32oz growler':
        return (qty * 32.0) / 128.0;
      case '5gal keg':
        return qty * 5.0;
      default:
        return qty; // fallback assumes gal
    }
  }

  int _bottlesFromYield({
    required double? finalYield,
    required String finalYieldUnit,
    required double bottleOz,
  }) {
    if (finalYield == null) return 0;
    final totalOz = _toGallons(finalYield, finalYieldUnit) * 128.0;
    return (totalOz / bottleOz).floor();
  }

  Widget _buildPreparationNotesEditor(BatchModel batch) {
    final currentPrepNotes = batch.prepNotes ?? '';
    if (_prepNotesController.text != currentPrepNotes) {
      _prepNotesController.text = currentPrepNotes;
      _prepNotesController.selection = TextSelection.fromPosition(
          TextPosition(offset: _prepNotesController.text.length));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _prepNotesController,
          maxLines: 5,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'Add notes for your preparation steps...',
          ),
          onChanged: (value) {
            batch.prepNotes = value;
            batch.save();
          },
        ),
        const SizedBox(height: 8),
        const Text(
          'Tip: Track things like sanitizing, yeast hydration, or juice prep here.',
          style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
        ),
      ],
    );
  }

@override
Widget build(BuildContext context) {
  final box = Hive.box<BatchModel>(Boxes.batches);

  return ValueListenableBuilder<Box<BatchModel>>(
    valueListenable: box.listenable(keys: [_hiveKey]),
    builder: (context, b, _) {
      final batch = b.get(_hiveKey);

      if (batch == null) {
        return Scaffold(
          appBar: AppBar(title: const Text("Batch Not Found")),
          body: const Center(child: Text("This batch may have been deleted.")),
        );
      }

      final media = MediaQuery.of(context);
      final width = media.size.width;
      final double scale = MediaQuery.textScalerOf(context).scale(1.0);
      final bool needsScroll = width < 380 || scale > 1.0;
      final fg = context.watch<FeatureGate>();

      return Scaffold(
        appBar: AppBar(
          title: Text(batch.name),
          actions: [
  IconButton(
    icon: Icon(
      _isBrewModeEnabled ? Icons.lightbulb : Icons.lightbulb_outline,
      color: _isBrewModeEnabled ? Colors.amber : null,
    ),
    tooltip: 'Toggle Brew Mode',
    onPressed: _toggleBrewMode,
  ),
IconButton(
  tooltip: batch.isArchived ? 'Unarchive' : 'Archive',
  icon: Icon(batch.isArchived ? Icons.unarchive : Icons.archive_outlined),
  onPressed: () => _onArchiveToggle(batch),
),

  // ---- Device: Link to this batch (Premium) ----
ifSignedIn((uid) => IconButton(
  tooltip: 'Attach / change device',
  icon: const Icon(Icons.sensors),
  onPressed: () async {
    if (!fg.allowDevices) { showPaywall(context); return; }

    final dialogContext = context;

    final currentId = await _currentDeviceIdForBatch(uid, batch.id);
    if (!dialogContext.mounted) return;

    final result = await showAttachDeviceSheet(
      context: dialogContext,
      currentlyAttachedDeviceId: currentId,
      fetchDevices: () => _fetchDevicePickItems(uid: uid, batchId: batch.id),
      showAssignedToo: true,
      batchId: batch.id,
    );
    if (result == null) return;

    await _attachDeviceToBatch(uid: uid, batchId: batch.id, deviceId: result.deviceId);
    if (!dialogContext.mounted) return;

    snacks.show(SnackBar(
      content: Text(result.deviceId == null ? 'Device detached' : 'Device attached'),
    ));
    if (mounted) setState(() {});
  },
)),


// --- Export CSV (use fresh `batch.name` / `batch.id`) ---
ifSignedIn((uid) => IconButton(
 tooltip: 'Export CSV (device raw)',
 icon: const Icon(Icons.download),
 onPressed: () async {
  if (!fg.allowDeviceExport) {
   // If this context is from a StatefulWidget, you can use `context` directly
      // before any async operation.
   showPaywall(context);
   return;
  }

  // Capture the BuildContext before the first async gap.
  final dialogContext = context;

  String safe(String s) {
   // strip Windows-illegal chars + control chars
   s = s.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]+'), '_');
   s = s.replaceAll(RegExp(r'_+'), '_');
   s = s.replaceAll(RegExp(r'^[\s\.]+|[\s\.]+$'), '');
   return s.isEmpty ? 'file' : s;
  }

  final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
  final base = 'device_data_${batch.name}_$ts';
  final filename = '${safe(base)}.csv';

  // This is the first async operation (the async gap).
  final csv = await exportRawMeasurementsCsv(uid: uid, batchId: batch.id);

  // Check if the widget is still mounted after the first async gap.
  if (!dialogContext.mounted) return;

  // This is the second async operation. We must await it.
  await promptSaveCsv(context: dialogContext, filename: filename, csv: csv);

    // Check again before performing another UI operation.
  if (!dialogContext.mounted) return;

  // Now it's safe to show the snack bar.
  ScaffoldMessenger.of(dialogContext).showSnackBar(
   SnackBar(content: Text('Exported ${csv.length} chars of CSV.')),
  );
 },
))




          ],

          bottom: TabBar(
            controller: _tabController,
            isScrollable: needsScroll,
            tabAlignment: needsScroll ? TabAlignment.start : TabAlignment.center,
            labelPadding: const EdgeInsets.symmetric(horizontal: 16),
            tabs: const [
              Tab(text: 'Plan'),
              Tab(text: 'Prep'),
              Tab(text: 'Ferment'),
              Tab(text: 'Complete'),
            ],
          ),
        ),
        body: Column(
          children: [
            if (batch.isArchived)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.lock, size: 18),
                    SizedBox(width: 8),
                    Expanded(child: Text('This batch is archived and read-only.')),
                  ],
                ),
              ),
            Expanded(
              child: AbsorbPointer(
                absorbing: batch.isArchived == true,
                child: Opacity(
                  opacity: batch.isArchived == true ? 0.75 : 1.0,
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildPlanningTab(batch),
                      _buildPreparationTab(batch),
                      _buildFermentingTab(batch),
                      _buildCompletedTab(batch),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}
}
class MeasurementLogPage extends StatefulWidget {
  const MeasurementLogPage({
    super.key,
    required this.batchId,
    required this.uid,
    required this.local,
    required this.deviceName,
    this.onEditLocal, // NEW

  });

  final void Function(Measurement)? onEditLocal;
  final String batchId;
  final String? deviceName;
  final List<Measurement> local;
  final String? uid; // null => local-only

  @override
  State<MeasurementLogPage> createState() => _MeasurementLogPageState();
}

class _MeasurementLogPageState extends State<MeasurementLogPage> {
  static const _filters = <int?>[7, 30, 90, null];

  // null = All
  int? _days = 30;

  List<Measurement> _mergeAndSort({
    required List<Measurement> local,
    required List<Measurement> remote,
  }) {
    final all = <Measurement>[...local, ...remote];
    all.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return all;
  }

List<Measurement> _applyDayFilterTo(List<Measurement> items) {
  if (_days == null) return items;
  final cutoff = DateTime.now().subtract(Duration(days: _days!));
  return items.where((m) => m.timestamp.isAfter(cutoff)).toList();
}

  @override
  Widget build(BuildContext context) {
    Widget filterBar = Wrap(
      spacing: 8,
      children: _filters.map((d) {
        final label = d == null ? 'All' : 'Last $d d';
        final selected = _days == d;
        return ChoiceChip(
          label: Text(label),
          selected: selected,
          onSelected: (_) => setState(() => _days = d),
        );
      }).toList(),
    );
Widget deviceBadgeLocal(Measurement m) {
  if (m.fromDevice != true) return const SizedBox.shrink();
  final note = (m.notes ?? '').trim();
  final label = (note.isNotEmpty && note.toLowerCase() != 'device')
      ? note
      : (widget.deviceName ?? 'Device');

  return Container(
    margin: const EdgeInsets.only(left: 6),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(label, style: Theme.of(context).textTheme.labelSmall),
  );
}

    Future<List<Measurement>> fetchRemote() async {
      if (widget.uid == null) return const <Measurement>[];
      final ref = FirestorePaths
          .batchMeasurements(widget.uid!, widget.batchId)
          .orderBy('timestamp', descending: true);

      final q = (_days == null)
          ? ref.limit(2000)
          : ref.where(
              'timestamp',
              isGreaterThan: DateTime.now().subtract(Duration(days: _days!)),
            ).limit(2000);

      final snap = await q.get();
  return snap.docs
    .map<Measurement>((d) => fromRemoteDoc(d.data(), docId: d.id))
          .where((m) => m.gravity != null || m.brix != null)
          .toList();
    }

    Widget buildList(List<Measurement> items) {
      if (items.isEmpty) {
        return const Center(child: Padding(
          padding: EdgeInsets.all(24), child: Text('No measurements.')));
      }
      return ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: items.length,
        separatorBuilder: (_, __) => const Divider(height: 8),
        itemBuilder: (_, i) {
          final m = items[i];
          final ts = DateFormat.yMMMd().add_jm().format(m.timestamp.toLocal());
          final g  = (m.gravity != null) ? m.gravity!.toStringAsFixed(3)
                    : (m.brix != null) ? '${m.brix!.toStringAsFixed(1)}°Bx' : '—';
          final t  = (m.temperature != null) ? '${m.temperature!.toStringAsFixed(1)}°C' : '—';

          return ListTile(
            title: Text(ts),
            subtitle: Text('SG/°Bx: $g • Temp: $t'),
            leading: Icon(m.fromDevice == true ? Icons.sensors : Icons.edit_note),
            trailing: deviceBadgeLocal(m),
            onTap: () {
  if (m.fromDevice != true) {
    widget.onEditLocal?.call(m);
  }
},

          );
        },
      );
    }

    // Local-only
    if (widget.uid == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Measurement Log')),
        body: Column(
          children: [
            Padding(padding: const EdgeInsets.all(12), child: filterBar),
            Expanded(child: buildList(_mergeAndSort(local: _applyDayFilterTo(widget.local), remote: const []))),
          ],
        ),
      );
    }

    // With remote
    return Scaffold(
      appBar: AppBar(title: const Text('Measurement Log')),
      body: Column(
        children: [
          Padding(padding: const EdgeInsets.all(12), child: filterBar),
          Expanded(
            child: FutureBuilder<List<Measurement>>(
              future: fetchRemote(),
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
              final merged = _mergeAndSort(local: _applyDayFilterTo(widget.local), remote: snap.data ?? const []);
              return buildList(merged);
              },
            ),
          ),
        ],
      ),
    );
  }
}
