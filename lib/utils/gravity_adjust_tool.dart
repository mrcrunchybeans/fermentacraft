import 'package:flutter/material.dart';
import 'package:fermentacraft/utils/sugar_gravity_data.dart';

class GravityAdjustTool extends StatefulWidget {
  const GravityAdjustTool({super.key});

  @override
  State<GravityAdjustTool> createState() => _GravityAdjustToolState();
}

class _GravityAdjustToolState extends State<GravityAdjustTool> {
  final _volumeController = TextEditingController();
  final _currentSGController = TextEditingController();
  final _targetSGController = TextEditingController();

  String _result = '';
  String _selectedSugar = 'Table Sugar (sucrose)';

  void _calculate() {
    final double? volume = double.tryParse(_volumeController.text);
    final double? currentSG = double.tryParse(_currentSGController.text);
    final double? targetSG = double.tryParse(_targetSGController.text);

    if (volume == null || currentSG == null || targetSG == null) {
      setState(() {
        _result = 'Please enter valid numbers.';
      });
      return;
    }

    final deltaSG = (targetSG - currentSG);
  final ppg = SugarGravityData.ppgMap[_selectedSugar] ?? 46.0;
    final gramsPerGallon = deltaSG * 1000 * (1000 / ppg);
    final gramsNeeded = gramsPerGallon * volume;

    setState(() {
      _result = deltaSG > 0
          ? 'Add ~${gramsNeeded.toStringAsFixed(1)}g of $_selectedSugar'
          : 'Dilution needed — reduce gravity or remove sugar.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Gravity Adjustment Tool", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          TextField(
            controller: _volumeController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Batch Volume (gallons)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _currentSGController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Current SG',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _targetSGController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Target SG',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButton<String>(
            value: _selectedSugar,
            isExpanded: true,
          items: SugarGravityData.ppgMap.keys.map((type) {
              return DropdownMenuItem<String>(
                value: type,
                child: Text(type),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  _selectedSugar = value;
                });
              }
            },
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _calculate,
            child: const Text("Calculate Adjustment"),
          ),
          const SizedBox(height: 16),
          Text(
            _result,
            style: const TextStyle(fontSize: 16),
          ),
        ],
      ),
    );
  }
}
