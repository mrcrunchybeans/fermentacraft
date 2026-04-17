import 'package:hive/hive.dart';
import 'package:fermentacraft/models/recipe_model.dart';
import 'package:fermentacraft/models/fermentation_stage.dart';
import 'package:fermentacraft/models/tag.dart';

void main() async {
  Hive.init('./test_db'); // We can't init Hive easily outside flutter
  print("need to use flutter tools");
}
