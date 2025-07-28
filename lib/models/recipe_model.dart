import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
import 'tag.dart';

part 'recipe_model.g.dart';

@HiveType(typeId: 0)
class RecipeModel extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  DateTime createdAt;

  @HiveField(3)
  List<Tag> tags;

  @HiveField(4)
  double og;

  @HiveField(5)
  double fg;

  @HiveField(6)
  double abv;

  @HiveField(7)
  List<Map<String, dynamic>> additives;

  @HiveField(8)
  List<Map<String, dynamic>> fermentables;

  @HiveField(9)
  List<Map<String, dynamic>> fermentationStages;

  @HiveField(10)
  List<Map<String, dynamic>> yeast;

  @HiveField(11)
  String notes;

  @HiveField(12)
  DateTime? lastOpened;

  RecipeModel({
    String? id,
    required this.name,
    required this.tags,
    required this.createdAt,
    required this.og,
    required this.fg,
    required this.abv,
    required this.additives,
    required this.fermentables,
    required this.fermentationStages,
    required this.yeast,
    this.notes = '',
    this.lastOpened,
  }) : id = id ?? const Uuid().v4();
}
