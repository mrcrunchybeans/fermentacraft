import 'package:hive_flutter/hive_flutter.dart';

part 'batch_extras.g.dart';

@HiveType(typeId: 37) // <-- pick an unused id
class BatchExtras extends HiveObject {
  @HiveField(0)
  String batchId;

  @HiveField(1)
  double? measuredOg;

  @HiveField(2, defaultValue: false) // ← add default here
  bool useMeasuredOg;

  BatchExtras({
    required this.batchId,
    this.measuredOg,
    this.useMeasuredOg = false,
  });
}
