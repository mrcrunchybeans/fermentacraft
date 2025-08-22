// lib/stores/ph_strip_store.dart
import 'dart:async';

import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

// This imports the PHStrip model (and its Hive adapter) you defined
// in strip_reader_tab.dart.
import '../acid_tools/strip_reader_tab.dart';

class PHStripStore {
  static const boxName = 'ph_strips';
  static final _uuid = const Uuid();

  Box<PHStrip>? _box;

  // Use a plain StreamController so you don't need rxdart.
  final _controller = StreamController<List<PHStrip>>.broadcast();

  /// A broadcast stream of the current list of strips (sorted by name).
  Stream<List<PHStrip>> get stripsStream => _controller.stream;

  /// Synchronous snapshot (null until first emit); keep your own cache if needed.
  List<PHStrip> _cache = const [];
  List<PHStrip> get current => _cache;

  Future<void> init() async {
    _box ??= await Hive.openBox<PHStrip>(boxName);
    _emit();
    // Re-emit whenever box changes.
    _box!.watch().listen((_) => _emit());
  }

  void _emit() {
    final list = _box!.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    _cache = list;
    if (!_controller.isClosed) _controller.add(list);
  }

  Future<PHStrip> create({
    required String name,
    required List<double> phValues,
    String? brand,
  }) async {
    final strip = PHStrip(
      id: _uuid.v4(),
      name: name,
      phValues: phValues,
      brand: brand,
    );
    await _box!.put(strip.id, strip);
    _emit();
    return strip;
  }

  Future<void> update(PHStrip strip) async {
    await _box!.put(strip.id, strip);
    _emit();
  }

  Future<void> delete(String id) async {
    await _box!.delete(id);
    _emit();
  }

  PHStrip? getById(String id) => _box!.get(id);

  Future<void> dispose() async {
    await _controller.close();
  }
}
