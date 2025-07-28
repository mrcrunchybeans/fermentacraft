import 'package:flutter_application_1/models/batch_model.dart';

double estimateMustPH(BatchModel batch) {
  final withPH = batch.safeIngredients.where((f) => f['ph'] != null).toList();
  if (withPH.isEmpty) return 3.4;

  final phValues = withPH.map((f) => double.tryParse(f['ph'].toString()) ?? 3.4);
  final avgPH = phValues.reduce((a, b) => a + b) / phValues.length;
  return avgPH;
}
