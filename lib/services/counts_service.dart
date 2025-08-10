// lib/services/counts_service.dart
import 'package:hive/hive.dart';
import 'package:fermentacraft/models/recipe_model.dart';
import 'package:fermentacraft/models/batch_model.dart';
import 'package:fermentacraft/models/inventory_item.dart';

class CountsService {
  CountsService._();
  static final instance = CountsService._();

  int recipeCount() {
    final box = Hive.box<RecipeModel>('recipes');
    return box.length;
  }

  int activeBatchCount() {
    final box = Hive.box<BatchModel>('batches');
    // Treat null as false to be safe
    return box.values.where((b) => b.isArchived != true).length;
  }

  int archivedBatchCount() {
    final box = Hive.box<BatchModel>('batches');
    return box.values.where((b) => b.isArchived == true).length;
  }

  int inventoryCount() {
    final box = Hive.box<InventoryItem>('inventory');
    return box.length;
  }
}
