import 'package:flutter/material.dart';
import '../utils/so2_utils.dart';

class StabilizationGuidanceDialog extends StatelessWidget {
  final double volume;
  final bool isGallons;
  final double? ph;

  const StabilizationGuidanceDialog({
    super.key,
    required this.volume,
    required this.isGallons,
    this.ph,
  });

  @override
  Widget build(BuildContext context) {
    final volumeLiters = isGallons ? volume * 3.78541 : volume;
    final displayVolume = volume.toStringAsFixed(2); // always display what user entered
    final unitLabel = isGallons ? 'gal' : 'L';


    final sorbateGrams = (volumeLiters * 0.2).toStringAsFixed(1); // 200 ppm
    final sulfitePPM = ph != null ? So2Utils.getRecommendedFreeSO2(ph!) : 50.0;
    final sulfiteGrams = So2Utils.calculateSulfiteGrams(
      volumeLiters: volumeLiters,
      targetPPM: sulfitePPM,
    ).toStringAsFixed(1);

    final campdenTabs = So2Utils.gramsToCampdenTabs(double.parse(sulfiteGrams)).toStringAsFixed(1);

    return AlertDialog(
      title: const Text("Stabilization Guidance"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("For $displayVolume $unitLabel of finished cider:"),
          const SizedBox(height: 12),
          Text("• Add **$sorbateGrams g** Potassium Sorbate (≈ 200 ppm)", style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (ph != null)
            Text("• Add **$sulfiteGrams g** Potassium Metabisulfite\n"
                "  (~${sulfitePPM.toStringAsFixed(0)} ppm at pH ${ph!.toStringAsFixed(2)} ≈ $campdenTabs Campden tablets)",
                style: const TextStyle(fontWeight: FontWeight.bold))
          else
            const Text("• Add Metabisulfite based on pH — enter pH above for accurate dosing."),
          const SizedBox(height: 12),
          const Text(
            "These additions help prevent refermentation after backsweetening.",
            style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text("Close"),
        ),
      ],
    );
  }
}
