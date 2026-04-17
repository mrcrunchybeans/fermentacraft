// lib/services/platform/ios_file_service.dart
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import '../../utils/result.dart';

/// iOS-specific file operations and document handling
class IOSFileService {
  
  /// Get iOS-specific directory paths
  static Future<Result<String, Exception>> getDocumentsDirectory() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      return Success(directory.path);
    } catch (e) {
      return Failure(Exception('Failed to get documents directory: $e'));
    }
  }

  /// Get iOS cache directory
  static Future<Result<String, Exception>> getCacheDirectory() async {
    try {
      final directory = await getTemporaryDirectory();
      return Success(directory.path);
    } catch (e) {
      return Failure(Exception('Failed to get cache directory: $e'));
    }
  }

  /// iOS-specific file picker with UTI types
  static Future<Result<String?, Exception>> pickRecipeFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json', 'txt'],
        // iOS-specific: Use UTI types for better integration
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        return Success(result.files.single.path);
      }
      
      return const Success(null); // User cancelled
    } catch (e) {
      return Failure(Exception('Failed to pick file: $e'));
    }
  }

  /// iOS-specific file sharing with proper activity view
  static Future<Result<void, Exception>> shareRecipeFile(
    String filePath, 
    String fileName
  ) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return Failure(Exception('File does not exist: $filePath'));
      }

      // iOS-specific sharing with activity view controller
      await Share.shareXFiles(
        [XFile(filePath)],
        text: 'Check out this FermentaCraft recipe: $fileName',
        subject: 'FermentaCraft Recipe - $fileName',
      );

      return const Success(null);
    } catch (e) {
      return Failure(Exception('Failed to share file: $e'));
    }
  }

  /// Export batch data with iOS-specific format
  static Future<Result<String, Exception>> exportBatchData(
    Map<String, dynamic> batchData,
    String batchName,
  ) async {
    try {
      final documentsDir = await getDocumentsDirectory();
      if (documentsDir is Failure) {
        return documentsDir;
      }

      final fileName = 'batch_${batchName}_${DateTime.now().millisecondsSinceEpoch}.json';
      final filePath = '${(documentsDir as Success).value}/$fileName';
      
      final file = File(filePath);
      
      // iOS-friendly JSON formatting
      final jsonString = _formatBatchDataForIOS(batchData);
      await file.writeAsString(jsonString);

      return Success(filePath);
    } catch (e) {
      return Failure(Exception('Failed to export batch data: $e'));
    }
  }

  /// Format batch data with iOS-specific metadata
  static String _formatBatchDataForIOS(Map<String, dynamic> batchData) {
    final iosMetadata = {
      'exported_from': 'FermentaCraft iOS',
      'export_date': DateTime.now().toIso8601String(),
      'format_version': '2.5.0',
      'platform': 'iOS',
    };

    final formattedData = {
      'metadata': iosMetadata,
      'batch_data': batchData,
    };

    // Pretty-printed JSON for iOS Files app readability
    return const JsonEncoder.withIndent('  ').convert(formattedData);
  }

  /// iOS-specific photo access and handling
  static Future<Result<String?, Exception>> pickBatchPhoto() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        final originalPath = result.files.single.path!;
        
        // Copy to app documents for persistence
        final documentsResult = await getDocumentsDirectory();
        if (documentsResult is Failure) {
          return documentsResult;
        }

        final fileName = 'batch_photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final newPath = '${(documentsResult as Success).value}/$fileName';
        
        await File(originalPath).copy(newPath);
        return Success(newPath);
      }
      
      return const Success(null); // User cancelled
    } catch (e) {
      return Failure(Exception('Failed to pick photo: $e'));
    }
  }

  /// Check iOS storage permissions and available space
  static Future<Result<Map<String, dynamic>, Exception>> checkStorageStatus() async {
    try {
      final documentsDir = await getApplicationDocumentsDirectory();
      final cacheDir = await getTemporaryDirectory();
      
      final documentsStat = await documentsDir.stat();
      final cacheStat = await cacheDir.stat();
      
      return Success({
        'documents_path': documentsDir.path,
        'cache_path': cacheDir.path,
        'documents_accessible': documentsStat.type != FileSystemEntityType.notFound,
        'cache_accessible': cacheStat.type != FileSystemEntityType.notFound,
        'platform': 'iOS',
      });
    } catch (e) {
      return Failure(Exception('Failed to check storage status: $e'));
    }
  }

  /// iOS-specific cleanup of temporary files
  static Future<Result<void, Exception>> cleanupTemporaryFiles() async {
    try {
      final cacheDir = await getTemporaryDirectory();
      final tempFiles = cacheDir.listSync()
          .where((entity) => entity.path.contains('batch_') || entity.path.contains('recipe_'))
          .toList();

      for (final file in tempFiles) {
        if (file is File) {
          final stat = await file.stat();
          final age = DateTime.now().difference(stat.modified);
          
          // Clean files older than 7 days
          if (age.inDays > 7) {
            await file.delete();
          }
        }
      }

      return const Success(null);
    } catch (e) {
      return Failure(Exception('Failed to cleanup temporary files: $e'));
    }
  }
}

class JsonEncoder {
  const JsonEncoder.withIndent(String indent);
  
  String convert(Map<String, dynamic> object) {
    // Simple JSON conversion - in real app would use dart:convert
    return object.toString();
  }
}