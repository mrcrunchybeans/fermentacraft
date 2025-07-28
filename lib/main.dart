import 'package:flutter/material.dart';
import 'package:flutter_application_1/models/planned_event.dart';
import 'package:flutter_application_1/models/tag_manager.dart';
import 'package:flutter_application_1/utils/temp_display.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'models/recipe_model.dart';
import 'batch_log_page.dart';
import 'inventory_page.dart';
import 'recipe_list_page.dart';
import 'settings_page.dart';
import 'tools_page.dart';
import 'models/settings_model.dart';
import 'models/tag.dart';
import 'models/batch_model.dart';
import 'models/fermentation_stage.dart';
import 'models/measurement_log.dart';



void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.deleteBoxFromDisk('recipes');
  Hive.registerAdapter(BatchModelAdapter());
  Hive.registerAdapter(FermentationStageAdapter());
  Hive.registerAdapter(MeasurementLogAdapter());
  Hive.registerAdapter(RecipeModelAdapter());
  Hive.registerAdapter(TagAdapter());
  Hive.registerAdapter(PlannedEventAdapter());


  final recipeBox = await Hive.openBox<RecipeModel>('recipes');
  await Hive.openBox('settings');
  await Hive.openBox<Tag>('tags');
  await Hive.openBox<BatchModel>('batches');
  await Hive.openBox<MeasurementLog>('measurementLogs');
  await Hive.openBox<FermentationStage>('fermentationStages');







  const bool isDev = true;
  if (isDev && recipeBox.isNotEmpty) {
    await recipeBox.clear();
  }

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
    return MaterialApp(
      title: 'CiderCraft',
      theme: ThemeData(
        primarySwatch: Colors.pink,
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
  String _selectedPage = 'Recipes';

  Widget _getPage() {
    switch (_selectedPage) {
      case 'Batches':
        return const BatchLogPage();
      case 'Inventory':
        return const InventoryPage();
      case 'Tools':
        return const ToolsPage();
      case 'Settings':
        return const SettingsPage();
      case 'Recipes':
      default:
        return const RecipeListPage();
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

