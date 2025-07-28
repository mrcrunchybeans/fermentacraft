import 'package:hive/hive.dart';

part 'planned_event.g.dart';

@HiveType(typeId: 15)
class PlannedEvent {
  @HiveField(0)
  String title;

  @HiveField(1)
  DateTime date;

  @HiveField(2)
  String? notes;

  PlannedEvent({
    required this.title,
    required this.date,
    this.notes,
  });
}
