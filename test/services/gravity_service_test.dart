// test/services/gravity_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fermentacraft/services/gravity_service.dart';

void main() {
  group('GravityService', () {
    group('abv', () {
      test('calculates ABV correctly for typical beer', () {
        // OG 1.050, FG 1.010 → ~5.25% ABV
        expect(
          GravityService.abv(og: 1.050, fg: 1.010),
          closeTo(5.25, 0.01),
        );
      });

      test('calculates ABV correctly for high-gravity beer', () {
        // OG 1.080, FG 1.015 → ~8.53% ABV
        expect(
          GravityService.abv(og: 1.080, fg: 1.015),
          closeTo(8.53, 0.01),
        );
      });

      test('calculates ABV correctly for session beer', () {
        // OG 1.035, FG 1.008 → ~3.54% ABV
        expect(
          GravityService.abv(og: 1.035, fg: 1.008),
          closeTo(3.54, 0.01),
        );
      });

      test('handles edge case: no fermentation', () {
        // Same OG and FG → 0% ABV
        expect(GravityService.abv(og: 1.050, fg: 1.050), 0.0);
      });

      test('handles edge case: complete fermentation', () {
        // OG 1.050, FG 1.000 → ~6.56% ABV
        expect(
          GravityService.abv(og: 1.050, fg: 1.000),
          closeTo(6.56, 0.01),
        );
      });

      test('returns 0 when FG > OG (invalid scenario)', () {
        // This shouldn't happen in practice, but ensures no negative ABV
        expect(GravityService.abv(og: 1.010, fg: 1.050), 0.0);
      });

      test('handles very low gravity values', () {
        expect(
          GravityService.abv(og: 1.002, fg: 1.000),
          closeTo(0.26, 0.01),
        );
      });

      test('handles very high gravity values (barleywine)', () {
        // OG 1.120, FG 1.025 → ~12.47% ABV
        expect(
          GravityService.abv(og: 1.120, fg: 1.025),
          closeTo(12.47, 0.01),
        );
      });
    });

    group('estimate', () {
      test('calculates OG correctly for simple sugar solution', () {
        final items = [
          // 1 gallon of water
          const FermentableItem(
            isLiquid: true,
            volumeGal: 1.0,
            sg: 1.000,
          ),
          // 1 lb of sugar (46 ppg)
          const FermentableItem(
            isLiquid: false,
            weightLb: 1.0,
            ppg: 46.0,
          ),
        ];

        final result = GravityService.estimate(items);
        
        // 46 points in 1 gallon → 1.046
        expect(result.og, closeTo(1.046, 0.001));
        expect(result.totalVolumeGal, closeTo(1.0, 0.01));
      });

      test('calculates OG correctly for honey must', () {
        final items = [
          // 1 gallon of water
          const FermentableItem(
            isLiquid: true,
            volumeGal: 1.0,
            sg: 1.000,
          ),
          // 3 lbs of honey (35 ppg default, 0.084 gal/lb volume)
          const FermentableItem(
            isLiquid: false,
            weightLb: 3.0,
            kind: 'honey',
          ),
        ];

        final result = GravityService.estimate(items);
        
        // 3 lbs * 35 ppg = 105 points
        // Volume = 1.0 + (3 * 0.084) = ~1.252 gal
        // OG = 1.0 + (105 / 1.252) / 1000 ≈ 1.084
        expect(result.og, closeTo(1.084, 0.003));
        expect(result.totalVolumeGal, closeTo(1.252, 0.01));
      });

      test('calculates OG correctly for fruit wine', () {
        final items = [
          // 1 gallon of water
          const FermentableItem(
            isLiquid: true,
            volumeGal: 1.0,
            sg: 1.000,
          ),
          // 2 lbs of fruit with 12% Brix
          const FermentableItem(
            isLiquid: false,
            weightLb: 2.0,
            fruitBrix: 12.0,
            kind: 'fruit',
          ),
        ];

        final result = GravityService.estimate(items);
        
        // 2 lbs * 0.12 = 0.24 lbs sugar → 0.24 * 46 = 11.04 points
        // Volume = 1.0 + (2 * 0.11) = 1.22 gal
        // OG = 1.0 + (11.04 / 1.22) / 1000 ≈ 1.009
        expect(result.og, closeTo(1.009, 0.002));
        expect(result.totalVolumeGal, closeTo(1.22, 0.01));
      });

      test('handles empty fermentables list', () {
        final result = GravityService.estimate([]);
        
        expect(result.og, 1.000);
        expect(result.totalVolumeGal, 0.0);
      });

      test('handles multiple liquids with different gravities', () {
        final items = [
          // 1 gallon of water
          const FermentableItem(
            isLiquid: true,
            volumeGal: 1.0,
            sg: 1.000,
          ),
          // 0.5 gallons of apple juice (SG 1.050)
          const FermentableItem(
            isLiquid: true,
            volumeGal: 0.5,
            sg: 1.050,
          ),
        ];

        final result = GravityService.estimate(items);
        
        // Points: (1.000-1)*1000*1 + (1.050-1)*1000*0.5 = 0 + 25 = 25
        // Volume: 1.5 gal
        // OG = 1.0 + (25 / 1.5) / 1000 ≈ 1.017
        expect(result.og, closeTo(1.017, 0.001));
        expect(result.totalVolumeGal, 1.5);
      });

      test('handles fruit with explicit juice SG', () {
        final items = [
          // 1 gallon of water
          const FermentableItem(
            isLiquid: true,
            volumeGal: 1.0,
            sg: 1.000,
          ),
          // 3 lbs of fruit with juice SG 1.040
          const FermentableItem(
            isLiquid: false,
            weightLb: 3.0,
            fruitJuiceSg: 1.040,
            kind: 'fruit',
          ),
        ];

        final result = GravityService.estimate(items);
        
        // Fruit volume: 3 * 0.11 = 0.33 gal
        // Points: 0 + (1.040-1)*1000*0.33 = 13.2
        // Total volume: 1.0 + 0.33 = 1.33 gal
        // OG = 1.0 + (13.2 / 1.33) / 1000 ≈ 1.010
        expect(result.og, closeTo(1.010, 0.002));
        expect(result.totalVolumeGal, closeTo(1.33, 0.01));
      });

      test('handles explicit PPG override', () {
        final items = [
          // 1 gallon of water
          const FermentableItem(
            isLiquid: true,
            volumeGal: 1.0,
            sg: 1.000,
          ),
          // 2 lbs with custom 40 ppg
          const FermentableItem(
            isLiquid: false,
            weightLb: 2.0,
            ppg: 40.0,
          ),
        ];

        final result = GravityService.estimate(items);
        
        // 2 * 40 = 80 points in 1 gallon → 1.080
        expect(result.og, closeTo(1.080, 0.001));
      });
    });

    group('pointsFromSgAndVolume', () {
      test('calculates gravity points correctly', () {
        // 1.050 SG in 2 gallons = 50 points * 2 = 100 points
        expect(
          GravityService.pointsFromSgAndVolume(1.050, 2.0),
          closeTo(100.0, 0.1),
        );
      });

      test('returns 0 for water (SG 1.000)', () {
        expect(
          GravityService.pointsFromSgAndVolume(1.000, 5.0),
          0.0,
        );
      });

      test('handles negative volume as 0', () {
        expect(
          GravityService.pointsFromSgAndVolume(1.050, -1.0),
          0.0,
        );
      });

      test('handles zero volume', () {
        expect(
          GravityService.pointsFromSgAndVolume(1.050, 0.0),
          0.0,
        );
      });
    });

    group('ogFromPointsAndVolume', () {
      test('calculates OG correctly from points', () {
        // 50 points in 1 gallon → 1.050
        expect(
          GravityService.ogFromPointsAndVolume(50.0, 1.0),
          closeTo(1.050, 0.001),
        );
      });

      test('handles zero points', () {
        expect(
          GravityService.ogFromPointsAndVolume(0.0, 1.0),
          1.000,
        );
      });

      test('handles zero volume', () {
        expect(
          GravityService.ogFromPointsAndVolume(100.0, 0.0),
          1.000,
        );
      });

      test('handles negative volume as zero', () {
        expect(
          GravityService.ogFromPointsAndVolume(100.0, -5.0),
          1.000,
        );
      });

      test('calculates high-gravity correctly', () {
        // 120 points in 1 gallon → 1.120
        expect(
          GravityService.ogFromPointsAndVolume(120.0, 1.0),
          closeTo(1.120, 0.001),
        );
      });
    });

    group('FermentableItem', () {
      test('liquid item contributes volume correctly', () {
        const item = FermentableItem(
          isLiquid: true,
          volumeGal: 2.5,
          sg: 1.000,
        );

        expect(item.volumeContributionGal, 2.5);
      });

      test('honey item uses default volume calculation', () {
        const item = FermentableItem(
          isLiquid: false,
          weightLb: 3.0,
          kind: 'honey',
        );

        // 3 lbs * (1/11.9) ≈ 0.252 gal
        expect(item.defaultVolumeFromWeightGal, closeTo(0.252, 0.01));
      });

      test('fruit item uses default volume calculation', () {
        const item = FermentableItem(
          isLiquid: false,
          weightLb: 2.0,
          kind: 'fruit',
        );

        // 2 lbs * 0.11 = 0.22 gal
        expect(item.defaultVolumeFromWeightGal, closeTo(0.22, 0.01));
      });

      test('explicit volume override works', () {
        const item = FermentableItem(
          isLiquid: false,
          weightLb: 2.0,
          kind: 'honey',
          volumeFromWeightGal: 0.5,
        );

        expect(item.defaultVolumeFromWeightGal, 0.5);
      });

      test('dry sugar has negligible volume', () {
        const item = FermentableItem(
          isLiquid: false,
          weightLb: 5.0,
          ppg: 46.0,
        );

        expect(item.defaultVolumeFromWeightGal, 0.0);
      });

      test('calculates gravity points for weighted honey', () {
        const item = FermentableItem(
          isLiquid: false,
          weightLb: 3.0,
          kind: 'honey',
        );

        // 3 lbs * 35 ppg = 105 points
        expect(item.gravityPoints, closeTo(105.0, 0.1));
      });

      test('calculates gravity points for fruit with Brix', () {
        const item = FermentableItem(
          isLiquid: false,
          weightLb: 2.0,
          fruitBrix: 12.0,
        );

        // 2 lbs * 0.12 = 0.24 lbs sugar → 0.24 * 46 = 11.04 points
        expect(item.gravityPoints, closeTo(11.04, 0.1));
      });
    });
  });
}
