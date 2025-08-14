import 'package:hive_flutter/hive_flutter.dart';
import '../models/batch_extras.dart';

class BatchExtrasRepo {
  static const boxName = 'batch_extras';

  Future<Box<BatchExtras>> _box() async => Hive.openBox<BatchExtras>(boxName);

  Future<BatchExtras> getOrCreate(String batchId) async {
    final b = await _box();
    final existing = b.get(batchId);
    if (existing != null) return existing;
    final created = BatchExtras(batchId: batchId);
    await b.put(batchId, created);
    return created;
  }

  Future<void> setMeasuredOg(String batchId, double? og) async {
    final b = await _box();
    final e = await getOrCreate(batchId);
    e.measuredOg = og;
    await e.save();
    await b.put(batchId, e); // ensure keyed by batchId
  }

  Future<void> setUseMeasuredOg(String batchId, bool value) async {
    final b = await _box();
    final e = await getOrCreate(batchId);
    e.useMeasuredOg = value;
    await e.save();
    await b.put(batchId, e);
  }
}
