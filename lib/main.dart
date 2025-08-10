// lib/main.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:fermentacraft/services/feature_gate.dart';
import 'firebase_options.dart';
import 'auth_gate.dart';

// Models / Hive adapters
import 'package:fermentacraft/models/batch_model.dart';
import 'package:fermentacraft/models/fermentation_stage.dart';
import 'package:fermentacraft/models/inventory_item.dart';
import 'package:fermentacraft/models/inventory_transaction_model.dart';
import 'package:fermentacraft/models/measurement.dart';
import 'package:fermentacraft/models/measurement_log.dart';
import 'package:fermentacraft/models/planned_event.dart';
import 'package:fermentacraft/models/recipe_model.dart';
import 'package:fermentacraft/models/shopping_list_item.dart';
import 'package:fermentacraft/models/tag.dart';
import 'package:fermentacraft/models/purchase_transaction.dart';
import 'package:fermentacraft/models/unit_type.dart';
import 'package:fermentacraft/models/tag_manager.dart';

import 'models/settings_model.dart';
import 'services/firestore_sync_service.dart';
import 'utils/inventory_item_extensions.dart'; // InventoryArchiveStore.ensureOpen()

// Theme
import 'theme/app_theme.dart';

Future<void> setupHive() async {
  await Hive.initFlutter();

  // Register adapters BEFORE opening boxes that use them
  Hive.registerAdapter(MeasurementAdapter());          // typeId: 6
  Hive.registerAdapter(FermentationStageAdapter());
  Hive.registerAdapter(PlannedEventAdapter());
  Hive.registerAdapter(TagAdapter());
  Hive.registerAdapter(InventoryItemAdapter());
  Hive.registerAdapter(InventoryTransactionAdapter());
  Hive.registerAdapter(MeasurementLogAdapter());
  Hive.registerAdapter(RecipeModelAdapter());
  Hive.registerAdapter(ShoppingListItemAdapter());
  Hive.registerAdapter(PurchaseTransactionAdapter());
  Hive.registerAdapter(UnitTypeAdapter());
  Hive.registerAdapter(BatchModelAdapter());           // typeId: 34

  // Open boxes actually used
  await Hive.openBox<BatchModel>('batches');
  await Hive.openBox<FermentationStage>('fermentationStages');
  await Hive.openBox<InventoryItem>('inventory');
  await Hive.openBox<InventoryTransaction>('inventoryTransactions');
  await Hive.openBox<MeasurementLog>('measurementLogs');
  await Hive.openBox<RecipeModel>('recipes');
  await InventoryArchiveStore.ensureOpen(); // sidecar archive box
  await Hive.openBox('settings');
  await Hive.openBox<ShoppingListItem>('shopping_list');
  await Hive.openBox<Tag>('tags');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // TEMP: Toggle Free/Pro for testing soft-locks (replace with RevenueCat later)
  FeatureGate.instance.isPro = false; // false = Free mode, true = Pro mode

  // Catch uncaught framework errors
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.dumpErrorToConsole(details);
    // Forward to Crashlytics here later if you add it.
  };

  await runZonedGuarded<Future<void>>(() async {
    // Firebase
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: true);
    FirebaseFirestore.setLoggingEnabled(true);

    // Local storage
    await setupHive();

    // Start sync service (auth listener inside handles start/stop)
    await FirestoreSyncService.instance.init();

    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsModel()),
          ChangeNotifierProvider(create: (_) => TagManager()),
        ],
        child: const FermentaCraftApp(),
      ),
    );
  }, (error, stack) {
    debugPrint('Uncaught zone error: $error\n$stack');
    // If you use Crashlytics later, forward here:
    // FirebaseCrashlytics.instance.recordError(error, stack);
  });
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
