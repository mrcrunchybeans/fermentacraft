// lib/services/counts_service.dart
import 'package:hive_flutter/hive_flutter.dart';
import 'package:fermentacraft/models/recipe_model.dart';
import 'package:fermentacraft/models/batch_model.dart';
import 'package:fermentacraft/models/inventory_item.dart';

import '../utils/boxes.dart';

class CountsService {
  CountsService._();
  static final instance = CountsService._();

  int recipeCount() {
    final box = Hive.box<RecipeModel>(Boxes.recipes);
    return box.length;
  }

  int activeBatchCount() {
    final box = Hive.box<BatchModel>(Boxes.batches); // ✅ opened in setup
    // Treat null as false to be safe
    return box.values.where((b) => b.isArchived != true).length;
  }

  int archivedBatchCount() {
    final box = Hive.box<BatchModel>(Boxes.batches); // ✅ opened in setup
    return box.values.where((b) => b.isArchived == true).length;
  }

  int inventoryCount() {
    final box = Hive.box<InventoryItem>(Boxes.inventory);
    return box.length;
  }
}
