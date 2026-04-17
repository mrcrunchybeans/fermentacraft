import 'dart:async';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:fermentacraft/models/batch_model.dart';
import 'package:fermentacraft/models/measurement.dart';
import 'package:fermentacraft/models/fermentation_stage.dart';
import 'package:fermentacraft/repositories/repositories.dart';
import 'package:fermentacraft/utils/result.dart';
import 'package:fermentacraft/utils/app_logger.dart';

/// Chart time range options
enum ChartRange {
  d1(Duration(days: 1), 'Last 24 Hours'),
  d3(Duration(days: 3), 'Last 3 Days'),
  d7(Duration(days: 7), 'Last Week'),
  d30(Duration(days: 30), 'Last Month'),
  all(null, 'All Time');

  const ChartRange(this.duration, this.label);
  final Duration? duration;
  final String label;
}

/// Dedicated state management for BatchDetailPage
/// Separates business logic from UI concerns
class BatchDetailState extends ChangeNotifier {
  // Repository dependencies
  final BatchRepository _batchRepository;
  
  // Current batch data
  BatchModel? _batch;
  String? _batchId;
  
  // UI state
  bool _isLoading = false;
  bool _isBrewModeEnabled = false;
  bool _pauseRealtime = false;
  bool _hidePremiumHint = false;
  ChartRange _currentChartRange = ChartRange.d7;
  int _currentTabIndex = 0;
  int _tastingRating = 0;
  
  // Controllers for text inputs
  late final TextEditingController _finalNotesController;
  late final TextEditingController _finalYieldController;
  late final TextEditingController _prepNotesController;
  late final TextEditingController _tastingAppearanceController;
  late final TextEditingController _tastingAromaController;
  late final TextEditingController _tastingFlavorController;
  
  // Focus nodes
  final FocusNode _finalYieldFocus = FocusNode();
  
  // Timers and streams
  Timer? _finalYieldDebounce;
  StreamSubscription? _batchSubscription;
  
  // Final yield settings
  String _finalYieldUnit = 'gal';
  
  // Error state
  String? _errorMessage;
  
  BatchDetailState({
    required BatchRepository batchRepository,
  }) : _batchRepository = batchRepository {
    _initializeControllers();
  }
  
  // Getters
  BatchModel? get batch => _batch;
  String? get batchId => _batchId;
  bool get isLoading => _isLoading;
  bool get isBrewModeEnabled => _isBrewModeEnabled;
  bool get pauseRealtime => _pauseRealtime;
  bool get hidePremiumHint => _hidePremiumHint;
  ChartRange get currentChartRange => _currentChartRange;
  int get currentTabIndex => _currentTabIndex;
  int get tastingRating => _tastingRating;
  String get finalYieldUnit => _finalYieldUnit;
  String? get errorMessage => _errorMessage;
  
  // Controller getters
  TextEditingController get finalNotesController => _finalNotesController;
  TextEditingController get finalYieldController => _finalYieldController;
  TextEditingController get prepNotesController => _prepNotesController;
  TextEditingController get tastingAppearanceController => _tastingAppearanceController;
  TextEditingController get tastingAromaController => _tastingAromaController;
  TextEditingController get tastingFlavorController => _tastingFlavorController;
  FocusNode get finalYieldFocus => _finalYieldFocus;
  
  /// Initialize the state with a batch ID
  Future<void> initialize(String batchId) async {
    _batchId = batchId;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    
    try {
      // Load initial batch data
      final result = await _batchRepository.getById(batchId);
      
      if (result.isSuccess) {
        _batch = result.value;
        if (_batch != null) {
          _populateControllers();
          _startWatchingBatch();
        } else {
          _errorMessage = 'Batch not found';
        }
      } else {
        _errorMessage = result.error?.toString() ?? 'Failed to load batch';
      }
    } catch (e) {
      _errorMessage = 'Unexpected error: $e';
      AppLogger.instance.error('Failed to initialize BatchDetailState: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  /// Update the current tab index
  void setCurrentTabIndex(int index) {
    if (_currentTabIndex != index) {
      _currentTabIndex = index;
      notifyListeners();
    }
  }
  
  /// Update the chart time range
  void setChartRange(ChartRange range) {
    if (_currentChartRange != range) {
      _currentChartRange = range;
      notifyListeners();
    }
  }
  
  /// Toggle brew mode
  Future<void> toggleBrewMode() async {
    _isBrewModeEnabled = !_isBrewModeEnabled;
    
    if (_isBrewModeEnabled) {
      // Enable wakelock when entering brew mode
      try {
        await WakelockPlus.enable();
      } catch (e) {
        AppLogger.instance.warning('Failed to enable wakelock: $e');
      }
    } else {
      // Disable wakelock when exiting brew mode
      try {
        await WakelockPlus.disable();
      } catch (e) {
        AppLogger.instance.warning('Failed to disable wakelock: $e');
      }
    }
    
    notifyListeners();
  }
  
  /// Toggle realtime pause
  void toggleRealtimePause() {
    _pauseRealtime = !_pauseRealtime;
    notifyListeners();
  }
  
  /// Hide premium hint UI
  void setPremiumHintHidden() {
    _hidePremiumHint = true;
    notifyListeners();
  }
  
  /// Update tasting rating
  void setTastingRating(int rating) {
    if (_tastingRating != rating) {
      _tastingRating = rating;
      notifyListeners();
      _saveBatchChanges();
    }
  }
  
  /// Update final yield unit
  void setFinalYieldUnit(String unit) {
    if (_finalYieldUnit != unit) {
      _finalYieldUnit = unit;
      notifyListeners();
    }
  }
  
  /// Add a new measurement to the batch
  Future<Result<void, Exception>> addMeasurement(Measurement measurement) async {
    if (_batch == null) {
      return Failure(Exception('No batch loaded'));
    }
    
    try {
      // Create updated batch with new measurement
      final updatedBatch = _batch!.copyWith(
        measurements: [..._batch!.safeMeasurements, measurement],
      );
      
      // Save to repository
      final result = await _batchRepository.save(updatedBatch);
      
      if (result.isSuccess) {
        _batch = result.value;
        notifyListeners();
        
        AppLogger.instance.info('Measurement added to batch ${_batch!.id}');
        return const Success(null);
      } else {
        return Failure(result.error!);
      }
    } catch (e) {
      AppLogger.instance.error('Failed to add measurement: $e');
      return Failure(Exception('Failed to add measurement: $e'));
    }
  }
  
  /// Update fermentation stages
  Future<Result<void, Exception>> updateFermentationStages(List<FermentationStage> stages) async {
    if (_batch == null) {
      return Failure(Exception('No batch loaded'));
    }
    
    try {
      final updatedBatch = _batch!.copyWith(fermentationStages: stages);
      final result = await _batchRepository.save(updatedBatch);
      
      if (result.isSuccess) {
        _batch = result.value;
        notifyListeners();
        
        AppLogger.instance.info('Fermentation stages updated for batch ${_batch!.id}');
        return const Success(null);
      } else {
        return Failure(result.error!);
      }
    } catch (e) {
      AppLogger.instance.error('Failed to update fermentation stages: $e');
      return Failure(Exception('Failed to update fermentation stages: $e'));
    }
  }
  
  /// Delete the batch
  Future<Result<void, Exception>> deleteBatch() async {
    if (_batch == null) {
      return Failure(Exception('No batch loaded'));
    }
    
    try {
      final result = await _batchRepository.delete(_batch!.id);
      
      if (result.isSuccess) {
        AppLogger.instance.info('Batch ${_batch!.id} deleted');
        _batch = null;
        notifyListeners();
        return const Success(null);
      } else {
        return Failure(result.error!);
      }
    } catch (e) {
      AppLogger.instance.error('Failed to delete batch: $e');
      return Failure(Exception('Failed to delete batch: $e'));
    }
  }
  
  /// Get measurements within the current chart range
  List<Measurement> getFilteredMeasurements() {
    if (_batch == null || _currentChartRange == ChartRange.all) {
      return _batch?.safeMeasurements ?? [];
    }
    
    final cutoff = DateTime.now().subtract(_currentChartRange.duration!);
    return _batch!.safeMeasurements
        .where((m) => m.timestamp.isAfter(cutoff))
        .toList();
  }
  
  /// Infer pitch time from batch data
  DateTime? inferPitchTime() {
    if (_batch == null) return null;
    
    // Use start date as primary indicator
    return _batch!.startDate;
  }
  
  /// Private methods
  
  void _initializeControllers() {
    _finalNotesController = TextEditingController();
    _finalYieldController = TextEditingController();
    _prepNotesController = TextEditingController();
    _tastingAppearanceController = TextEditingController();
    _tastingAromaController = TextEditingController();
    _tastingFlavorController = TextEditingController();
    
    // Set up debounced save for final yield
    _finalYieldController.addListener(_onFinalYieldChanged);
    _finalNotesController.addListener(_saveBatchChanges);
    _prepNotesController.addListener(_saveBatchChanges);
  }
  
  void _populateControllers() {
    if (_batch == null) return;
    
    _finalNotesController.text = _batch!.finalNotes ?? '';
    _finalYieldController.text = _batch!.finalYield?.toString() ?? '';
    _prepNotesController.text = _batch!.prepNotes ?? '';
    // Note: tasting fields may not exist in current BatchModel
    _tastingRating = 0; // Default value
  }
  
  void _onFinalYieldChanged() {
    // Debounce final yield changes
    _finalYieldDebounce?.cancel();
    _finalYieldDebounce = Timer(const Duration(milliseconds: 500), () {
      _saveBatchChanges();
    });
  }
  
  void _saveBatchChanges() {
    if (_batch == null) return;
    
    final finalYield = double.tryParse(_finalYieldController.text);
    
    final updatedBatch = _batch!.copyWith(
      finalNotes: _finalNotesController.text.isEmpty ? null : _finalNotesController.text,
      finalYield: finalYield,
      prepNotes: _prepNotesController.text.isEmpty ? null : _prepNotesController.text,
      // Note: tasting fields may need to be added to BatchModel if needed
    );
    
    // Save asynchronously without waiting
    _batchRepository.save(updatedBatch).then((result) {
      if (result.isSuccess) {
        _batch = result.value;
      } else {
        AppLogger.instance.warning('Failed to save batch changes: ${result.error}');
      }
    });
  }
  
  void _startWatchingBatch() {
    if (_batchId == null) return;
    
    _batchSubscription?.cancel();
    _batchSubscription = _batchRepository.watchById(_batchId!).listen((result) {
      if (result.isSuccess && result.value != null) {
        _batch = result.value;
        _populateControllers();
        notifyListeners();
      }
    });
  }
  
  @override
  void dispose() {
    // Cancel timers and subscriptions
    _finalYieldDebounce?.cancel();
    _batchSubscription?.cancel();
    
    // Dispose controllers
    _finalNotesController.dispose();
    _finalYieldController.dispose();
    _prepNotesController.dispose();
    _tastingAppearanceController.dispose();
    _tastingAromaController.dispose();
    _tastingFlavorController.dispose();
    
    // Dispose focus nodes
    _finalYieldFocus.dispose();
    
    // Disable wakelock if enabled
    if (_isBrewModeEnabled) {
      WakelockPlus.disable().ignore();
    }
    
    super.dispose();
  }
}