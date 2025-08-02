import 'dart:convert';
import 'dart:io' if (dart.library.html) 'dart:html'; // Use dart:io, but not on web

import 'package:flutter/foundation.dart' show kIsWeb; // To check for web platform
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'package:universal_html/html.dart' as html; // For web downloads

// Hive model imports
import '../models/recipe_model.dart';
import '../models/batch_model.dart';
import '../models/inventory_item.dart';
import '../models/tag.dart';

class DataManagementService {
  static const List<String> _boxNames = [
    'recipes',
    'settings',
    'tags',
    'batches',
    'inventory',
  ];

  static final Map<String, Function> _fromJsonConstructors = {
    'recipes': (json) => RecipeModel.fromJson(json),
    'batches': (json) => BatchModel.fromJson(json),
    'inventory': (json) => InventoryItem.fromJson(json),
    'tags': (json) => Tag.fromJson(json),
  };

  // Helper to get a typed Hive box
  static Box getTypedBox(String name) {
    switch (name) {
      case 'recipes':
        return Hive.box<RecipeModel>('recipes');
      case 'batches':
        return Hive.box<BatchModel>('batches');
      case 'inventory':
        return Hive.box<InventoryItem>('inventory');
      case 'tags':
        return Hive.box<Tag>('tags');
      case 'settings':
        return Hive.box('settings');
      default:
        throw Exception('Unknown box name: $name');
    }
  }

    static Future<void> clearAllData() async {
    for (final boxName in _boxNames) {
      await Hive.box(boxName).clear();
    }
  }

  /// Exports all Hive data to a JSON file.
  /// - On Web, it triggers a browser download.
  /// - On Desktop, it opens a "Save As" dialog.
  /// - On Mobile, it uses the native Share sheet.
static Future<void> exportData(BuildContext context) async {
  try {
    final Map<String, dynamic> allData = {};

    for (final boxName in _boxNames) {
      print("--- Processing Box: $boxName ---");
      final box = getTypedBox(boxName);

      if (boxName == 'settings') {
        final settingsMap = box.toMap();
        final typedSettingsMap = Map<String, dynamic>.from(settingsMap);
        allData[boxName] = [typedSettingsMap];
        continue;
      }

      // For all other boxes, check each item individually
      List<Map<String, dynamic>> boxData = [];
      for (var i = 0; i < box.length; i++) {
        final item = box.getAt(i);

        if (item == null) {
          print("Warning: Found a null item at index $i in box '$boxName'. Skipping.");
          continue;
        }

        try {
          // This is the critical call where the error is likely happening
          final Map<String, dynamic> jsonItem = item.toJson();
          boxData.add(jsonItem);
        } catch (e) {
          // This block will now catch the exact item that fails
          print("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!");
          print("!!! ERROR: Failed to call toJson() on an item.");
          print("!!! BOX: $boxName");
          print("!!! ITEM AT INDEX: $i");
          print("!!! ITEM's toString(): ${item.toString()}");
          print("!!! ERROR DETAILS: $e");
          print("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!");
          // Stop the export and show a helpful message
          throw Exception(
              "Failed to serialize item in box '$boxName'. Check the debug console for details.");
        }
      }
      allData[boxName] = boxData;
    }

    print("--- All data collected successfully. Encoding to JSON... ---");
    final jsonString = const JsonEncoder.withIndent('  ').convert(allData);
    print("--- JSON encoding successful. Proceeding to save... ---");

    bool didSave = false;
    final timestamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
    final fileName = 'cidercraft_backup_$timestamp.json';

      // Platform-specific saving logic
      
    if (kIsWeb) {
      final bytes = utf8.encode(jsonString);
      final blob = html.Blob([bytes]);
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)
        ..setAttribute("download", fileName)
        ..click();
      html.Url.revokeObjectUrl(url);
      didSave = true;
    } else if (Platform.isAndroid || Platform.isIOS) {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsString(jsonString);
      await Share.shareXFiles([XFile(file.path)], text: 'CiderCraft Backup');
      didSave = true;
    } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final fileSaveLocation = await getSaveLocation(suggestedName: fileName);
      if (fileSaveLocation != null) {
        final file = File(fileSaveLocation.path);
        await file.writeAsString(jsonString);
        didSave = true;
      }
    }


          if (context.mounted && didSave) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Data backup created successfully!')),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    
      }
    }
  }

  /// Imports data from a user-selected JSON file.
  /// This will overwrite all existing data.
  static Future<void> importData(BuildContext context) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: kIsWeb, // On web, we need the file bytes, not the path
      );

      if (result == null) return; // User canceled the picker

      // Show confirmation dialog before proceeding
      if (context.mounted) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("Confirm Import"),
            content: const Text("This will overwrite all existing data. This action cannot be undone. Are you sure?"),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
              ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text("Import")),
            ],
          ),
        );
        if (confirmed != true) return;
      }
      
      // Read file content based on platform
      String jsonString;
      if (kIsWeb) {
        // WEB: Read bytes from the result
        final fileBytes = result.files.single.bytes!;
        jsonString = utf8.decode(fileBytes);
      } else {
        // MOBILE/DESKTOP: Read from the file path
        final filePath = result.files.single.path!;
        final file = File(filePath);
        jsonString = await file.readAsString();
      }

      final allData = jsonDecode(jsonString) as Map<String, dynamic>;

      // Clear old data and import new data
      for (final boxName in _boxNames) {
        if (allData.containsKey(boxName)) {
          final box = getTypedBox(boxName);
          await box.clear();
          final boxData = allData[boxName] as List;

          for (var itemJson in boxData) {
            if (_fromJsonConstructors.containsKey(boxName)) {
              final item = _fromJsonConstructors[boxName]!(itemJson);
              await box.add(item);
            } else if (boxName == 'settings') {
              // Settings are stored as key-value pairs
              await box.putAll(Map<String, dynamic>.from(itemJson));
            }
          }
        }
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Data imported successfully! Please restart the app.')),
        );
      }

    } catch (e) {
    print("EXPORT FAILED WITH ERROR: $e");
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error exporting data: $e')),
      );
    }
  }
}
}