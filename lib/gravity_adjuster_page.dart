import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_application_1/utils/sugar_gravity_data.dart';
import '../widgets/stabilization_guidance_dialog.dart';


class GravityAdjustTool extends StatefulWidget {
  const GravityAdjustTool({super.key});

  @override
  State<GravityAdjustTool> createState() => _GravityAdjustToolState();
}

class _GravityAdjustToolState extends State<GravityAdjustTool> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Gravity Adjustment Tool"),
          bottom: const TabBar(
            tabs: [
              Tab(text: "Pre-Fermentation"),
              Tab(text: "Backsweeten"),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            PreFermentationAdjustTab(),
            BacksweetenAdjustTab(),
          ],
        ),
      ),
    );
  }
}

class PreFermentationAdjustTab extends StatefulWidget {
  const PreFermentationAdjustTab({super.key});

  @override
  State<PreFermentationAdjustTab> createState() => _PreFermentationAdjustTabState();
}

class _PreFermentationAdjustTabState extends State<PreFermentationAdjustTab> {
  Timer? abvDebounce;
  Timer? sgDebounce;
  bool userOverrodeAbv = false;

  final _abvController = TextEditingController();
  final _currentSGController = TextEditingController();
  final _fgController = TextEditingController(text: '1.000');
  String _formulaHelp = '';
  String _result = '';
  String _selectedSugar = 'Table Sugar (sucrose)';
  final _targetSGController = TextEditingController();
  bool _useGallons = true;
  final _volumeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _abvController.addListener(() {
      final val = double.tryParse(_abvController.text);
      final fg = double.tryParse(_fgController.text) ?? 1.000;
      if (val != null && val > 0 && val < 25) {
        userOverrodeAbv = true;
        sgDebounce?.cancel();
        sgDebounce = Timer(const Duration(milliseconds: 500), () {
          final requiredOG = (val / 131.25) + fg;
          final formattedOG = double.parse(requiredOG.toStringAsFixed(3));
          _targetSGController.text = formattedOG.toStringAsFixed(3);
          _calculate();
        });
      }
    });
  }

  String formatGallonsToGalCupOz(double gallons) {
    final int wholeGallons = gallons.floor();
    final double remainingGallons = gallons - wholeGallons;
    final int totalOz = (remainingGallons * 128).round();
    final int cups = totalOz ~/ 8;
    final int flOz = totalOz % 8;
    List<String> parts = [];
    if (wholeGallons > 0) parts.add("$wholeGallons gal");
    if (cups > 0) parts.add("$cups cup${cups > 1 ? 's' : ''}");
    if (flOz > 0) parts.add("$flOz fl oz");
    return parts.isNotEmpty ? parts.join(', ') : "0 fl oz";
  }

  void _calculate() {
    final double? volumeInput = double.tryParse(_volumeController.text);
    final double? currentSG = double.tryParse(_currentSGController.text);
    final double? targetSG = double.tryParse(_targetSGController.text);
    if (volumeInput == null || currentSG == null || targetSG == null) {
      setState(() {
        _result = 'Please enter valid numbers.';
        _formulaHelp = '';
      });
      return;
    }
    final double volumeGallons = _useGallons ? volumeInput : volumeInput / 3.78541;
    final double deltaSG = targetSG - currentSG;
    final double deltaPoints = deltaSG * 1000;
    final double? ppg = SugarGravityData.ppgMap[_selectedSugar];
    if (ppg == null) {
      setState(() {
        _result = 'Unknown sugar type selected.';
        _formulaHelp = '';
      });
      return;
    }
    if (deltaSG == 0) {
      setState(() {
        _result = 'No adjustment needed. Target and current SG are equal.';
        _formulaHelp = '';
      });
      return;
    }
    final poundsNeeded = (deltaPoints * volumeGallons) / ppg;
    final gramsNeeded = poundsNeeded * 453.592;
    setState(() {
      _result = 'Add ~${gramsNeeded.toStringAsFixed(1)}g of $_selectedSugar to reach ${targetSG.toStringAsFixed(3)} SG.';
      _formulaHelp =
          'Δ points = (${targetSG.toStringAsFixed(3)} - ${currentSG.toStringAsFixed(3)}) × 1000 = ${deltaPoints.toStringAsFixed(1)} pts\n'
          'Pounds = (Δ pts × Volume) / PPG\n'
          'Grams = Pounds × 453.592';
    });
    if (!userOverrodeAbv) {
      final og = double.tryParse(_targetSGController.text);
      final fg = double.tryParse(_fgController.text);
      if (og != null && fg != null && og > fg) {
        final abv = (og - fg) * 131.25;
        _abvController.text = abv.toStringAsFixed(2);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Pre-Fermentation Adjustment", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
Row(
  children: [
    Expanded(
      child: TextField(
        controller: _volumeController,
        decoration: InputDecoration(
          labelText: 'Volume (${_useGallons ? "gal" : "L"})',
        ),
        onChanged: (_) => _calculate(),
      ),
    ),
    const SizedBox(width: 8),
    DropdownButton<bool>(
      value: _useGallons,
      items: const [
        DropdownMenuItem(value: true, child: Text("Gallons")),
        DropdownMenuItem(value: false, child: Text("Liters")),
      ],
      onChanged: (value) {
        if (value != null) {
          setState(() {
            _useGallons = value;
            _calculate();
          });
        }
      },
    ),
  ],
),
          TextField(controller: _currentSGController, decoration: const InputDecoration(labelText: 'Current SG'), onChanged: (_) => _calculate()),
          TextField(controller: _targetSGController, decoration: const InputDecoration(labelText: 'Target SG'), onChanged: (_) => _calculate()),
          TextField(controller: _abvController, decoration: const InputDecoration(labelText: 'Desired ABV (%)'), onChanged: (_) => _calculate()),
          TextField(controller: _fgController, decoration: const InputDecoration(labelText: 'Predicted FG'), onChanged: (_) => _calculate()),
          DropdownButton<String>(
            value: _selectedSugar,
            isExpanded: true,
            items: SugarGravityData.ppgMap.keys.map((type) => DropdownMenuItem(value: type, child: Text(type))).toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() => _selectedSugar = value);
                _calculate();
              }
            },
          ),
          const SizedBox(height: 12),
          Text(_result, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          if (_formulaHelp.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.amber.shade100, borderRadius: BorderRadius.circular(6)),
              child: Text(_formulaHelp),
            ),
        ],
      ),
    );
  }
}

class BacksweetenAdjustTab extends StatefulWidget {
  const BacksweetenAdjustTab({super.key});

  @override
  State<BacksweetenAdjustTab> createState() => _BacksweetenAdjustTabState();
}

class _BacksweetenAdjustTabState extends State<BacksweetenAdjustTab> {
  final _currentSGController = TextEditingController();
  String _result = '';
  String _selectedSugar = 'Table Sugar (sucrose)';
  final _targetSGController = TextEditingController();
  final _phController = TextEditingController();
  bool _useGallons = true;
  final _volumeController = TextEditingController();

  void _calculate() {
    final double? volumeInput = double.tryParse(_volumeController.text);
    final double? currentSG = double.tryParse(_currentSGController.text);
    final double? targetSG = double.tryParse(_targetSGController.text);
    if (volumeInput == null || currentSG == null || targetSG == null) {
      setState(() => _result = 'Please enter valid numbers.');
      return;
    }
    final double volumeGallons = _useGallons ? volumeInput : volumeInput / 3.78541;
    final double deltaSG = targetSG - currentSG;
    final double deltaPoints = deltaSG * 1000;
    final double? ppg = SugarGravityData.ppgMap[_selectedSugar];
    if (ppg == null || deltaSG <= 0) {
      setState(() => _result = 'No sugar needed.');
      return;
    }
    final poundsNeeded = (deltaPoints * volumeGallons) / ppg;
    final gramsNeeded = poundsNeeded * 453.592;
    setState(() => _result = 'Add ~${gramsNeeded.toStringAsFixed(1)}g of $_selectedSugar to reach ${targetSG.toStringAsFixed(3)} SG.');
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Backsweetening Adjustment", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
Row(
  children: [
    Expanded(
      child: TextField(
        controller: _volumeController,
        decoration: InputDecoration(
          labelText: 'Volume (${_useGallons ? "gal" : "L"})',
        ),
        onChanged: (_) => _calculate(),
      ),
    ),
    const SizedBox(width: 8),
    DropdownButton<bool>(
      value: _useGallons,
      items: const [
        DropdownMenuItem(value: true, child: Text("Gallons")),
        DropdownMenuItem(value: false, child: Text("Liters")),
      ],
      onChanged: (value) {
        if (value != null) {
          setState(() {
            _useGallons = value;
            _calculate();
          });
        }
      },
    ),
  ],
),
          TextField(controller: _currentSGController, decoration: const InputDecoration(labelText: 'Current SG'), onChanged: (_) => _calculate()),
          TextField(controller: _targetSGController, decoration: const InputDecoration(labelText: 'Target SG'), onChanged: (_) => _calculate()),
          TextField(controller: _phController, decoration: const InputDecoration(labelText: 'Measured pH (optional)'), keyboardType: TextInputType.numberWithOptions(decimal: true),),

          DropdownButton<String>(
            value: _selectedSugar,
            isExpanded: true,
            items: SugarGravityData.ppgMap.keys.map((type) => DropdownMenuItem(value: type, child: Text(type))).toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() => _selectedSugar = value);
                _calculate();
              }
            },
          ),
          const SizedBox(height: 12),
          Text(_result, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ElevatedButton.icon(
  icon: const Icon(Icons.shield),
  label: const Text("Stabilization Dose Guide"),
  onPressed: () {
    final volumeInput = double.tryParse(_volumeController.text);
    if (volumeInput == null || volumeInput <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid volume first.')),
      );
      return;
    }
final volume = double.tryParse(_volumeController.text) ?? 1.0;
final ph = double.tryParse(_phController.text);

showDialog(
  context: context,
  builder: (_) => StabilizationGuidanceDialog(
    volume: volume,          // <- raw input from user
    isGallons: _useGallons,  // <- actual unit
    ph: ph,
  ),
);

  
  },
    ),
          ],
        
      ),
    );
  }
}
