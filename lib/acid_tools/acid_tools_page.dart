// lib/acid_tools/acid_tools.dart
import 'package:flutter/material.dart';

import 'ta_acid_calculator_tab.dart';
import 'ph_acid_calculator_tab.dart';
import 'strip_reader_tab.dart';

import 'package:fermentacraft/services/feature_gate.dart';
import 'package:fermentacraft/widgets/soft_lock_overlay.dart';

class AcidToolsPage extends StatelessWidget {
  const AcidToolsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final fg = FeatureGate.instance;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Acid Tools"),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.science), text: "pH"),
              Tab(icon: Icon(Icons.tune), text: "TA"),
              Tab(icon: Icon(Icons.photo_camera), text: "Strip Reader"),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // pH tab stays fully available
            const PhAcidCalculatorTab(),

            // TA tab is visible but soft-locked when not Pro
            SoftLockOverlay(
              allow: fg.allowAcidTA,
              message: 'TA Calculator is a Pro feature',
              child: const TaAcidCalculatorTab(),
            ),

            // Strip Reader tab is visible but soft-locked when not Pro
            SoftLockOverlay(
              allow: fg.allowStripReader,
              message: 'Strip Reader is a Pro feature',
              child: const StripReaderTab(),
            ),
          ],
        ),
      ),
    );
  }
}
