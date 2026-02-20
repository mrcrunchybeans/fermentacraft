// test/utils/temperature_utils_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fermentacraft/utils/temp_display.dart';

void main() {
  group('TempConversion', () {
    group('toC', () {
      test('converts Fahrenheit to Celsius correctly', () {
        expect(TempConversion.toC(32, 'F'), closeTo(0.0, 0.01));
        expect(TempConversion.toC(212, 'F'), closeTo(100.0, 0.01));
        expect(TempConversion.toC(68, 'F'), closeTo(20.0, 0.1));
        expect(TempConversion.toC(98.6, 'F'), closeTo(37.0, 0.1));
      });

      test('returns input if already Celsius', () {
        expect(TempConversion.toC(20, 'C'), 20.0);
        expect(TempConversion.toC(0, 'C'), 0.0);
        expect(TempConversion.toC(100, 'C'), 100.0);
      });

      test('returns input if unit is null', () {
        expect(TempConversion.toC(20, null), 20.0);
        expect(TempConversion.toC(25.5, null), 25.5);
      });

      test('is case-insensitive for Fahrenheit', () {
        expect(TempConversion.toC(32, 'f'), closeTo(0.0, 0.01));
        expect(TempConversion.toC(32, 'F'), closeTo(0.0, 0.01));
        expect(TempConversion.toC(32, '°F'), closeTo(0.0, 0.01));
      });

      test('handles negative temperatures', () {
        expect(TempConversion.toC(-40, 'F'), closeTo(-40.0, 0.01));
        expect(TempConversion.toC(-10, 'C'), -10.0);
      });

      test('handles fractional temperatures', () {
        expect(TempConversion.toC(72.5, 'F'), closeTo(22.5, 0.1));
        expect(TempConversion.toC(15.7, 'C'), 15.7);
      });
    });

    group('toF', () {
      test('converts Celsius to Fahrenheit correctly', () {
        expect(TempConversion.toF(0), closeTo(32.0, 0.01));
        expect(TempConversion.toF(100), closeTo(212.0, 0.01));
        expect(TempConversion.toF(20), closeTo(68.0, 0.1));
        expect(TempConversion.toF(37), closeTo(98.6, 0.1));
      });

      test('handles negative Celsius', () {
        expect(TempConversion.toF(-40), closeTo(-40.0, 0.01));
        expect(TempConversion.toF(-10), closeTo(14.0, 0.1));
      });

      test('handles fractional Celsius', () {
        expect(TempConversion.toF(22.5), closeTo(72.5, 0.1));
        expect(TempConversion.toF(15.5), closeTo(59.9, 0.1));
      });
    });

    group('parse', () {
      test('parses Fahrenheit values', () {
        expect(TempConversion.parse(68, 'F'), closeTo(20.0, 0.1));
        expect(TempConversion.parse(32, 'F'), closeTo(0.0, 0.01));
      });

      test('parses Celsius values', () {
        expect(TempConversion.parse(20, 'C'), 20.0);
        expect(TempConversion.parse(25.5, null), 25.5);
      });

      test('handles num (int and double)', () {
        expect(TempConversion.parse(68, 'F'), closeTo(20.0, 0.1));
        expect(TempConversion.parse(68.5, 'F'), closeTo(20.3, 0.1));
      });
    });

    group('isValidBrewingTemp', () {
      test('returns true for typical brewing temperatures', () {
        expect(TempConversion.isValidBrewingTemp(20), true); // Room temp
        expect(TempConversion.isValidBrewingTemp(65), true); // Mash temp
        expect(TempConversion.isValidBrewingTemp(100), true); // Boiling
        expect(TempConversion.isValidBrewingTemp(0), true); // Cold crash
      });

      test('returns false for unrealistic temperatures', () {
        expect(TempConversion.isValidBrewingTemp(-10), false); // Too cold
        expect(TempConversion.isValidBrewingTemp(110), false); // Too hot
      });

      test('handles boundary conditions', () {
        expect(TempConversion.isValidBrewingTemp(-5), true); // Minimum
        expect(TempConversion.isValidBrewingTemp(-5.1), false); // Just below
        expect(TempConversion.isValidBrewingTemp(100.1), false); // Just above
      });
    });

    group('isValidFermentationTemp', () {
      test('returns true for typical fermentation temperatures', () {
        expect(TempConversion.isValidFermentationTemp(18), true); // Ale
        expect(TempConversion.isValidFermentationTemp(10), true); // Lager
        expect(TempConversion.isValidFermentationTemp(25), true); // Warm ferment
        expect(TempConversion.isValidFermentationTemp(0), true); // Cold crash
      });

      test('returns false for unrealistic fermentation temperatures', () {
        expect(TempConversion.isValidFermentationTemp(-1), false); // Too cold
        expect(TempConversion.isValidFermentationTemp(45), false); // Too hot
      });

      test('handles boundary conditions', () {
        expect(TempConversion.isValidFermentationTemp(40), true); // Maximum
        expect(TempConversion.isValidFermentationTemp(40.1), false); // Just above
      });
    });

    group('calibrationTemp constants', () {
      test('calibration temperatures are correct', () {
        expect(TempConversion.calibrationTempC, 20.0);
        expect(TempConversion.calibrationTempF, 68.0);
      });

      test('calibration temperatures are equivalent', () {
        expect(
          TempConversion.toF(TempConversion.calibrationTempC),
          closeTo(TempConversion.calibrationTempF, 0.1),
        );
      });
    });
  });

  group('TemperatureUtils extension', () {
    group('asFahrenheit', () {
      test('converts Celsius to Fahrenheit', () {
        expect(0.0.asFahrenheit, closeTo(32.0, 0.01));
        expect(100.0.asFahrenheit, closeTo(212.0, 0.01));
        expect(20.0.asFahrenheit, closeTo(68.0, 0.1));
      });

      test('handles negative values', () {
        expect((-40.0).asFahrenheit, closeTo(-40.0, 0.01));
        expect((-10.0).asFahrenheit, closeTo(14.0, 0.1));
      });
    });

    group('asCelsius', () {
      test('converts Fahrenheit to Celsius', () {
        expect(32.0.asCelsius, closeTo(0.0, 0.01));
        expect(212.0.asCelsius, closeTo(100.0, 0.01));
        expect(68.0.asCelsius, closeTo(20.0, 0.1));
      });

      test('handles negative values', () {
        expect((-40.0).asCelsius, closeTo(-40.0, 0.01));
        expect(14.0.asCelsius, closeTo(-10.0, 0.1));
      });
    });

    group('toDisplay', () {
      test('formats Fahrenheit correctly', () {
        expect(20.0.toDisplay(targetUnit: 'F'), '68.0°F');
        expect(20.0.toDisplay(targetUnit: 'f'), '68.0°F');
        expect(20.0.toDisplay(targetUnit: '°F'), '68.0°F');
      });

      test('formats Celsius correctly', () {
        expect(20.0.toDisplay(targetUnit: 'C'), '20.0°C');
        expect(20.0.toDisplay(targetUnit: 'c'), '20.0°C');
      });

      test('defaults to Celsius for unknown units', () {
        expect(20.0.toDisplay(targetUnit: 'K'), '20.0°C');
        expect(20.0.toDisplay(targetUnit: 'unknown'), '20.0°C');
        expect(20.0.toDisplay(targetUnit: ''), '20.0°C');
      });

      test('formats with one decimal place', () {
        expect(20.55.toDisplay(targetUnit: 'C'), '20.6°C');
        expect(20.44.toDisplay(targetUnit: 'C'), '20.4°C');
        expect(20.0.toDisplay(targetUnit: 'F'), '68.0°F');
      });

      test('handles negative temperatures', () {
        expect((-10.0).toDisplay(targetUnit: 'C'), '-10.0°C');
        expect((-10.0).toDisplay(targetUnit: 'F'), '14.0°F');
      });

      test('handles zero', () {
        expect(0.0.toDisplay(targetUnit: 'C'), '0.0°C');
        expect(0.0.toDisplay(targetUnit: 'F'), '32.0°F');
      });
    });

    group('round-trip conversion', () {
      test('C -> F -> C preserves value', () {
        const original = 20.0;
        final converted = original.asFahrenheit.asCelsius;
        expect(converted, closeTo(original, 0.001));
      });

      test('F -> C -> F preserves value', () {
        const original = 68.0;
        final converted = original.asCelsius.asFahrenheit;
        expect(converted, closeTo(original, 0.001));
      });
    });
  });

  group('Integration tests', () {
    test('typical fermentation workflow', () {
      // User enters 68°F, we store as Celsius
      const userInputF = 68.0;
      final storedC = TempConversion.toC(userInputF, 'F');
      
      expect(storedC, closeTo(20.0, 0.1));
      
      // Later, display back as Fahrenheit
      final displayedF = storedC.toDisplay(targetUnit: 'F');
      expect(displayedF, '68.0°F');
    });

    test('validate temperature before storing', () {
      final tempC = TempConversion.toC(72, 'F'); // ~22°C
      
      expect(TempConversion.isValidBrewingTemp(tempC), true);
      expect(TempConversion.isValidFermentationTemp(tempC), true);
    });

    test('handle edge case: very high temperature', () {
      final tempC = TempConversion.toC(200, 'F'); // ~93°C
      
      expect(TempConversion.isValidBrewingTemp(tempC), true);
      expect(TempConversion.isValidFermentationTemp(tempC), false);
    });
  });
}
