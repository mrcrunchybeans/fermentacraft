import 'package:hive_flutter/hive_flutter.dart';

part 'planned_event.g.dart';

@HiveType(typeId: 5)
class PlannedEvent extends HiveObject {
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

  // --- ADDED for data export/import ---
  Map<String, dynamic> toJson() => {
        'title': title,
        'date': date.toIso8601String(),
        'notes': notes,
      };

  factory PlannedEvent.fromJson(Map<String, dynamic> json) => PlannedEvent(
        title: json['title'],
        date: DateTime.parse(json['date']),
        notes: json['notes'],
      );
  // --- END of added code ---
}
