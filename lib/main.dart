// lib/main.dart
import 'dart:async';
import 'package:fermentacraft/utils/inventory_item_extensions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'firebase_options.dart';
import 'auth_gate.dart';

// Models / Hive adapters
import 'services/feature_gate.dart';
import 'services/revenuecat_service.dart';
import 'services/firestore_sync_service.dart';

import 'models/batch_model.dart';
import 'models/fermentation_stage.dart';
import 'models/inventory_item.dart';
import 'models/inventory_transaction_model.dart';
import 'models/measurement.dart';
import 'models/measurement_log.dart';
import 'models/planned_event.dart';
import 'models/recipe_model.dart';
import 'models/shopping_list_item.dart';
import 'models/tag.dart';
import 'models/purchase_transaction.dart';
import 'models/unit_type.dart';
import 'models/tag_manager.dart';
import 'models/settings_model.dart';

// Theme
import 'theme/app_theme.dart';

Future<void> setupHive() async {
  await Hive.initFlutter();

  // Register adapters BEFORE opening boxes that use them
  Hive.registerAdapter(MeasurementAdapter());
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
  Hive.registerAdapter(BatchModelAdapter());

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
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Configure Firestore once
  FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: true);
  FirebaseFirestore.setLoggingEnabled(true);

  // Local storage
  await setupHive();

  // Start your own sync service
  await FirestoreSyncService.instance.init();

  // Configure RevenueCat once.
  // On Android/iOS: sets up RC and listens to Firebase Auth changes (logIn/logOut).
  // On Windows/Web/Mac: skips RC and mirrors premium from Firestore (per your service).
  await RevenueCatService.instance.init();
  await FeatureGate.instance.bootstrap();


  // This is the line that was removed.
  // The service handles login after the user actually signs in.

  // Catch uncaught framework errors
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.dumpErrorToConsole(details);
    // Hook Crashlytics here later if you add it.
  };

  await runZonedGuarded<Future<void>>(() async {
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