import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';

/// Saves [bytes] as [fileName]. Returns the saved path or null if cancelled.
Future<String?> saveBytesToDevice(String fileName, List<int> bytes) async {
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    final location = await getSaveLocation(suggestedName: fileName);
    if (location == null) return null;
    final file = File(location.path);
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  // Mobile: app documents directory
  final dir = await getApplicationDocumentsDirectory();
  final file = File('${dir.path}/$fileName');
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}
