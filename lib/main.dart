import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';
import 'auth_gate.dart';

// Models / Hive adapters
import 'package:fermentacraft/models/batch_model.dart';
import 'package:fermentacraft/models/fermentation_stage.dart';
import 'package:fermentacraft/models/inventory_item.dart';
import 'package:fermentacraft/models/inventory_transaction_model.dart';
import 'package:fermentacraft/models/measurement_log.dart';
import 'package:fermentacraft/models/recipe_model.dart';
import 'package:fermentacraft/models/shopping_list_item.dart';
import 'package:fermentacraft/models/tag.dart';
import 'package:fermentacraft/models/purchase_transaction.dart';
import 'package:fermentacraft/models/unit_type.dart';
import 'package:fermentacraft/models/tag_manager.dart';
import 'models/settings_model.dart';
import 'utils/inventory_item_extensions.dart';

// Theme
import 'theme/app_theme.dart';

Future<void> setupHive() async {
  await Hive.initFlutter();

  Hive.registerAdapter(BatchModelAdapter());
  Hive.registerAdapter(FermentationStageAdapter());
  Hive.registerAdapter(InventoryItemAdapter());
  Hive.registerAdapter(InventoryTransactionAdapter());
  Hive.registerAdapter(MeasurementLogAdapter());
  Hive.registerAdapter(RecipeModelAdapter());
  Hive.registerAdapter(ShoppingListItemAdapter());
  Hive.registerAdapter(TagAdapter());
  Hive.registerAdapter(PurchaseTransactionAdapter());
  Hive.registerAdapter(UnitTypeAdapter());

  await Hive.openBox<BatchModel>('batches');
  await Hive.openBox<FermentationStage>('fermentationStages');
  await Hive.openBox<InventoryItem>('inventory');
  await Hive.openBox<InventoryTransaction>('inventoryTransactions');
  await Hive.openBox<MeasurementLog>('measurementLogs');
  await Hive.openBox<RecipeModel>('recipes');
  await InventoryArchiveStore.ensureOpen();
  await Hive.openBox('settings');
  await Hive.openBox<ShoppingListItem>('shopping_list');
  await Hive.openBox<Tag>('tags');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await setupHive();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsModel()),
        ChangeNotifierProvider(create: (_) => TagManager()),
      ],
      child: const FermentaCraftApp(),
    ),
  );
}

class FermentaCraftApp extends StatelessWidget {
  const FermentaCraftApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsModel>();
    return MaterialApp(
      title: 'FermentaCraft',
      debugShowCheckedModeBanner: false,
      themeMode: settings.themeMode,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      home: const AuthGate(),
    );
  }
}
