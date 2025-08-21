import 'package:flutter/material.dart';
import 'dart:async';

class FSUCalculatorTab extends StatefulWidget {
  const FSUCalculatorTab({super.key});

  @override
  State<FSUCalculatorTab> createState() => _FSUCalculatorTabState();
}

Color _getFSUColor(double fsu) {
  if (fsu > 400) return Colors.red.shade400;
  if (fsu > 350) return Colors.orange.shade400;
  if (fsu >= 250) return Colors.green.shade600;
  if (fsu > 50) return Colors.orange.shade300;
  return Colors.blueGrey.shade400;
}

String _getFSUMessage(double fsu) {
  if (fsu > 400) return "� ️ Faster than typical primary fermentation.";
  if (fsu > 350) return "Slightly fast, monitor fermentation closely.";
  if (fsu >= 250) return "✅ Ideal rate for primary fermentation.";
  if (fsu > 50) return "Secondary fermentation or slow primary.";
  return "Very low activity — likely secondary or stalled.";
}

class _FSUCalculatorTabState extends State<FSUCalculatorTab> {
  DateTime date1 = DateTime.now().subtract(const Duration(days: 1));
  DateTime date2 = DateTime.now();
  final sg1Controller = TextEditingController();
  final sg2Controller = TextEditingController();

  double? fsu;

  Future<void> _pickDate(BuildContext context, bool isFirst) async {
    final initial = isFirst ? date1 : date2;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        if (isFirst) {
          date1 = picked;
        } else {
          date2 = picked;
        }
        _calculateFSU();
      });
    }
  }

  void _calculateFSU() {
    final sg1 = double.tryParse(sg1Controller.text);
    final sg2 = double.tryParse(sg2Controller.text);
    final days = date2.difference(date1).inDays;

    if (sg1 == null || sg2 == null || days == 0) {
      setState(() => fsu = null);
      return;
    }

    final result = 100000 * (sg1 - sg2) / days;
    setState(() => fsu = result);
  }

  @override
  void initState() {
    super.initState();
    sg1Controller.addListener(_calculateFSU);
    sg2Controller.addListener(_calculateFSU);
  }

  @override
  void dispose() {
    sg1Controller.dispose();
    sg2Controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("FSU Calculator")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text("Fermentation Speed (FSU)", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),

          const Text("Measurement 1"),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: sg1Controller,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: "SG 1"),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: () => _pickDate(context, true),
                child: Text("${date1.toLocal()}".split(' ')[0]),
              ),
            ],
          ),

          const SizedBox(height: 16),

          const Text("Measurement 2"),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: sg2Controller,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: "SG 2"),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: () => _pickDate(context, false),
                child: Text("${date2.toLocal()}".split(' ')[0]),
              ),
            ],
          ),

          const SizedBox(height: 24),

          if (fsu != null)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _getFSUColor(fsu!),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Fermentation Speed (FSU): ${fsu!.toStringAsFixed(1)}",
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _getFSUMessage(fsu!),
                    style: const TextStyle(fontSize: 14, color: Colors.white70),
                  ),
                ],
              ),
            )
          else
            const Text(
              "Enter valid SGs and dates at least 1 day apart.",
              style: TextStyle(color: Colors.grey),
            ),

          Card(
            color: Colors.blueGrey[50],
            elevation: 2,
            margin: const EdgeInsets.only(top: 24),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: RichText(
                text: const TextSpan(
                  style: TextStyle(color: Colors.black87, fontSize: 14),
                  children: [
                    TextSpan(
                      text: 'Guidelines:\n\n',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    TextSpan(text: '• Primary/Turbulent Fermentation: ', style: TextStyle(fontWeight: FontWeight.w600)),
                    TextSpan(text: '250–350 FSU\n'),
                    TextSpan(text: '• Secondary Fermentation: ', style: TextStyle(fontWeight: FontWeight.w600)),
                    TextSpan(text: '50 FSU or less'),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
