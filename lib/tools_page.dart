import 'package:flutter/material.dart';
import 'package:flutter_application_1/fsu_calculator_page.dart';
import 'package:flutter_application_1/so2_calculator_page.dart';
import 'package:flutter_application_1/acid_tools/acid_tools_page.dart';

import 'abv_calculator_page.dart';
import 'bubble_counter_page.dart';
import 'gravity_adjuster_page.dart';
import 'sg_correction_page.dart';
import 'unit_converter_page.dart';



class ToolsPage extends StatelessWidget {
  const ToolsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final tools = [
      ToolData("ABV Calculator", Icons.local_drink, const ABVCalculatorPage()),
      ToolData("SG Correction", Icons.thermostat, const SgCorrectionPage()),
      ToolData("SO₂ Estimator", Icons.science, const So2CalculatorPage()),
      ToolData("FSU Calculator", Icons.bubble_chart, const FSUCalculatorTab()),
      ToolData("Gravity Adjuster", Icons.scale, const GravityAdjustTool()),
      ToolData("Bubble Counter", Icons.av_timer, const BubbleCounterTab()),
      ToolData("Acid Tools", Icons.ac_unit, const AcidToolsPage()),
      ToolData(
        "Unit Converter",
        Icons.swap_horiz,
        const DefaultTabController(
          length: 4,
          child: UnitConverterTab(),
        ),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text("Cider Tools"),
        centerTitle: true,
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: tools.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
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
