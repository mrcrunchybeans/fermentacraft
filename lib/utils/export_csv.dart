// lib/utils/export_csv.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../services/firestore_paths.dart';

/// Build a CSV of raw device measurements for a given batch.
/// Columns: timestamp, sg, tempC, source
Future<String> exportRawMeasurementsCsv({
  required String uid,
  required String batchId,
}) async {
  final query = await FirestorePaths
      .batchMeasurements(uid, batchId)
      .orderBy('timestamp', descending: false)
      .get();

  final buf = StringBuffer();
  buf.writeln('timestamp,sg,tempC,source');

  for (final d in query.docs) {
    final m = d.data();
    final ts = (m['timestamp'] as Timestamp?)?.toDate();
    final sg = (m['sg'] as num?)?.toDouble();
    final temp = (m['tempC'] as num?)?.toDouble();
    final src = (m['src'] as String?) ?? 'device';

    final tsIso = ts?.toIso8601String() ?? '';
    final sgStr = (sg == null) ? '' : sg.toStringAsFixed(3);
    final tStr = (temp == null) ? '' : temp.toStringAsFixed(2);

    buf.writeln('$tsIso,$sgStr,$tStr,$src');
  }

  return buf.toString();
}

/// Prompts the user to save/share a CSV.
/// - On desktop/web: shows a Save dialog
/// - On Android/iOS: uses Share sheet
Future<void> promptSaveCsv({
  required BuildContext context,
  required String filename,
  required String csv,
}) async {
  // CAPTURE anything derived from context BEFORE any await:
  final platform = Theme.of(context).platform;
  final messenger = ScaffoldMessenger.of(context);

  final bytes = Uint8List.fromList(utf8.encode(csv));

  if (kIsWeb) {
    final saveLoc = await getSaveLocation(
      suggestedName: filename,
      acceptedTypeGroups: [const XTypeGroup(label: 'CSV', extensions: ['csv'])],
    );
    if (saveLoc == null) return;
    final file = XFile.fromData(bytes, name: filename, mimeType: 'text/csv');
    await file.saveTo(saveLoc.path);
    _showSnack(messenger, 'CSV saved');
    return;
  }

  switch (platform) {
    case TargetPlatform.windows:
    case TargetPlatform.linux:
    case TargetPlatform.macOS: {
      final saveLoc = await getSaveLocation(
        suggestedName: filename,
        acceptedTypeGroups: [const XTypeGroup(label: 'CSV', extensions: ['csv'])],
      );
      if (saveLoc == null) return;
      final file = XFile.fromData(bytes, name: filename, mimeType: 'text/csv');
      await file.saveTo(saveLoc.path);
      _showSnack(messenger, 'CSV saved');
      return;
    }
    case TargetPlatform.android:
    case TargetPlatform.iOS: {
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/$filename';
      final xfile = XFile.fromData(
        bytes,
        name: filename,
        mimeType: 'text/csv',
        path: path,
      );
      await Share.shareXFiles([xfile], text: 'FermentaCraft device data');
      return;
    }
    default: {
      final saveLoc = await getSaveLocation(
        suggestedName: filename,
        acceptedTypeGroups: [const XTypeGroup(label: 'CSV', extensions: ['csv'])],
      );
      if (saveLoc == null) return;
      final file = XFile.fromData(bytes, name: filename, mimeType: 'text/csv');
      await file.saveTo(saveLoc.path);
      _showSnack(messenger, 'CSV saved');
      return;
    }
  }
}

void _showSnack(ScaffoldMessengerState messenger, String msg) {
  messenger.showSnackBar(SnackBar(content: Text(msg)));
}
