// lib/recipe_list_page.dart

import 'package:fermentacraft/widgets/show_paywall.dart';
import 'package:flutter/material.dart';
import 'package:fermentacraft/recipe_detail_page.dart';
import 'package:fermentacraft/recipe_builder_page.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:fermentacraft/utils/snacks.dart';
import 'models/recipe_model.dart';

// Gating / sync
import 'package:fermentacraft/services/feature_gate.dart';
import 'package:fermentacraft/services/counts_service.dart';
import 'package:fermentacraft/services/firestore_sync_service.dart';

import 'utils/boxes.dart';

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

  IconData _iconForTag(String tag) {
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
      case 'no tag':
        return Icons.label_off_outlined;
      default:
        return Icons.label_outline;
    }
  }

  Color _colorForTag(BuildContext context, String tag) {
    final cs = Theme.of(context).colorScheme;
    final seed = tag.hashCode;
    final palette = <Color>[
      cs.primary,
      cs.tertiary,
      cs.secondary,
      cs.primaryContainer,
      cs.tertiaryContainer,
      cs.secondaryContainer,
    ];
    return palette[(seed.abs()) % palette.length];
  }

  Widget _tagHeader(BuildContext context, String tag, int count) {
    final icon = _iconForTag(tag);
    final color = _colorForTag(context, tag);
    return Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            tag,
            style: Theme.of(context).textTheme.titleMedium,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Chip(
          label: Text('$count'),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ],
    );
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

    // Mark remote deletion first to avoid race
    await FirestoreSyncService.instance.markDeleted(
      collection: Boxes.recipes,
      id: recipeId,
    );

    // Delete locally using the resolved key
    await box.delete(resolvedKey);

    if (!mounted) return;

    snacks
      ..clear()
      ..show(
        SnackBar(
          content: Text('Deleted "$name"'),
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'UNDO',
            onPressed: () async {
              final restored = RecipeModel.fromJson(recipeDataBackup);
              await box.put(resolvedKey, restored);
              await FirestoreSyncService.instance.forceSync();
              if (!mounted) return;
              snacks
                ..hide()
                ..show(
                  const SnackBar(
                    content: Text('Recipe restored'),
                    duration: Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
            },
          ),
        ),
      );
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

          final Map<String, List<RecipeModel>> grouped = {};
          for (final recipe in filtered) {
            final tags =
                recipe.tags.isEmpty ? ['No Tag'] : recipe.tags.map((t) => t.name);
            for (final tag in tags) {
              grouped.putIfAbsent(tag, () => []).add(recipe);
            }
          }
          final sortedKeys = grouped.keys.toList()..sort();

          return ListView.builder(
            itemCount: sortedKeys.length,
            itemBuilder: (context, i) {
              final tag = sortedKeys[i];
              final recipes = grouped[tag]!;

              return Card(
                margin:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: ExpansionTile(
                  title: _tagHeader(context, tag, recipes.length),
                  initiallyExpanded: i == 0,
                  children: recipes.map((recipe) {
                    final created = _date.format(recipe.createdAt);
                    final tagLine = recipe.tags.isNotEmpty
                        ? 'Tags: ${recipe.tags.map((t) => t.name).join(", ")}'
                        : null;

                    return Dismissible(
                      // Safe, stable key (prefer id; fallbacks for legacy items)
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
                        title: Text(recipe.name),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (tagLine != null) Text(tagLine),
                            Text('Created: $created'),
                          ],
                        ),
                        isThreeLine: tagLine != null,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => RecipeDetailPage(
                                recipe: recipe,
                                // Pass a non-null, correct key for legacy items too
                                recipeKey: _resolveHiveKeyFor(recipe),
                              ),
                            ),
                          );
                        },
                        trailing: _moreMenu(recipe),
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
    );
  }
}
