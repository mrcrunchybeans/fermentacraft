// test/models/batch_model_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fermentacraft/models/batch_model.dart';
import 'package:fermentacraft/models/fermentation_stage.dart';
import 'package:fermentacraft/models/measurement.dart';
import 'package:fermentacraft/models/planned_event.dart';
import 'package:fermentacraft/models/tag.dart';

// Note: BatchModel extends HiveObject, but tests don't require Hive initialization
// as we're only testing the model logic, not database operations.

void main() {
  group('BatchModel', () {
    late BatchModel testBatch;

    setUp(() {
      testBatch = BatchModel(
        id: 'test-1',
        name: 'Test Batch',
        recipeId: 'recipe-1',
        startDate: DateTime(2024, 1, 1),
        createdAt: DateTime(2024, 1, 1, 10, 0),
      );
    });

    group('constructor', () {
      test('creates batch with required fields', () {
        expect(testBatch.id, 'test-1');
        expect(testBatch.name, 'Test Batch');
        expect(testBatch.recipeId, 'recipe-1');
        expect(testBatch.status, 'Planning');
      });

      test('initializes empty lists correctly', () {
        expect(testBatch.measurements, isEmpty);
        expect(testBatch.ingredients, isEmpty);
        expect(testBatch.additives, isEmpty);
        expect(testBatch.fermentationStages, isEmpty);
        expect(testBatch.measurementLogs, isEmpty);
      });

      test('initializes deductedIngredients as empty map', () {
        expect(testBatch.deductedIngredients, isEmpty);
      });

      test('sets isArchived to false by default', () {
        expect(testBatch.isArchived, false);
      });
    });

    group('categoryLabel', () {
      test('returns explicit category when set', () {
        final batch = testBatch.copyWith(category: 'Mead');
        expect(batch.categoryLabel, 'Mead');
      });

      test('falls back to first legacy tag', () {
        final batch = BatchModel(
          id: 'test-2',
          name: 'Tagged Batch',
          recipeId: 'recipe-1',
          startDate: DateTime(2024, 1, 1),
          createdAt: DateTime(2024, 1, 1),
          tagsLegacy: [Tag(name: 'Cider')],
        );
        expect(batch.categoryLabel, 'Cider');
      });

      test('returns "Uncategorized" when no category or tags', () {
        expect(testBatch.categoryLabel, 'Uncategorized');
      });

      test('prefers category over tags', () {
        final batch = BatchModel(
          id: 'test-3',
          name: 'Both',
          recipeId: 'recipe-1',
          startDate: DateTime(2024, 1, 1),
          createdAt: DateTime(2024, 1, 1),
          category: 'Mead',
          tagsLegacy: [Tag(name: 'Cider')],
        );
        expect(batch.categoryLabel, 'Mead');
      });

      test('ignores whitespace-only category', () {
        final batch = testBatch.copyWith(category: '   ');
        expect(batch.categoryLabel, 'Uncategorized');
      });
    });

    group('safe accessor methods', () {
      test('safeFermentationStages filters out nulls', () {
        final batch = BatchModel(
          id: 'test-4',
          name: 'Test',
          recipeId: 'recipe-1',
          startDate: DateTime(2024, 1, 1),
          createdAt: DateTime(2024, 1, 1),
          fermentationStages: [
            FermentationStage(
              name: 'Primary',
              durationDays: 7,
            ),
          ],
        );
        expect(batch.safeFermentationStages, hasLength(1));
        expect(batch.safeFermentationStages.first.name, 'Primary');
      });

      test('safeMeasurements filters out nulls', () {
        final batch = BatchModel(
          id: 'test-5',
          name: 'Test',
          recipeId: 'recipe-1',
          startDate: DateTime(2024, 1, 1),
          createdAt: DateTime(2024, 1, 1),
          measurements: [
            Measurement(
              id: 'm-1',
              timestamp: DateTime(2024, 1, 2),
              gravity: 1.050,
            ),
          ],
        );
        expect(batch.safeMeasurements, hasLength(1));
        expect(batch.safeMeasurements.first.gravity, 1.050);
      });

      test('safePlannedEvents returns empty list when null', () {
        expect(testBatch.safePlannedEvents, isEmpty);
      });

      test('safePlannedEvents filters out nulls', () {
        final batch = BatchModel(
          id: 'test-6',
          name: 'Test',
          recipeId: 'recipe-1',
          startDate: DateTime(2024, 1, 1),
          createdAt: DateTime(2024, 1, 1),
          plannedEvents: [
            PlannedEvent(
              title: 'Dry Hop',
              date: DateTime(2024, 1, 8),
            ),
          ],
        );
        expect(batch.safePlannedEvents, hasLength(1));
        expect(batch.safePlannedEvents.first.title, 'Dry Hop');
      });

      test('safeIngredients normalizes maps', () {
        final batch = BatchModel(
          id: 'test-7',
          name: 'Test',
          recipeId: 'recipe-1',
          startDate: DateTime(2024, 1, 1),
          createdAt: DateTime(2024, 1, 1),
          ingredients: [
            {'name': 'Honey', 'amount': 3.0},
          ],
        );
        expect(batch.safeIngredients, hasLength(1));
        expect(batch.safeIngredients.first['name'], 'Honey');
      });

      test('safePackagingBreakdown returns empty list when null', () {
        expect(testBatch.safePackagingBreakdown, isEmpty);
      });

      test('safePackagingBreakdown normalizes maps', () {
        final batch = BatchModel(
          id: 'test-8',
          name: 'Test',
          recipeId: 'recipe-1',
          startDate: DateTime(2024, 1, 1),
          createdAt: DateTime(2024, 1, 1),
          packagingBreakdown: [
            {'method': 'Bottled', 'quantity': 5.0, 'unit': 'gallons'},
          ],
        );
        expect(batch.safePackagingBreakdown, hasLength(1));
        expect(batch.safePackagingBreakdown.first['method'], 'Bottled');
      });
    });

    group('normalizeInPlace', () {
      test('converts numeric types to double', () {
        final batch = BatchModel(
          id: 'test-9',
          name: 'Test',
          recipeId: 'recipe-1',
          startDate: DateTime(2024, 1, 1),
          createdAt: DateTime(2024, 1, 1),
          og: 1.050,
          fg: 1.010,
          abv: 5.25,
          plannedOg: 1.052,
        );

        batch.normalizeInPlace();

        expect(batch.og, isA<double>());
        expect(batch.fg, isA<double>());
        expect(batch.abv, isA<double>());
        expect(batch.plannedOg, isA<double>());
      });

      test('preserves existing data', () {
        final batch = BatchModel(
          id: 'test-10',
          name: 'Test',
          recipeId: 'recipe-1',
          startDate: DateTime(2024, 1, 1),
          createdAt: DateTime(2024, 1, 1),
          og: 1.050,
          ingredients: [{'name': 'Honey'}],
        );

        batch.normalizeInPlace();

        expect(batch.og, 1.050);
        expect(batch.safeIngredients.first['name'], 'Honey');
      });
    });

    group('copyWith', () {
      test('creates new instance with updated fields', () {
        final updated = testBatch.copyWith(
          name: 'Updated Batch',
          status: 'Fermenting',
        );

        expect(updated.name, 'Updated Batch');
        expect(updated.status, 'Fermenting');
        expect(updated.id, testBatch.id); // unchanged
      });

      test('preserves original instance', () {
        final original = testBatch.name;
        testBatch.copyWith(name: 'New Name');
        expect(testBatch.name, original);
      });

      test('handles null values correctly', () {
        final batch = testBatch.copyWith(
          batchVolume: 5.0,
          og: 1.050,
        );

        final updated = batch.copyWith();

        expect(updated.batchVolume, 5.0);
        expect(updated.og, 1.050);
      });

      test('can update measurements list', () {
        final updated = testBatch.copyWith(
          measurements: [
            Measurement(
              id: 'm-1',
              timestamp: DateTime(2024, 1, 2),
              gravity: 1.050,
            ),
          ],
        );

        expect(updated.measurements, hasLength(1));
        expect(testBatch.measurements, isEmpty);
      });

      test('can update isArchived flag', () {
        final updated = testBatch.copyWith(isArchived: true);
        expect(updated.isArchived, true);
        expect(testBatch.isArchived, false);
      });
    });

    group('toJson/fromJson', () {
      test('round-trip preserves basic fields', () {
        final batch = BatchModel(
          id: 'json-test',
          name: 'JSON Batch',
          recipeId: 'recipe-1',
          startDate: DateTime(2024, 1, 1),
          createdAt: DateTime(2024, 1, 1, 10, 0),
          status: 'Fermenting',
          batchVolume: 5.0,
          og: 1.050,
          fg: 1.010,
          category: 'Mead',
        );

        final json = batch.toJson();
        final restored = BatchModel.fromJson(json);

        expect(restored.id, batch.id);
        expect(restored.name, batch.name);
        expect(restored.recipeId, batch.recipeId);
        expect(restored.status, batch.status);
        expect(restored.batchVolume, batch.batchVolume);
        expect(restored.og, batch.og);
        expect(restored.fg, batch.fg);
        expect(restored.category, batch.category);
      });

      test('round-trip preserves dates', () {
        final batch = BatchModel(
          id: 'date-test',
          name: 'Date Batch',
          recipeId: 'recipe-1',
          startDate: DateTime(2024, 1, 1),
          createdAt: DateTime(2024, 1, 1, 10, 0),
          bottleDate: DateTime(2024, 2, 1),
          fsuDate: DateTime(2024, 1, 15),
        );

        final json = batch.toJson();
        final restored = BatchModel.fromJson(json);

        expect(restored.startDate, batch.startDate);
        expect(restored.bottleDate, batch.bottleDate);
        expect(restored.fsuDate, batch.fsuDate);
      });

      test('round-trip preserves measurements', () {
        final batch = BatchModel(
          id: 'meas-test',
          name: 'Measurement Batch',
          recipeId: 'recipe-1',
          startDate: DateTime(2024, 1, 1),
          createdAt: DateTime(2024, 1, 1),
          measurements: [
            Measurement(
              id: 'm-1',
              timestamp: DateTime(2024, 1, 2),
              gravity: 1.050,
              temperature: 20.0,
            ),
          ],
        );

        final json = batch.toJson();
        final restored = BatchModel.fromJson(json);

        expect(restored.measurements, hasLength(1));
        expect(restored.measurements.first.gravity, 1.050);
        expect(restored.measurements.first.temperature, 20.0);
      });

      test('fromJson handles missing optional fields', () {
        final json = {
          'id': 'minimal',
          'name': 'Minimal Batch',
          'recipeId': 'recipe-1',
          'startDate': '2024-01-01T00:00:00.000',
          'createdAt': '2024-01-01T10:00:00.000',
        };

        final batch = BatchModel.fromJson(json);

        expect(batch.id, 'minimal');
        expect(batch.name, 'Minimal Batch');
        expect(batch.status, 'Planning'); // default
        expect(batch.measurements, isEmpty);
        expect(batch.ingredients, isEmpty);
      });

      test('fromJson provides defaults for malformed data', () {
        final json = {
          'name': 'Bad Data',
          // missing id, recipeId, dates
        };

        final batch = BatchModel.fromJson(json);

        expect(batch.id, ''); // empty string default
        expect(batch.name, 'Bad Data');
        expect(batch.recipeId, ''); // empty string default
        expect(batch.startDate, isA<DateTime>()); // falls back to now
        expect(batch.createdAt, isA<DateTime>());
      });

      test('fromJson handles legacy tags', () {
        final json = {
          'id': 'tag-test',
          'name': 'Tagged Batch',
          'recipeId': 'recipe-1',
          'startDate': '2024-01-01T00:00:00.000',
          'createdAt': '2024-01-01T00:00:00.000',
          'tags': [
            {'name': 'Mead'},
          ],
        };

        final batch = BatchModel.fromJson(json);

        expect(batch.tags, hasLength(1));
        expect(batch.tags.first.name, 'Mead');
      });
    });

    group('packagingBreakdown', () {
      test('can store multiple packaging methods', () {
        final batch = testBatch.copyWith(
          packagingBreakdown: [
            {'method': 'Bottled', 'quantity': 3.0, 'unit': 'gallons'},
            {'method': 'Kegged', 'quantity': 2.0, 'unit': 'gallons'},
          ],
        );

        expect(batch.safePackagingBreakdown, hasLength(2));
        expect(batch.safePackagingBreakdown[0]['method'], 'Bottled');
        expect(batch.safePackagingBreakdown[1]['method'], 'Kegged');
      });

      test('preserves packaging breakdown through JSON', () {
        final batch = testBatch.copyWith(
          packagingBreakdown: [
            {'method': 'Bottled', 'quantity': 5.0, 'unit': 'liters'},
          ],
        );

        final json = batch.toJson();
        final restored = BatchModel.fromJson(json);

        expect(restored.safePackagingBreakdown, hasLength(1));
        expect(restored.safePackagingBreakdown.first['method'], 'Bottled');
        expect(restored.safePackagingBreakdown.first['quantity'], 5.0);
      });
    });

    group('deductedIngredients', () {
      test('tracks ingredient deductions', () {
        final batch = testBatch.copyWith(
          deductedIngredients: {
            'honey-1': true,
            'yeast-2': false,
          },
        );

        expect(batch.deductedIngredients['honey-1'], true);
        expect(batch.deductedIngredients['yeast-2'], false);
      });

      test('preserves deductions through JSON', () {
        final batch = testBatch.copyWith(
          deductedIngredients: {'honey-1': true},
        );

        final json = batch.toJson();
        final restored = BatchModel.fromJson(json);

        expect(restored.deductedIngredients['honey-1'], true);
      });
    });

    group('legacy tag compatibility', () {
      test('tags getter returns tagsLegacy', () {
        final batch = BatchModel(
          id: 'compat-test',
          name: 'Compat Batch',
          recipeId: 'recipe-1',
          startDate: DateTime(2024, 1, 1),
          createdAt: DateTime(2024, 1, 1),
          tagsLegacy: [Tag(name: 'Mead')],
        );

        expect(batch.tags, hasLength(1));
        expect(batch.tags.first.name, 'Mead');
      });

      test('tags setter updates tagsLegacy', () {
        final batch = testBatch;
        batch.tags = [Tag(name: 'Cider')];

        expect(batch.tagsLegacy, hasLength(1));
        expect(batch.tagsLegacy!.first.name, 'Cider');
      });
    });
  });
}
