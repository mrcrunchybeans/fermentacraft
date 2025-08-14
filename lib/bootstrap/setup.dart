// lib/bootstrap/setup.dart
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../firebase_options.dart';
import '../utils/boxes.dart';

// Import the model libraries (the ones with @HiveType + part 'x.g.dart')
import 'package:fermentacraft/models/unit_type.dart' as ut;
import 'package:fermentacraft/models/purchase_transaction.dart';
import 'package:fermentacraft/models/inventory_item.dart';
import 'package:fermentacraft/models/inventory_action.dart';
import 'package:fermentacraft/models/inventory_transaction_model.dart';
import 'package:fermentacraft/models/inventory_purchase.dart';
import 'package:fermentacraft/models/batch_model.dart';
import 'package:fermentacraft/models/recipe_model.dart';
import 'package:fermentacraft/models/shopping_list_item.dart';
import 'package:fermentacraft/models/tag.dart';
import 'package:fermentacraft/models/batch_extras.dart';

Future<void> setupAppServices() async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  try {
    FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: true);
  } catch (_) {}

  await Hive.initFlutter();

  // Guarded helper to avoid double registration on hot reload.
  void reg<T>(int typeId, TypeAdapter<T> a) {
    if (!Hive.isAdapterRegistered(typeId)) Hive.registerAdapter(a);
  }

  // Use YOUR actual @HiveType(typeId: ...) values:

  reg<ut.UnitType>(24, ut.UnitTypeAdapter());               // enum adapter from unit_type.g.dart
  reg<PurchaseTransaction>(2, PurchaseTransactionAdapter());
  reg<InventoryItem>(20, InventoryItemAdapter());
  reg<InventoryAction>(29, InventoryActionAdapter());
  reg<InventoryTransaction>(21, InventoryTransactionAdapter());
  reg<InventoryPurchase>(26, InventoryPurchaseAdapter());

  // The rest (only once)
  if (!Hive.isAdapterRegistered(BatchModelAdapter().typeId)) {
    Hive
      ..registerAdapter(BatchExtrasAdapter())
      ..registerAdapter(BatchModelAdapter())
      ..registerAdapter(RecipeModelAdapter())
      ..registerAdapter(ShoppingListItemAdapter())
      ..registerAdapter(TagAdapter());
  }

  await Future.wait([
    Hive.openBox<BatchModel>(Boxes.batches),
    Hive.openBox<InventoryItem>(Boxes.inventory),
    Hive.openBox<InventoryAction>(Boxes.inventoryActions), // typed box if you store actions
    Hive.openBox<RecipeModel>(Boxes.recipes),
    Hive.openBox(Boxes.settings),
    Hive.openBox<ShoppingListItem>(Boxes.shoppingList),
    Hive.openBox(Boxes.syncMeta),
    Hive.openBox<Tag>(Boxes.tags),
  ]);
}
