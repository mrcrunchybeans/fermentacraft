// lib/services/logout.dart
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import 'package:fermentacraft/models/batch_model.dart';
import 'package:fermentacraft/utils/boxes.dart';
import 'package:fermentacraft/auth_gate.dart';
import 'package:fermentacraft/services/local_mode_service.dart';

Future<void> performLogout(BuildContext context) async {
  // Ensure Local Mode is disabled so AuthGate routes to LoginPage
  try {
    await LocalModeService.instance.clearLocalOnly();
  } catch (_) {/* ignore */}

  // Navigate away first so widgets stop listening to Hive
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const AuthGate()),
    (_) => false,
  );

  // Now it's safe to clear/close boxes
  try {
    if (Hive.isBoxOpen(Boxes.batches)) {
      await Hive.box<BatchModel>(Boxes.batches).clear();
    }
    // If you have other boxes, clear them here too (inventory, actions, etc.)
    // e.g. if (Hive.isBoxOpen(Boxes.inventory)) await Hive.box<InventoryItem>(Boxes.inventory).clear();

    await Hive.close(); // closes all boxes
  } catch (_) {
    // Swallow errors on logout; user has already been navigated away
  }
}
