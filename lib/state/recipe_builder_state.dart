import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fermentacraft/models/recipe_model.dart';
import 'package:fermentacraft/models/fermentation_stage.dart';
import 'package:fermentacraft/models/tag.dart';
import 'package:fermentacraft/repositories/repositories.dart';
import 'package:fermentacraft/utils/result.dart';
import 'package:fermentacraft/utils/app_logger.dart';

/// Recipe building step enumeration
enum RecipeBuilderStep {
  basics(0, 'Basics'),
  ingredients(1, 'Ingredients'),
  process(2, 'Process'),
  review(3, 'Review');

  const RecipeBuilderStep(this.stepIndex, this.title);
  final int stepIndex;
  final String title;
}

/// Dedicated state management for RecipeBuilderPage
/// Handles recipe creation and editing with step-by-step validation
class RecipeBuilderState extends ChangeNotifier {
  // Repository dependencies
  final RecipeRepository _recipeRepository;
  
  // Recipe data
  RecipeModel? _recipe;
  String? _recipeId;
  bool _isEditing = false;
  
  // UI state
  bool _isLoading = false;
  bool _isSaving = false;
  RecipeBuilderStep _currentStep = RecipeBuilderStep.basics;
  
  // Form controllers
  late final TextEditingController _nameController;
  late final TextEditingController _styleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _batchSizeController;
  late final TextEditingController _ogController;
  late final TextEditingController _fgController;
  late final TextEditingController _abvController;
  late final TextEditingController _ibuController;
  late final TextEditingController _srmController;
  late final TextEditingController _notesController;
  
  // Recipe components
  List<Map<String, dynamic>> _ingredients = [];
  List<Map<String, dynamic>> _additives = [];
  List<Map<dynamic, dynamic>> _yeast = [];
  List<FermentationStage> _fermentationStages = [];
  List<Tag> _tags = [];
  
  // Validation state
  final Map<RecipeBuilderStep, List<String>> _validationErrors = {};
  
  // Error handling
  String? _errorMessage;
  
  RecipeBuilderState({
    required RecipeRepository recipeRepository,
  }) : _recipeRepository = recipeRepository {
    _initializeControllers();
    _initializeDefaults();
  }
  
  // Getters
  RecipeModel? get recipe => _recipe;
  String? get recipeId => _recipeId;
  bool get isEditing => _isEditing;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  RecipeBuilderStep get currentStep => _currentStep;
  List<Map<String, dynamic>> get ingredients => List.unmodifiable(_ingredients);
  List<Map<String, dynamic>> get additives => List.unmodifiable(_additives);
  List<Map<dynamic, dynamic>> get yeast => List.unmodifiable(_yeast);
  List<FermentationStage> get fermentationStages => List.unmodifiable(_fermentationStages);
  List<Tag> get tags => List.unmodifiable(_tags);
  String? get errorMessage => _errorMessage;
  
  // Controller getters
  TextEditingController get nameController => _nameController;
  TextEditingController get styleController => _styleController;
  TextEditingController get descriptionController => _descriptionController;
  TextEditingController get batchSizeController => _batchSizeController;
  TextEditingController get ogController => _ogController;
  TextEditingController get fgController => _fgController;
  TextEditingController get abvController => _abvController;
  TextEditingController get ibuController => _ibuController;
  TextEditingController get srmController => _srmController;
  TextEditingController get notesController => _notesController;
  
  /// Initialize with a new recipe
  void initializeNewRecipe() {
    _recipe = null;
    _recipeId = null;
    _isEditing = false;
    _currentStep = RecipeBuilderStep.basics;
    
    _clearAllFields();
    _initializeDefaults();
    _clearValidationErrors();
    
    _errorMessage = null;
    notifyListeners();
  }
  
  /// Initialize for editing an existing recipe
  Future<void> initializeEditRecipe(String recipeId) async {
    _recipeId = recipeId;
    _isEditing = true;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    
    try {
      final result = await _recipeRepository.getById(recipeId);
      
      if (result.isSuccess && result.value != null) {
        _recipe = result.value;
        _populateFromRecipe();
        _currentStep = RecipeBuilderStep.basics;
      } else {
        _errorMessage = 'Recipe not found';
      }
    } catch (e) {
      _errorMessage = 'Failed to load recipe: $e';
      AppLogger.instance.error('Failed to load recipe for editing: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  /// Move to the next step
  Future<bool> nextStep() async {
    if (!await _validateCurrentStep()) {
      return false;
    }
    
    final nextIndex = _currentStep.stepIndex + 1;
    if (nextIndex < RecipeBuilderStep.values.length) {
      _currentStep = RecipeBuilderStep.values[nextIndex];
      notifyListeners();
      return true;
    }
    
    return false;
  }
  
  /// Move to the previous step
  void previousStep() {
    final prevIndex = _currentStep.stepIndex - 1;
    if (prevIndex >= 0) {
      _currentStep = RecipeBuilderStep.values[prevIndex];
      notifyListeners();
    }
  }
  
  /// Go to a specific step
  Future<bool> goToStep(RecipeBuilderStep step) async {
    // Validate all steps up to the target step
    for (int i = 0; i <= step.stepIndex; i++) {
      final stepToValidate = RecipeBuilderStep.values[i];
      _currentStep = stepToValidate;
      
      if (!await _validateCurrentStep()) {
        notifyListeners();
        return false;
      }
    }
    
    _currentStep = step;
    notifyListeners();
    return true;
  }
  
  /// Add an ingredient
  void addIngredient(Map<String, dynamic> ingredient) {
    _ingredients.add(ingredient);
    _clearValidationErrors();
    notifyListeners();
  }
  
  /// Update an ingredient
  void updateIngredient(int index, Map<String, dynamic> ingredient) {
    if (index >= 0 && index < _ingredients.length) {
      _ingredients[index] = ingredient;
      _clearValidationErrors();
      notifyListeners();
    }
  }
  
  /// Remove an ingredient
  void removeIngredient(int index) {
    if (index >= 0 && index < _ingredients.length) {
      _ingredients.removeAt(index);
      _clearValidationErrors();
      notifyListeners();
    }
  }
  
  /// Add an additive
  void addAdditive(Map<String, dynamic> additive) {
    _additives.add(additive);
    notifyListeners();
  }
  
  /// Remove an additive
  void removeAdditive(int index) {
    if (index >= 0 && index < _additives.length) {
      _additives.removeAt(index);
      notifyListeners();
    }
  }
  
  /// Add yeast
  void addYeast(Map<dynamic, dynamic> yeastEntry) {
    _yeast.add(yeastEntry);
    notifyListeners();
  }
  
  /// Remove yeast
  void removeYeast(int index) {
    if (index >= 0 && index < _yeast.length) {
      _yeast.removeAt(index);
      notifyListeners();
    }
  }
  
  /// Add fermentation stage
  void addFermentationStage(FermentationStage stage) {
    _fermentationStages.add(stage);
    notifyListeners();
  }
  
  /// Remove fermentation stage
  void removeFermentationStage(int index) {
    if (index >= 0 && index < _fermentationStages.length) {
      _fermentationStages.removeAt(index);
      notifyListeners();
    }
  }
  
  /// Add a tag
  void addTag(Tag tag) {
    if (!_tags.any((t) => t.name == tag.name)) {
      _tags.add(tag);
      notifyListeners();
    }
  }
  
  /// Remove a tag
  void removeTag(Tag tag) {
    _tags.removeWhere((t) => t.name == tag.name);
    notifyListeners();
  }
  
  /// Save the recipe
  Future<Result<RecipeModel, Exception>> saveRecipe() async {
    // Validate all steps
    _clearValidationErrors();
    bool allValid = true;
    
    for (final step in RecipeBuilderStep.values) {
      _currentStep = step;
      if (!await _validateCurrentStep()) {
        allValid = false;
      }
    }
    
    if (!allValid) {
      _currentStep = RecipeBuilderStep.basics; // Go back to first invalid step
      notifyListeners();
      return Failure(Exception('Recipe validation failed'));
    }
    
    _isSaving = true;
    notifyListeners();
    
    try {
      final recipeToSave = _buildRecipeFromState();
      final result = await _recipeRepository.save(recipeToSave);
      
      if (result.isSuccess) {
        _recipe = result.value!;
        _recipeId = result.value!.id;
        _isEditing = true;
        
        AppLogger.instance.info('Recipe saved successfully: ${result.value!.id}');
        return Success(result.value!);
      } else {
        _errorMessage = result.error?.toString() ?? 'Failed to save recipe';
        return Failure(result.error!);
      }
    } catch (e) {
      _errorMessage = 'Unexpected error: $e';
      AppLogger.instance.error('Failed to save recipe: $e');
      return Failure(Exception('Failed to save recipe: $e'));
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }
  
  /// Get validation errors for a specific step
  List<String> getValidationErrors(RecipeBuilderStep step) {
    return _validationErrors[step] ?? [];
  }
  
  /// Check if a step has validation errors
  bool hasValidationErrors(RecipeBuilderStep step) {
    return _validationErrors[step]?.isNotEmpty ?? false;
  }
  
  /// Private methods
  
  void _initializeControllers() {
    _nameController = TextEditingController();
    _styleController = TextEditingController();
    _descriptionController = TextEditingController();
    _batchSizeController = TextEditingController();
    _ogController = TextEditingController();
    _fgController = TextEditingController();
    _abvController = TextEditingController();
    _ibuController = TextEditingController();
    _srmController = TextEditingController();
    _notesController = TextEditingController();
  }
  
  void _initializeDefaults() {
    _batchSizeController.text = '5.0'; // Default 5 gallon batch
    _fermentationStages = [
      FermentationStage(
        name: 'Primary Fermentation',
        durationDays: 7,
        targetTempC: 20.0, // ~68°F
      ),
    ];
  }
  
  void _clearAllFields() {
    _nameController.clear();
    _styleController.clear();
    _descriptionController.clear();
    _batchSizeController.clear();
    _ogController.clear();
    _fgController.clear();
    _abvController.clear();
    _ibuController.clear();
    _srmController.clear();
    _notesController.clear();
    
    _ingredients.clear();
    _additives.clear();
    _yeast.clear();
    _fermentationStages.clear();
    _tags.clear();
  }
  
  void _populateFromRecipe() {
    if (_recipe == null) return;
    
    _nameController.text = _recipe!.name;
    _styleController.text = _recipe!.category ?? '';
    _descriptionController.text = _recipe!.notes;
    _batchSizeController.text = _recipe!.batchVolume?.toString() ?? '';
    _ogController.text = _recipe!.og?.toString() ?? '';
    _fgController.text = _recipe!.fg?.toString() ?? '';
    _abvController.text = _recipe!.abv?.toString() ?? '';
    _ibuController.text = ''; // Not available in current model
    _srmController.text = ''; // Not available in current model
    _notesController.text = _recipe!.notes;
    
    _ingredients = List<Map<String, dynamic>>.from(_recipe!.ingredients);
    _additives = List<Map<String, dynamic>>.from(_recipe!.additives);
    _yeast = List<Map<dynamic, dynamic>>.from(_recipe!.yeast);
    _fermentationStages = List.from(_recipe!.fermentationStages);
    _tags = List.from(_recipe!.tags);
  }
  
  RecipeModel _buildRecipeFromState() {
    final now = DateTime.now();
    
    return RecipeModel(
      id: _recipeId,
      name: _nameController.text.trim(),
      category: _styleController.text.trim().isEmpty ? null : _styleController.text.trim(),
      notes: _notesController.text.trim(),
      batchVolume: double.tryParse(_batchSizeController.text),
      og: double.tryParse(_ogController.text),
      fg: double.tryParse(_fgController.text),
      abv: double.tryParse(_abvController.text),
      plannedOg: double.tryParse(_ogController.text),
      plannedAbv: double.tryParse(_abvController.text),
      ingredients: _ingredients,
      additives: _additives,
      yeast: _yeast,
      fermentationStages: _fermentationStages,
      tags: _tags,
      createdAt: _recipe?.createdAt ?? now,
    );
  }
  
  Future<bool> _validateCurrentStep() async {
    final errors = <String>[];
    
    switch (_currentStep) {
      case RecipeBuilderStep.basics:
        if (_nameController.text.trim().isEmpty) {
          errors.add('Recipe name is required');
        }
        if (_batchSizeController.text.trim().isEmpty || 
            double.tryParse(_batchSizeController.text) == null) {
          errors.add('Valid batch size is required');
        }
        break;
        
      case RecipeBuilderStep.ingredients:
        if (_ingredients.isEmpty) {
          errors.add('At least one ingredient is required');
        }
        if (_yeast.isEmpty) {
          errors.add('Yeast selection is required');
        }
        break;
        
      case RecipeBuilderStep.process:
        if (_fermentationStages.isEmpty) {
          errors.add('At least one fermentation stage is required');
        }
        break;
        
      case RecipeBuilderStep.review:
        // Final validation - all previous steps should be valid
        break;
    }
    
    if (errors.isNotEmpty) {
      _validationErrors[_currentStep] = errors;
    } else {
      _validationErrors.remove(_currentStep);
    }
    
    notifyListeners();
    return errors.isEmpty;
  }
  
  void _clearValidationErrors() {
    _validationErrors.clear();
  }
  
  @override
  void dispose() {
    // Dispose controllers
    _nameController.dispose();
    _styleController.dispose();
    _descriptionController.dispose();
    _batchSizeController.dispose();
    _ogController.dispose();
    _fgController.dispose();
    _abvController.dispose();
    _ibuController.dispose();
    _srmController.dispose();
    _notesController.dispose();
    
    super.dispose();
  }
}