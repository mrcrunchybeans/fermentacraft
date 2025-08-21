// lib/recipe_list_page.dart

import 'package:fermentacraft/widgets/show_paywall.dart';
import 'package:flutter/material.dart';
import 'package:fermentacraft/pages/recipe_detail_page.dart';
import 'package:fermentacraft/pages/recipe_builder_page.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:fermentacraft/utils/snacks.dart';
import '../models/recipe_model.dart';


// Gating / sync
import 'package:fermentacraft/services/feature_gate.dart';
import 'package:fermentacraft/services/counts_service.dart';
import 'package:fermentacraft/services/firestore_sync_service.dart';

import '../utils/boxes.dart';

enum SortMode { dateCreated, aToZ, zToA, recentlyOpened }
enum _RecipeAction { archiveToggle, delete }

class RecipeListPage extends StatefulWidget {
  const RecipeListPage({super.key});

  @override
  State<RecipeListPage> createState() => _RecipeListPageState();
}

class _RecipeListPageState extends State<RecipeListPage> {
  final _date = DateFormat.yMMMd();
  SortMode _sortMode = SortMode.dateCreated;
  bool _showArchived = false;

  IconData _iconForCategory(String tag) {
    switch (tag.toLowerCase()) {
      case 'cider':
        return Icons.local_drink_outlined;
      case 'mead':
        return Icons.hive_outlined;
      case 'wine':
        return Icons.wine_bar_outlined;
      case 'fruit wine':
        return Icons.local_florist_outlined;
      case 'experimental':
        return Icons.science_outlined;
      case 'draft':
        return Icons.edit_note_outlined;
      case 'favorite':
      case 'favourite':
        return Icons.star_outline;
      case 'archived':
        return Icons.archive_outlined;
      case 'uncategorized':
        return Icons.folder_open_outlined;
      case 'no tag':
        return Icons.label_off_outlined;
      default:
        return Icons.label_outline;
    }
  }

  Color _colorForCategory(BuildContext context, String category) {
    final cs = Theme.of(context).colorScheme;
    final seed = category.hashCode;
    final palette = <Color>[
      cs.primary, cs.tertiary, cs.secondary,
      cs.primaryContainer, cs.tertiaryContainer, cs.secondaryContainer,
    ];
    return palette[(seed.abs()) % palette.length];
  }

  Widget _categoryHeader(BuildContext context, String category, int count) {
    final color = _colorForCategory(context, category);
    return Row(
      children: [
        Icon(_iconForCategory(category), color: color),
        const SizedBox(width: 8),
        Text(category, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(width: 8),
        Chip(
          label: Text('$count'),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ],
    );
  }

  /// Quick stat line that matches what the builder computes.
  String _statLine(RecipeModel r) {
    final og = r.og?.toStringAsFixed(3);
    final fg = r.fg?.toStringAsFixed(3);
    final abv = r.abv?.toStringAsFixed(1);
    final parts = <String>[];
    if (og != null) parts.add('OG $og');
    if (fg != null) parts.add('FG $fg');
    if (abv != null) parts.add('ABV $abv%');
    return parts.isEmpty ? '' : parts.join(' · ');
  }

  // ----------------- Key resolution (handles legacy/null keys) ----------------

  dynamic _resolveHiveKeyFor(RecipeModel recipe) {
    final box = Hive.box<RecipeModel>(Boxes.recipes);

    // 1) If Hive attached a key, use it.
    final dynamic k1 = recipe.key;
    if (k1 != null) return k1;

    // 2) Try by stable id (post-migration keys should equal id).
    final id = recipe.id;
    final map = box.toMap(); // read once
    if (id.trim().isNotEmpty) {
      for (final entry in map.entries) {
        if (entry.value.id == id) return entry.key; // may be String or int
      }
    }

    // 3) Last resort: identity match (same instance).
    for (final entry in map.entries) {
      if (identical(entry.value, recipe)) return entry.key;
    }

    throw StateError(
      'Could not resolve Hive key for recipe "${recipe.name}" (id=$id, key=null)',
    );
  }

  // --------------------------------- Actions ---------------------------------

  Future<void> _toggleArchiveStatus(RecipeModel recipe) async {
    final isArchiving = !recipe.isArchived;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isArchiving ? 'Archive Recipe?' : 'Unarchive Recipe?'),
        content: Text(
          'Are you sure you want to ${isArchiving ? 'archive' : 'unarchive'} "${recipe.name}"?',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(isArchiving ? 'Archive' : 'Unarchive'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      recipe.isArchived = isArchiving;
      await recipe.save();
      if (!mounted) return;

      snacks
        ..clear()
        ..show(
          SnackBar(
            content: Text(isArchiving
                ? 'Archived "${recipe.name}"'
                : 'Unarchived "${recipe.name}"'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      setState(() {}); // regroup/rebuild
    }
  }

  Future<void> _deleteRecipeWithUndo(RecipeModel recipe) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Recipe?'),
        content: Text('This will permanently delete "${recipe.name}".'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

final box = Hive.box<RecipeModel>(Boxes.recipes);
final resolvedKey = _resolveHiveKeyFor(recipe); // robust key
final recipeDataBackup = recipe.toJson();
final recipeId = recipe.id;
final name = recipe.name;

// 1) Tombstone every plausible remote doc id
final idsToTombstone = <String>{};

if (recipeId.trim().isNotEmpty) idsToTombstone.add(recipeId.trim());

final resolvedKeyStr = resolvedKey?.toString().trim();
if (resolvedKeyStr != null && resolvedKeyStr.isNotEmpty) {
  idsToTombstone.add(resolvedKeyStr);
}

final objKeyStr = recipe.key?.toString().trim();
if (objKeyStr != null && objKeyStr.isNotEmpty) {
  idsToTombstone.add(objKeyStr);
}

for (final rid in idsToTombstone) {
  await FirestoreSyncService.instance.markDeleted(
    collection: Boxes.recipes,
    id: rid,
  );
}

// 2) Delete locally
await box.delete(resolvedKey);

// 3) Force convergence so nothing resurrects
await FirestoreSyncService.instance.forceSync();

if (!mounted) return;

snacks
  ..clear()
  ..show(
    SnackBar(
      content: Text('Deleted "$name"'),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2), // shorter
      showCloseIcon: true,                  // optional
      action: SnackBarAction(
        label: 'UNDO',
        onPressed: () async {
          final restored = RecipeModel.fromJson(recipeDataBackup);
          await box.put(resolvedKey, restored);
          await FirestoreSyncService.instance.forceSync();
          if (!mounted) return;
          snacks
            ..hide()
            ..show(const SnackBar(
              content: Text('Recipe restored'),
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 2),
              showCloseIcon: true,
            ));
        },
      ),
    ),
  );

// 👇 force-hide early in case the timer stalls
Future.delayed(const Duration(milliseconds: 1800), () {
  if (mounted) snacks.hide();
});
  }

  PopupMenuButton<_RecipeAction> _moreMenu(RecipeModel recipe) {
    return PopupMenuButton<_RecipeAction>(
      onSelected: (action) {
        switch (action) {
          case _RecipeAction.archiveToggle:
            _toggleArchiveStatus(recipe);
            break;
          case _RecipeAction.delete:
            _deleteRecipeWithUndo(recipe);
            break;
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _RecipeAction.archiveToggle,
          child: Text(recipe.isArchived ? 'Unarchive' : 'Archive'),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: _RecipeAction.delete,
          child: Row(
            children: const [
              Icon(Icons.delete_outline),
              SizedBox(width: 8),
              Text('Delete'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _swipeBg(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Alignment alignment,
    bool danger = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    final color = danger ? cs.error : cs.primary;
    final onColor = danger ? cs.onError : cs.onPrimary;

    return Container(
      // ignore: deprecated_member_use
      color: color.withOpacity(0.90),
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: onColor),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(color: onColor, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // ------------------------------------ UI -----------------------------------

  void _onAddRecipePressed() {
    final fg = context.read<FeatureGate>();
    final recipeCount = CountsService.instance.recipeCount();

    if (!fg.canAddRecipe(recipeCount)) {
      snacks.show(
        SnackBar(
          content: Text(
              'Free allows ${fg.recipeLimitFree} recipes. Upgrade to add more.'),
        ),
      );
      showPaywall(context);
      return;
    }

    snacks.clear();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RecipeBuilderPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_showArchived ? 'Archived Recipes' : 'Saved Recipes'),
        actions: [
          PopupMenuButton<SortMode>(
            onSelected: (mode) => setState(() => _sortMode = mode),
            icon: const Icon(Icons.sort),
            itemBuilder: (_) => const [
              PopupMenuItem(
                  value: SortMode.dateCreated, child: Text('Date Created')),
              PopupMenuItem(value: SortMode.aToZ, child: Text('A → Z')),
              PopupMenuItem(value: SortMode.zToA, child: Text('Z → A')),
              PopupMenuItem(
                  value: SortMode.recentlyOpened,
                  child: Text('Recently Opened')),
            ],
          ),
          IconButton(
            icon: Icon(_showArchived
                ? Icons.inventory_2_outlined
                : Icons.archive_outlined),
            tooltip: _showArchived ? 'View Active Recipes' : 'View Archived',
            onPressed: () => setState(() => _showArchived = !_showArchived),
          ),
        ],
      ),
      body: ValueListenableBuilder<Box<RecipeModel>>(
        valueListenable: Hive.box<RecipeModel>(Boxes.recipes).listenable(),
        builder: (context, box, _) {
          if (box.isEmpty) {
            return Center(
              child: Text(_showArchived
                  ? 'No archived recipes.'
                  : 'No recipes saved yet.'),
            );
          }

          List<RecipeModel> filtered =
              box.values.where((r) => r.isArchived == _showArchived).toList();

          if (filtered.isEmpty) {
            return Center(
              child: Text(_showArchived
                  ? 'No archived recipes.'
                  : 'No recipes match your filter.'),
            );
          }

          final epoch = DateTime.fromMillisecondsSinceEpoch(0);
          switch (_sortMode) {
            case SortMode.dateCreated:
              filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
              break;
            case SortMode.aToZ:
              filtered.sort((a, b) =>
                  a.name.toLowerCase().compareTo(b.name.toLowerCase()));
              break;
            case SortMode.zToA:
              filtered.sort((a, b) =>
                  b.name.toLowerCase().compareTo(a.name.toLowerCase()));
              break;
            case SortMode.recentlyOpened:
              filtered.sort((a, b) =>
                  (b.lastOpened ?? epoch).compareTo(a.lastOpened ?? epoch));
              break;
          }

          // Group by single category label (builder writes `category`)
          final Map<String, List<RecipeModel>> grouped = {};
          for (final recipe in filtered) {
            final key = recipe.categoryLabel;
            grouped.putIfAbsent(key, () => []).add(recipe);
          }
          final sortedKeys = grouped.keys.toList()..sort();

          return ListView.builder(
            itemCount: sortedKeys.length,
            itemBuilder: (context, i) {
              final category = sortedKeys[i];
              final recipes = grouped[category]!;

              return Card(
                margin:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: ExpansionTile(
                  title: _categoryHeader(context, category, recipes.length),
                  initiallyExpanded: i == 0,
                  children: recipes.map((recipe) {
                    final created = _date.format(recipe.createdAt);
                    final itemColor = _colorForCategory(context, category);

                    return Dismissible(
                      // Stable id key
                      key: ValueKey(recipe.id),
                      background: _swipeBg(
                        context,
                        icon: recipe.isArchived
                            ? Icons.unarchive
                            : Icons.archive_outlined,
                        label: recipe.isArchived ? 'Unarchive' : 'Archive',
                        alignment: Alignment.centerLeft,
                      ),
                      secondaryBackground: _swipeBg(
                        context,
                        icon: Icons.delete_outline,
                        label: 'Delete',
                        alignment: Alignment.centerRight,
                        danger: true,
                      ),
                      confirmDismiss: (direction) async {
                        snacks.hide();
                        if (direction == DismissDirection.startToEnd) {
                          await _toggleArchiveStatus(recipe);
                          return false; // handled
                        } else {
                          await _deleteRecipeWithUndo(recipe);
                          return false; // handled
                        }
                      },
                      child: ListTile(
                        leading: Icon(
                          _iconForCategory(category),
                          color: itemColor,
                        ),
                        title: Text(recipe.name),
                        subtitle: Text(
                          [
                            'Created: $created',
                            _statLine(recipe),
                          ].where((s) => s.isNotEmpty).join('\n'),
                        ),
                        trailing: _moreMenu(recipe),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => RecipeDetailPage(
                                recipe: recipe,
                                recipeKey: _resolveHiveKeyFor(recipe),
                              ),
                            ),
                          );
                        },
                        onLongPress: () => _toggleArchiveStatus(recipe),
                      ),
                    );
                  }).toList(),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'addRecipeFab',
        onPressed: _onAddRecipePressed,
        tooltip: 'New Recipe',
        child: const Icon(Icons.add),
      ),
    ); // ⬅️ close return Scaffold(...)
  }     // ⬅️ close build()
}       // ⬅️ close class _RecipeListPageState