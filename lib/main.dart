// lib/main.dart
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Firebase
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// App
import 'firebase_options.dart';
import 'auth_gate.dart';

// Services
import 'services/feature_gate.dart';
import 'services/revenuecat_service.dart';
import 'services/firestore_sync_service.dart';
import 'services/auth_service.dart';
import 'services/tester_premium_service.dart';

// Hive / Models
import 'package:hive_flutter/hive_flutter.dart';
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
import 'utils/inventory_item_extensions.dart';
import 'utils/migrations.dart';

// Theme
import 'theme/app_theme.dart';

/// ---------------- Hive setup ----------------
Future<void> setupHive() async {
  await Hive.initFlutter();

  // Register adapters BEFORE opening boxes
  Hive
    ..registerAdapter(MeasurementAdapter())
    ..registerAdapter(FermentationStageAdapter())
    ..registerAdapter(PlannedEventAdapter())
    ..registerAdapter(TagAdapter())
    ..registerAdapter(InventoryItemAdapter())
    ..registerAdapter(InventoryTransactionAdapter())
    ..registerAdapter(MeasurementLogAdapter())
    ..registerAdapter(RecipeModelAdapter())
    ..registerAdapter(ShoppingListItemAdapter())
    ..registerAdapter(PurchaseTransactionAdapter())
    ..registerAdapter(UnitTypeAdapter())
    ..registerAdapter(BatchModelAdapter());

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

  // ✅ Run migrations AFTER boxes are open
  await migrateTagIconsIfNeeded();
  await migrateEmbeddedTagsIfNeeded();
}

/// Coordinates a single “claim tester premium” call per sign-in.
class _PremiumClaimCoordinator {
  String? _lastClaimedUid;
  StreamSubscription<User?>? _sub;

  void start() {
    _sub ??= FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user == null) return;
      if (_lastClaimedUid == user.uid) return; // already claimed this session
      _lastClaimedUid = user.uid;
      try {
        await TesterPremiumService.instance.claim(); // callable + refresh RC
      } catch (e) {
        debugPrint('Premium claim failed: $e');
      }
    });
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}

final _premiumClaimCoordinator = _PremiumClaimCoordinator();

Future<void> _initFirebase() async {
  // Avoid double init (especially on web when hot-reloading)
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  // Firestore: enable local persistence & logging (wrap to be safe on any platform)
  try {
    FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: true);
  } catch (e) {
    debugPrint('Firestore settings warning: $e');
  }
  try {
    FirebaseFirestore.setLoggingEnabled(true);
  } catch (e) {
    debugPrint('Firestore logging warning: $e');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase
  try {
    await _initFirebase();
  } catch (e, st) {
    debugPrint('Firebase init failed: $e\n$st');
  }

  // ✅ WEB-ONLY: finish Google redirect sign-in if popup was blocked
  if (kIsWeb) {
    try {
      await AuthService.instance.completePendingRedirectIfAny();
    } catch (e) {
      debugPrint('Auth redirect completion failed: $e');
    }
  }

  // Local storage
  await setupHive();

  // App services
  await FirestoreSyncService.instance.init();
  await RevenueCatService.instance.init();
  await FeatureGate.instance.bootstrap();

  // Begin auto-claim flow (safe no-op if not allowlisted)
  _premiumClaimCoordinator.start();

  // Global error handling
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.dumpErrorToConsole(details);
  };

  runZonedGuarded(() {
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
      builder: (context, child) => SafeArea(
        top: false,
        left: false,
        right: false,
        bottom: true,
        maintainBottomViewPadding: true,
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
