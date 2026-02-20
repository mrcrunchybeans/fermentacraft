// test/widgets/fermentation_chart_improved_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fermentacraft/widgets/fermentation_chart_improved.dart';
import 'package:fermentacraft/models/measurement.dart';

void main() {
  group('ImprovedFermentationChartPanel', () {
    testWidgets('displays empty state when no measurements', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ImprovedFermentationChartPanel(
              measurements: [],
              useFahrenheit: false,
              sincePitchingAt: null,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Should show empty state message
      expect(find.text('No measurements yet'), findsOneWidget);
    });

    testWidgets('displays chart with recent measurements', (tester) async {
      final now = DateTime.now();
      final measurements = [
        Measurement(
          id: 'm-1',
          timestamp: now.subtract(const Duration(hours: 12)),
          gravity: 1.050,
          temperature: 20.0,
        ),
        Measurement(
          id: 'm-2',
          timestamp: now.subtract(const Duration(hours: 6)),
          gravity: 1.045,
          temperature: 20.5,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ImprovedFermentationChartPanel(
              measurements: measurements,
              useFahrenheit: false,
              sincePitchingAt: now.subtract(const Duration(days: 1)),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Should not show empty state
      expect(find.text('No measurements yet'), findsNothing);
      
      // Chart should be present
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('shows info button', (tester) async {
      final now = DateTime.now();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ImprovedFermentationChartPanel(
              measurements: [
                Measurement(
                  id: 'm-1',
                  timestamp: now,
                  gravity: 1.050,
                ),
              ],
              useFahrenheit: false,
              sincePitchingAt: null,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Should have info icon button
      expect(find.byIcon(Icons.info_outline), findsOneWidget);
    });

    testWidgets('handles dense data without crashing', (tester) async {
      final now = DateTime.now();
      // Create many measurements (simulating iSpindle data)
      final measurements = List.generate(
        200,
        (i) => Measurement(
          id: 'm-$i',
          timestamp: now.subtract(Duration(minutes: i * 15)),
          gravity: 1.050 - (i * 0.0001),
          temperature: 20.0 + (i % 3) * 0.5,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ImprovedFermentationChartPanel(
              measurements: measurements,
              useFahrenheit: false,
              sincePitchingAt: now.subtract(const Duration(days: 7)),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Chart should render without errors
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('handles measurements with missing temperature', (tester) async {
      final now = DateTime.now();
      final measurements = [
        Measurement(
          id: 'm-1',
          timestamp: now.subtract(const Duration(hours: 12)),
          gravity: 1.050,
          // temperature is null
        ),
        Measurement(
          id: 'm-2',
          timestamp: now.subtract(const Duration(hours: 6)),
          gravity: 1.045,
          temperature: 20.0,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ImprovedFermentationChartPanel(
              measurements: measurements,
              useFahrenheit: false,
              sincePitchingAt: now.subtract(const Duration(days: 1)),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Chart should render without errors
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('handles single measurement', (tester) async {
      final now = DateTime.now();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ImprovedFermentationChartPanel(
              measurements: [
                Measurement(
                  id: 'm-1',
                  timestamp: now,
                  gravity: 1.050,
                  temperature: 20.0,
                ),
              ],
              useFahrenheit: false,
              sincePitchingAt: now,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Should render without errors
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('renders with Fahrenheit mode', (tester) async {
      final now = DateTime.now();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ImprovedFermentationChartPanel(
              measurements: [
                Measurement(
                  id: 'm-1',
                  timestamp: now,
                  gravity: 1.050,
                  temperature: 20.0, // Stored in Celsius
                ),
              ],
              useFahrenheit: true, // Display in Fahrenheit
              sincePitchingAt: null,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Chart should render (conversion happens internally)
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('handles measurements spanning multiple days', (tester) async {
      final now = DateTime.now();
      final measurements = List.generate(
        10,
        (i) => Measurement(
          id: 'm-$i',
          timestamp: now.subtract(Duration(days: i)),
          gravity: 1.050 - (i * 0.003),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ImprovedFermentationChartPanel(
              measurements: measurements,
              useFahrenheit: false,
              sincePitchingAt: now.subtract(const Duration(days: 10)),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Chart should render
      expect(find.byType(CustomPaint), findsWidgets);
    });
  });
}
