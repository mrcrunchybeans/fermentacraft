import 'package:hive/hive.dart';

part 'tag.g.dart';

@HiveType(typeId: 9)
class Tag extends HiveObject {
  @HiveField(0)
  String name;

  Tag({required this.name});

  // --- ADDED for data export/import ---
  Map<String, dynamic> toJson() => {
        'name': name,
      };

  factory Tag.fromJson(Map<String, dynamic> json) => Tag(
        name: json['name'],
      );
  // --- END of added code ---

  @override
  String toString() {
    return name;
  }
}