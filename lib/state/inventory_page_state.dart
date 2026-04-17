import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fermentacraft/models/inventory_item.dart';
import 'package:fermentacraft/utils/app_logger.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:fermentacraft/utils/boxes.dart';

/// Inventory view modes
enum InventoryViewMode {
  grid('Grid View'),
  list('List View'),
  category('By Category');

  const InventoryViewMode(this.label);
  final String label;
}

/// Inventory filter options
enum InventoryFilter {
  all('All Items'),
  lowStock('Low Stock'),
  outOfStock('Out of Stock'),
  expiringSoon('Expiring Soon');

  const InventoryFilter(this.label);
  final String label;
}

/// Dedicated state management for InventoryPage
/// Handles inventory display, filtering, and CRUD operations
class InventoryPageState extends ChangeNotifier {
  // Data source
  late Box<InventoryItem> _inventoryBox;
  
  // Current inventory data
  List<InventoryItem> _allItems = [];
  List<InventoryItem> _filteredItems = [];
  
  // UI state
  bool _isLoading = false;
  InventoryViewMode _viewMode = InventoryViewMode.grid;
  InventoryFilter _currentFilter = InventoryFilter.all;
  String _searchQuery = '';
  
  // Controllers
  late final TextEditingController _searchController;
  
  // Error state
  String? _errorMessage;
  
  InventoryPageState() {
    _initializeControllers();
  }
  
  // Getters
  List<InventoryItem> get allItems => List.unmodifiable(_allItems);
  List<InventoryItem> get filteredItems => List.unmodifiable(_filteredItems);
  bool get isLoading => _isLoading;
  InventoryViewMode get viewMode => _viewMode;
  InventoryFilter get currentFilter => _currentFilter;
  String get searchQuery => _searchQuery;
  String? get errorMessage => _errorMessage;
  
  TextEditingController get searchController => _searchController;
  
  /// Items that are low in stock (using simple threshold)
  List<InventoryItem> get lowStockItems {
    return _allItems.where((item) {
      return item.amountInStock <= 5.0 && item.amountInStock > 0;
    }).toList();
  }
  
  /// Items that are out of stock
  List<InventoryItem> get outOfStockItems {
    return _allItems.where((item) => item.amountInStock <= 0).toList();
  }
  
  /// Items expiring soon (within 30 days)
  List<InventoryItem> get expiringSoonItems {
    final cutoff = DateTime.now().add(const Duration(days: 30));
    return _allItems.where((item) {
      final expiry = item.expirationDate;
      return expiry != null && expiry.isBefore(cutoff) && expiry.isAfter(DateTime.now());
    }).toList();
  }
  
  /// Initialize the state
  Future<void> initialize() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    
    try {
      _inventoryBox = await Hive.openBox<InventoryItem>(Boxes.inventory);
      await _loadInventoryData();
      
      AppLogger.instance.info('InventoryPageState initialized successfully');
    } catch (e) {
      _errorMessage = 'Failed to initialize inventory: $e';
      AppLogger.instance.error('Failed to initialize InventoryPageState: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  /// Set search query
  void setSearchQuery(String query) {
    if (_searchQuery != query) {
      _searchQuery = query;
      _searchController.text = query;
      _applyFiltersAndSorting();
      notifyListeners();
    }
  }
  
  /// Change the current filter
  void setFilter(InventoryFilter filter) {
    if (_currentFilter != filter) {
      _currentFilter = filter;
      _applyFiltersAndSorting();
      notifyListeners();
    }
  }
  
  /// Change the view mode
  void setViewMode(InventoryViewMode mode) {
    if (_viewMode != mode) {
      _viewMode = mode;
      notifyListeners();
    }
  }
  
  /// Private methods
  
  void _initializeControllers() {
    _searchController = TextEditingController();
    _searchController.addListener(() {
      if (_searchController.text != _searchQuery) {
        setSearchQuery(_searchController.text);
      }
    });
  }
  
  Future<void> _loadInventoryData() async {
    _allItems = _inventoryBox.values.toList();
    _applyFiltersAndSorting();
  }
  
  void _applyFiltersAndSorting() {
    List<InventoryItem> items = List.from(_allItems);
    
    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      items = items.where((item) {
        return item.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
               item.category.toLowerCase().contains(_searchQuery.toLowerCase());
      }).toList();
    }
    
    // Apply status filter
    switch (_currentFilter) {
      case InventoryFilter.all:
        // No additional filtering
        break;
      case InventoryFilter.lowStock:
        items = items.where((item) {
          return item.amountInStock <= 5.0 && item.amountInStock > 0;
        }).toList();
        break;
      case InventoryFilter.outOfStock:
        items = items.where((item) => item.amountInStock <= 0).toList();
        break;
      case InventoryFilter.expiringSoon:
        final cutoff = DateTime.now().add(const Duration(days: 30));
        items = items.where((item) {
          final expiry = item.expirationDate;
          return expiry != null && expiry.isBefore(cutoff) && expiry.isAfter(DateTime.now());
        }).toList();
        break;
    }
    
    // Sort items
    items.sort((a, b) => a.name.compareTo(b.name));
    
    _filteredItems = items;
  }
  
  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}