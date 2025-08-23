import 'package:flutter/material.dart';
import 'package:fermentacraft/pages/fsu_calculator_page.dart';
import 'package:fermentacraft/pages/so2_calculator_page.dart';
import 'package:fermentacraft/acid_tools/acid_tools_page.dart';

import '../abv_calculator_page.dart';
import 'bubble_counter_page.dart';
import 'gravity_adjuster_page.dart';
import 'sg_correction_page.dart';
import 'unit_converter_page.dart';
import 'package:fermentacraft/services/review_prompter.dart';



class ToolsPage extends StatefulWidget {
  const ToolsPage({super.key});

  @override
  State<ToolsPage> createState() => _ToolsPageState();
}

class _ToolsPageState extends State<ToolsPage> {
  @override
  void initState() {
    super.initState();
    // Log that the Tools page was used today (idempotent per day)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ReviewPrompter.instance.fireToolsUsedToday(context);
    });
  }

  @override
  Widget build(BuildContext context) {

    final tools = [
      ToolData("ABV Calculator", Icons.percent, const ABVCalculatorPage()),
      ToolData("SG Correction", Icons.device_thermostat, const SgCorrectionPage()),
      ToolData("SO₂ Estimator", Icons.bubble_chart, const So2CalculatorPage()),
      ToolData("FSU Calculator", Icons.speed, const FSUCalculatorTab()),
      ToolData("Gravity Adjuster", Icons.scale, const GravityAdjustTool()),
      ToolData("Bubble Counter", Icons.timelapse, const BubbleCounterTab()),
      ToolData("Acid Tools", Icons.opacity, const AcidToolsPage()),
      ToolData(
        "Unit Converter",
        Icons.compare_arrows,
        const DefaultTabController(
          length: 4,
          child: UnitConverterTab(),
        ),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text("Tools"),
        centerTitle: true,
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: tools.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final tool = tools[index];
          return Card(
            elevation: 3,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              leading: Icon(tool.icon, size: 30, color: Theme.of(context).colorScheme.primary),
              title: Text(
                tool.name,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => tool.page),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class ToolData {
  final String name;
  final IconData icon;
  final Widget page;

  ToolData(this.name, this.icon, this.page);
}
