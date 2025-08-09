// lib/main.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'firebase_options.dart';
import 'auth_gate.dart';

// Models / Hive adapters
import 'package:fermentacraft/models/batch_model.dart';
import 'package:fermentacraft/models/fermentation_stage.dart';
import 'package:fermentacraft/models/inventory_item.dart';
import 'package:fermentacraft/models/inventory_transaction_model.dart';
import 'package:fermentacraft/models/measurement.dart'; // ⬅️ NEW: embedded measurements
import 'package:fermentacraft/models/measurement_log.dart'; // keep if still used elsewhere
import 'package:fermentacraft/models/planned_event.dart';   // ⬅️ NEW: used by BatchModel
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

  // IMPORTANT: register the adapters for any types that appear inside others
  // BEFORE opening boxes that store those parent objects.
  Hive.registerAdapter(MeasurementAdapter());          // typeId: 6 (embedded in BatchModel)
  Hive.registerAdapter(FermentationStageAdapter());
  Hive.registerAdapter(PlannedEventAdapter());         // used by BatchModel
  Hive.registerAdapter(TagAdapter());
  Hive.registerAdapter(InventoryItemAdapter());
  Hive.registerAdapter(InventoryTransactionAdapter());
  Hive.registerAdapter(MeasurementLogAdapter());       // legacy/log use (optional)
  Hive.registerAdapter(RecipeModelAdapter());
  Hive.registerAdapter(ShoppingListItemAdapter());
  Hive.registerAdapter(PurchaseTransactionAdapter());
  Hive.registerAdapter(UnitTypeAdapter());
  Hive.registerAdapter(BatchModelAdapter());           // typeId: 34

  // Open boxes you actually store. You do NOT need a box for Measurement since
  // it's embedded in BatchModel (Option A).
  await Hive.openBox<BatchModel>('batches');
  await Hive.openBox<FermentationStage>('fermentationStages');
  await Hive.openBox<InventoryItem>('inventory');
  await Hive.openBox<InventoryTransaction>('inventoryTransactions');
  await Hive.openBox<MeasurementLog>('measurementLogs'); // keep if you still use it
  await Hive.openBox<RecipeModel>('recipes');
  await InventoryArchiveStore.ensureOpen(); // sidecar archive box
  await Hive.openBox('settings');
  await Hive.openBox<ShoppingListItem>('shopping_list');
  await Hive.openBox<Tag>('tags');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Catch uncaught framework errors.
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.dumpErrorToConsole(details);
    // If you add Crashlytics later, forward here.
  };

  await runZonedGuarded<Future<void>>(() async {
    // Firebase once.
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

    // Helpful while verifying sync. Turn off later if noisy.
    FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: true);
    FirebaseFirestore.setLoggingEnabled(true);

    // Local storage
    await setupHive();

    // Start live two-way sync (auth listener inside will start/stop on login/logout).
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
    // If you use Crashlytics: FirebaseCrashlytics.instance.recordError(error, stack);
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
