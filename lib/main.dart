import 'package:flutter/material.dart';
import 'package:fermentacraft/models/tag_manager.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:fermentacraft/models/batch_model.dart';
import 'package:fermentacraft/models/fermentation_stage.dart';
import 'package:fermentacraft/models/inventory_item.dart';
import 'package:fermentacraft/models/inventory_transaction_model.dart';
import 'package:fermentacraft/models/measurement_log.dart';
import 'package:fermentacraft/models/recipe_model.dart';
import 'package:fermentacraft/models/shopping_list_item.dart';
import 'package:fermentacraft/models/tag.dart';
// Page Imports
import 'batch_log_page.dart';
import 'inventory_page.dart';
import 'recipe_list_page.dart';
import 'settings_page.dart';
import 'tools_page.dart';
import 'shopping_list_page.dart';
import 'home_page.dart';

// Model Imports (only those directly used in this file)
import 'models/settings_model.dart';

// Theme Import
import 'theme/app_theme.dart';

Future<void> setupHive() async {
  await Hive.initFlutter();
  // IMPORTANT: Make sure all your registerAdapter() calls are here
  Hive.registerAdapter(BatchModelAdapter());
  Hive.registerAdapter(FermentationStageAdapter());
  Hive.registerAdapter(InventoryItemAdapter());
  Hive.registerAdapter(InventoryTransactionAdapter());
  Hive.registerAdapter(MeasurementLogAdapter());
  Hive.registerAdapter(RecipeModelAdapter());
  Hive.registerAdapter(ShoppingListItemAdapter());
  Hive.registerAdapter(TagAdapter());

  // IMPORTANT: Make sure all your openBox() calls are here
  await Hive.openBox<BatchModel>('batches');
  await Hive.openBox<FermentationStage>('fermentationStages');
  await Hive.openBox<InventoryItem>('inventory');
  await Hive.openBox<InventoryTransaction>('inventoryTransactions');
  await Hive.openBox<MeasurementLog>('measurementLogs');
  await Hive.openBox<RecipeModel>('recipes');
  await Hive.openBox('settings');
  await Hive.openBox<ShoppingListItem>('shopping_list');
  await Hive.openBox<Tag>('tags');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await setupHive();

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
      themeMode: settings.themeMode,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  static const List<Widget> _pages = <Widget>[
    HomePage(),
    RecipeListPage(),
    BatchLogPage(),
    InventoryPage(),
    ShoppingListPage(),
    ToolsPage(),
    SettingsPage(),
  ];


  void _selectPage(int index) {
    if (mounted) {
      Navigator.pop(context);
      setState(() {
        _selectedIndex = index;
      });
    }
  }

  void _showAboutAppDialog() async {
    Navigator.pop(context); // Close drawer first
    final packageInfo = await PackageInfo.fromPlatform();

    if (!mounted) return;

    showAboutDialog(
      context: context,
      applicationName: 'FermentaCraft',
      applicationVersion: packageInfo.version,
      applicationLegalese: '© 2025 Brian Petry',
      applicationIcon: Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 12),
        // FIX: Using the carboy logo, which is more suitable for an icon.
        child: Image.asset(
          'assets/images/logo.png',
          width: 80,
        ),
      ),
      children: [
        const SizedBox(height: 24),
        const Text("Your Craft, Perfected.\n\nFermentaCraft helps you design, track, and manage your homebrewing projects with precision and ease.")
      ]
    );
  }

  @override
  Widget build(BuildContext context) {
  return Scaffold(
    appBar: AppBar(
      title: Image.asset(
        'assets/images/fermentacraft_logo_txt.png',
        height: 22,
        // color: Theme.of(context).colorScheme.onPrimary,
      ),
      centerTitle: true, 
    ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Image.asset(
                    'assets/images/logo.png',
                    height: 60,
                    // color: Theme.of(context).colorScheme.onPrimary,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'FermentaCraft',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                  ),
                ],
              ),
            ),
            _buildDrawerItem(icon: Icons.home_outlined, title: 'Home', index: 0),
            _buildDrawerItem(icon: Icons.book_outlined, title: 'Recipes', index: 1),
            _buildDrawerItem(icon: Icons.science_outlined, title: 'Batches', index: 2),
            _buildDrawerItem(icon: Icons.inventory_2_outlined, title: 'Inventory', index: 3),
            _buildDrawerItem(icon: Icons.shopping_cart_outlined, title: 'Shopping List', index: 4),
            _buildDrawerItem(icon: Icons.construction_outlined, title: 'Tools', index: 5),
            const Divider(),
            _buildDrawerItem(icon: Icons.settings_outlined, title: 'Settings', index: 6),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('About'),
              onTap: _showAboutAppDialog,
            ),
          ],
        ),
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: _pages,
      ),
    );
  }

  // This simplified widget uses the ListTileTheme from your theme file.
  Widget _buildDrawerItem({required IconData icon, required String title, required int index}) {
    final isSelected = _selectedIndex == index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: ListTile(
        selected: isSelected,
        leading: Icon(icon),
        title: Text(
          title,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
        ),
        onTap: () => _selectPage(index),
      ),
    );
  }
}