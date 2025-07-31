import 'package:flutter/material.dart';
import 'package:flutter_application_1/models/measurement.dart';
import 'package:flutter_application_1/models/planned_event.dart';
import 'package:flutter_application_1/models/tag_manager.dart';
import 'package:flutter_application_1/utils/temp_display.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'models/purchase_transaction.dart';
import 'models/recipe_model.dart';
import 'batch_log_page.dart';
import 'inventory_page.dart';
import 'models/unit_type.dart';
import 'recipe_list_page.dart';
import 'settings_page.dart';
import 'tools_page.dart';
import 'models/settings_model.dart';
import 'models/tag.dart';
import 'models/batch_model.dart';
import 'models/fermentation_stage.dart';
import 'models/measurement_log.dart';
import 'models/inventory_item.dart';
import 'models/inventory_transaction_model.dart';
import 'home_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  Hive.registerAdapter(BatchModelAdapter());
  Hive.registerAdapter(FermentationStageAdapter());
  Hive.registerAdapter(MeasurementLogAdapter());
  Hive.registerAdapter(RecipeModelAdapter());
  Hive.registerAdapter(TagAdapter());
  Hive.registerAdapter(PlannedEventAdapter());
  Hive.registerAdapter(MeasurementAdapter());
  Hive.registerAdapter(InventoryItemAdapter());
  Hive.registerAdapter(InventoryTransactionAdapter());
  Hive.registerAdapter(UnitTypeAdapter());
  Hive.registerAdapter(PurchaseTransactionAdapter());

  await Hive.openBox<RecipeModel>('recipes');
  await Hive.openBox('settings');
  await Hive.openBox<Tag>('tags');
  await Hive.openBox<BatchModel>('batches');
  await Hive.openBox<MeasurementLog>('measurementLogs');
  await Hive.openBox<FermentationStage>('fermentationStages');
  await Hive.openBox<InventoryItem>('inventory');
  await Hive.openBox<InventoryTransaction>('inventoryTransactions');

  final useCelsius = Hive.box('settings').get('useCelsius', defaultValue: true);
  TempDisplay.setUseFahrenheit(!useCelsius);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) {
          final model = SettingsModel();
          model.setUnitFromStorage(useCelsius);
          return model;
        }),
        ChangeNotifierProvider(create: (_) => TagManager()),
      ],
      child: const CiderCraftApp(),
    ),
  );
}

class CiderCraftApp extends StatelessWidget {
  const CiderCraftApp({super.key});

  @override
  Widget build(BuildContext context) {
    // FIX 1: You need to get the settings model from the provider to use it.
    final settings = Provider.of<SettingsModel>(context);

    return MaterialApp(
      title: 'CiderCraft',
      // These lines now correctly use the settings model
      themeMode: settings.themeMode,
      theme: ThemeData(
        brightness: Brightness.light,
        primarySwatch: Colors.pink,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.pink,
      ),
      // FIX 2: Removed extra closing parenthesis that was causing a syntax error.
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _selectedPage = 'Home';

  Widget _getPage() {
    switch (_selectedPage) {
      case 'Recipes':
        return const RecipeListPage();
      case 'Batches':
        return const BatchLogPage();
      case 'Inventory':
        return const InventoryPage();
      case 'Tools':
        return const ToolsPage();
      case 'Settings':
        return const SettingsPage();
      case 'Home':
      default:
        return const HomePage();
    }
  }

  void _selectPage(String page) {
    Navigator.pop(context); // close the drawer
    setState(() {
      _selectedPage = page;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('CiderCraft – $_selectedPage')),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: Color.fromARGB(255, 108, 147, 73)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('CiderCraft',
                      style: TextStyle(color: Colors.white, fontSize: 24)),
                  SizedBox(height: 8),
                  Text('Brian Petry – Diamond',
                      style: TextStyle(color: Colors.white70)),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.home),
              title: const Text('Home'),
              onTap: () => _selectPage('Home'),
            ),
            ListTile(
              leading: const Icon(Icons.book),
              title: const Text('Recipes'),
              onTap: () => _selectPage('Recipes'),
            ),
            ListTile(
              leading: const Icon(Icons.local_drink),
              title: const Text('Batches'),
              onTap: () => _selectPage('Batches'),
            ),
            ListTile(
              leading: const Icon(Icons.inventory),
              title: const Text('Inventory'),
              onTap: () => _selectPage('Inventory'),
            ),
            ListTile(
              leading: const Icon(Icons.science),
              title: const Text('Tools'),
              onTap: () => _selectPage('Tools'),
            ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Settings'),
              onTap: () => _selectPage('Settings'),
            ),
          ],
        ),
      ),
      body: _getPage(),
    );
  }
}
