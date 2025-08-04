import 'package:flutter/material.dart';
import 'package:flutter_application_1/models/measurement.dart';
import 'package:flutter_application_1/models/planned_event.dart';
import 'package:flutter_application_1/models/tag_manager.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'models/inventory_action.dart';
import 'models/purchase_transaction.dart';
import 'models/recipe_model.dart';
import 'batch_log_page.dart';
import 'inventory_page.dart';
import 'models/shopping_list_item.dart';
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
import 'shopping_list_page.dart';
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
  Hive.registerAdapter(InventoryActionAdapter());
  Hive.registerAdapter(ShoppingListItemAdapter());
  await Hive.openBox<InventoryAction>('inventory_actions');
  await Hive.openBox<RecipeModel>('recipes');
  await Hive.openBox('settings');
  await Hive.openBox<ShoppingListItem>('shopping_list');
  await Hive.openBox<Tag>('tags');
  await Hive.openBox<BatchModel>('batches');
  await Hive.openBox<MeasurementLog>('measurementLogs');
  await Hive.openBox<FermentationStage>('fermentationStages');
  await Hive.openBox<InventoryItem>('inventory');
  await Hive.openBox<InventoryTransaction>('inventoryTransactions');

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsModel()),
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
    final settings = context.watch<SettingsModel>();

    return MaterialApp(
      title: 'CiderCraft',
      themeMode: settings.themeMode,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.pink),
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.pink,
          brightness: Brightness.dark,
        ),
        brightness: Brightness.dark,
      ),
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
    Navigator.pop(context);
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
              leading: const Icon(Icons.shopping_cart_outlined),
              title: const Text('Shopping List'),
              onTap: () {
                Navigator.pop(context); // Close the drawer
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ShoppingListPage()),
                );
              },
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