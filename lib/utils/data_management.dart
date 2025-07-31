import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:developer' as dev;
import 'package:file_selector/file_selector.dart';

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

  static dynamic getTypedBox(String name) {
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
        return Hive.box(name);
    }
  }

  static Future<void> exportData(BuildContext context) async {
    try {
      final Map<String, dynamic> allData = {};

      for (final boxName in _boxNames) {
        final box = getTypedBox(boxName);
        final boxData = box.values.map((item) {
          try {
            return item.toJson();
          } catch (_) {
            return item;
          }
        }).toList();

        allData[boxName] = boxData;
      }

      final filePath = await DataManagementService().saveJsonBackup(allData);

        if ((Platform.isAndroid || Platform.isIOS) && filePath != null) {
      await Share.shareXFiles([XFile(filePath)], text: 'CiderCraft Backup');
    }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Data backup created successfully!')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error exporting data: $e')),
        );
      }
    }
  }

  static Future<void> importData(BuildContext context) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result == null || result.files.single.path == null) return;

      final file = File(result.files.single.path!);
      final jsonString = await file.readAsString();
      final allData = jsonDecode(jsonString) as Map<String, dynamic>;

      if (context.mounted) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("Confirm Import"),
            content: const Text(
                "This will overwrite all existing data. This action cannot be undone. Are you sure?"),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
              ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text("Import")),
            ],
          ),
        );

        if (confirmed != true) return;
      }

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
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error importing data: $e')),
        );
      }
    }
  }

Future<String?> saveJsonBackup(Map<String, dynamic> data) async {
  final jsonString = const JsonEncoder.withIndent('  ').convert(data);
  final timestamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:\\/*?"<>|]'), '_');
  final fileName = 'cidercraft_backup_$timestamp.json';

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    final fileSaveLocation = await getSaveLocation(
      suggestedName: fileName,
      acceptedTypeGroups: [XTypeGroup(extensions: ['json'])],
    );
    if (fileSaveLocation != null) {
      final file = File(fileSaveLocation.path);
      await file.writeAsString(jsonString);
      dev.log('Backup saved to ${file.path}');
      return file.path;
    }
  } else if (Platform.isAndroid || Platform.isIOS) {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(jsonString);
    dev.log('Backup saved to ${file.path}');
    return file.path;
  } else {
    throw UnsupportedError('Unsupported platform');
  }

  return null;
}
}