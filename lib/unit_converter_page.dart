import 'package:flutter/material.dart';

class UnitConverterTab extends StatelessWidget {
  const UnitConverterTab({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Unit Converter"),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.local_drink), text: "Volume"),
              Tab(icon: Icon(Icons.scale), text: "Mass"),
              Tab(icon: Icon(Icons.thermostat), text: "Temperature"),
              Tab(icon: Icon(Icons.bubble_chart), text: "Gravity"),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            UnitConverterCategoryTab(category: 'Volume'),
            UnitConverterCategoryTab(category: 'Mass'),
            UnitConverterCategoryTab(category: 'Temperature'),
            UnitConverterCategoryTab(category: 'Gravity'),
          ],
        ),
      ),
    );
  }
}

class UnitConverterCategoryTab extends StatefulWidget {
  final String category;
  const UnitConverterCategoryTab({required this.category, super.key});

  @override
  State<UnitConverterCategoryTab> createState() =>
      _UnitConverterCategoryTabState();
}

class _UnitConverterCategoryTabState extends State<UnitConverterCategoryTab> {
  final inputController = TextEditingController(text: '1.0');
  double inputValue = 1.0;

  late String fromUnit;
  late String toUnit;

  final Map<String, double> volumeUnits = {
    'mL': 1.0,
    'L': 1000.0,
    'fl oz': 29.5735,
    'cup': 236.588,
    'pint': 473.176,
    'quart': 946.353,
    'gal': 3785.41,
    '12 oz bottle': 355.0,
  };

  final Map<String, double> massUnits = {
    'mg': 0.001,
    'g': 1.0,
    'kg': 1000.0,
    'oz': 28.3495,
    'lb': 453.592,
  };

  final List<String> tempUnits = ['°C', '°F', 'K'];
  final List<String> gravityUnits = ['SG', 'SGP', '°Brix', '°Plato'];

  @override
  void initState() {
    super.initState();
    switch (widget.category) {
      case 'Volume':
        fromUnit = 'gal';
        toUnit = '12 oz bottle';
        break;
      case 'Mass':
        fromUnit = 'g';
        toUnit = 'lb';
        break;
      case 'Temperature':
        fromUnit = '°C';
        toUnit = '°F';
        break;
      case 'Gravity':
        fromUnit = 'SG';
        toUnit = '°Brix';
        break;
    }
  }

  List<String> getUnits() {
    switch (widget.category) {
      case 'Volume':
        return volumeUnits.keys.toList();
      case 'Mass':
        return massUnits.keys.toList();
      case 'Gravity':
        return gravityUnits;
      default:
        return tempUnits;
    }
  }

  double convert() {
    switch (widget.category) {
      case 'Temperature':
        return _convertTemp(inputValue, fromUnit, toUnit);
      case 'Gravity':
        return convertGravity(inputValue, fromUnit, toUnit);
      case 'Volume':
        return _convertWithMap(volumeUnits);
      case 'Mass':
        return _convertWithMap(massUnits);
      default:
        return 0;
    }
  }

  double _convertWithMap(Map<String, double> units) {
    final fromFactor = units[fromUnit];
    final toFactor = units[toUnit];
    if (fromFactor == null || toFactor == null) return 0;
    return (inputValue * fromFactor) / toFactor;
  }

  double _convertTemp(double val, String from, String to) {
    if (from == to) return val;
    if (from == '°C') return to == '°F' ? val * 9 / 5 + 32 : val + 273.15;
    if (from == '°F') {
      return to == '°C'
        ? (val - 32) * 5 / 9
        : (val - 32) * 5 / 9 + 273.15;
    }
    if (from == 'K') {
      return to == '°C'
        ? val - 273.15
        : (val - 273.15) * 9 / 5 + 32;
    }
    return val;
  }

double convertGravity(double val, String from, String to) {
  if (from == to) return val;

  // Plato ↔ Brix: direct 1:1 mapping is a reasonable approximation
  if ((from == '°Plato' && to == '°Brix') || (from == '°Brix' && to == '°Plato')) {
    return val;
  }

  // First, convert the input value from its original unit TO Specific Gravity (SG)
  double sg;
  switch (from) {
    case 'SG':
      sg = val;
      break;
    case 'SGP':
      sg = 1.0 + (val / 1000.0);
      break;
    case '°Brix':
    case '°Plato':
      sg = (val / (258.6 - ((val / 258.2) * 227.1))) + 1.0;
      break;
    default:
      sg = val; // Should not happen with the defined units
  }

  // Second, convert FROM Specific Gravity (SG) to the target unit
  switch (to) {
    case 'SG':
      return sg;
    case 'SGP':
      return (sg - 1.0) * 1000.0;
    case '°Brix':
    case '°Plato':
      // THIS IS THE CORRECTED FORMULA
      return (((182.4601 * sg - 775.6821) * sg + 1262.7794) * sg - 669.5622);
    default:
      return val; // Should not happen
  }
}


  String formatNumber(double value) {
    if (widget.category == 'Gravity') return value.toStringAsFixed(4);
    if (value >= 10000 || value < 0.001) return value.toStringAsExponential(3);
    return value.toStringAsFixed(3).replaceAll(RegExp(r"([.]*0+)(?!.*\d)"), "");
  }

  @override
  Widget build(BuildContext context) {
    final units = getUnits();
    final result = convert();

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _buildInputCard(units),
                ),
                IconButton(
                  icon: const Icon(Icons.swap_horiz),
                  onPressed: () => setState(() {
                    final temp = fromUnit;
                    fromUnit = toUnit;
                    toUnit = temp;
                  }),
                ),
                Expanded(
                  child: _buildOutputCard(units, result),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ExpansionTile(
              title: const Text("Show Conversion Formula",
                  style: TextStyle(fontSize: 16)),
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    getFormulaHint(),
                    style: const TextStyle(fontStyle: FontStyle.italic),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputCard(List<String> units) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            TextField(
              controller: inputController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24),
              onChanged: (val) {
                final parsed = double.tryParse(val);
                if (parsed != null) setState(() => inputValue = parsed);
              },
              onTap: () => inputController.selection = TextSelection(
                baseOffset: 0,
                extentOffset: inputController.text.length,
              ),
              decoration:
                  const InputDecoration(border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: fromUnit,
              onChanged: (val) => setState(() => fromUnit = val!),
              decoration: const InputDecoration(border: OutlineInputBorder()),
              borderRadius: BorderRadius.circular(10),
              items: units
                  .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOutputCard(List<String> units, double result) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(6),
              ),
              child: SelectableText(
                formatNumber(result),
                style: const TextStyle(fontSize: 24),
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: toUnit,
              onChanged: (val) => setState(() => toUnit = val!),
              decoration: const InputDecoration(border: OutlineInputBorder()),
              borderRadius: BorderRadius.circular(10),
              items: units
                  .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  String getFormulaHint() {
    if (widget.category == 'Temperature') {
      return "°F ↔ °C: (°F - 32) × 5/9 = °C\n°C ↔ K: °C + 273.15 = K";
    }
    if (widget.category == 'Mass' || widget.category == 'Volume') {
      final units = widget.category == 'Mass' ? massUnits : volumeUnits;
      final from = units[fromUnit];
      final to = units[toUnit];
      if (from == null || to == null) return "Conversion formula unavailable.";
      final mult = from / to;
      return "1 $fromUnit = ${mult.toStringAsFixed(3)} $toUnit";
    }
    if (widget.category == 'Gravity') {
      return "Gravity conversions are calculated by converting all units to Specific Gravity (SG) as an intermediate:\n"
        "- °Brix/°Plato → SG: (Brix / (258.6 - ((Brix / 258.2) * 227.1))) + 1\n"
        "- SG → °Brix/°Plato: (((182.46 * SG - 775.68) * SG + 1262.78) * SG - 669.56)";
    }
    return "No formula found.";
  }
}
