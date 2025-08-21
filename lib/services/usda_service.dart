// lib/services/usda_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import 'package:fermentacraft/models/enums.dart';

const String usdaApiKey = '19KqdR8naSAvfiWrx5ZltHDsuVUtwVcs1A3dmr4j'; // consider moving to secure config

String _searchUrl(String query, {required List<String> dataTypes, int pageSize = 25}) {
  final dt = dataTypes.map(Uri.encodeQueryComponent).join(',');
  final q = Uri.encodeQueryComponent(query);
  return 'https://api.nal.usda.gov/fdc/v1/foods/search'
      '?dataType=$dt&pageSize=$pageSize&query=$q&api_key=$usdaApiKey';
}

const String fdcDetailBase = 'https://api.nal.usda.gov/fdc/v1/food'; // /{fdcId}?api_key=...

class UsdaService {
  final _cache = <String, List<UsdaChoice>>{};
  final _client = http.Client();

  static const _timeout = Duration(seconds: 8);
  static const _headers = {
    'User-Agent': 'FermentaCraft/1.0 (+mobile)',
    'Accept': 'application/json',
  };

  Future<List<UsdaChoice>> searchFoods(String query) async {
    final q = query.trim();
    if (q.isEmpty) return [];

    final brandIntent = _looksLikeBrandQuery(q);
    final cacheKey = '${q.toLowerCase()}|brand=$brandIntent';
    if (_cache.containsKey(cacheKey)) return _cache[cacheKey]!;

    try {
      // Pass 1: generics only
      final generic = await _fetchFdcSearch(
        q,
        dataTypes: const ['Foundation', 'SR Legacy'],
        allowBrands: false,
      );

      final needBrands = brandIntent || generic.length < 5;

      List<UsdaChoice> out = generic;
      if (needBrands) {
        final branded = await _fetchFdcSearch(
          q,
          dataTypes: const ['Branded'],
          allowBrands: true,
        );
        out = [...generic, ...branded];
      }

      // De-dup by fdcId
      final seen = <int>{};
      final merged = <UsdaChoice>[];
      for (final c in out) {
        if (seen.add(c.fdcId)) merged.add(c);
      }
      _cache[cacheKey] = merged;
      return merged;
    } catch (_) {
      final fb = _fallback(q.toLowerCase());
      _cache[cacheKey] = fb;
      return fb;
    }
  }

  Future<UsdaFoodDetail> getFood(int fdcId, {FermentableType? hint}) async {
    try {
      final url = '$fdcDetailBase/$fdcId?api_key=$usdaApiKey';
      final res = await _client.get(Uri.parse(url), headers: _headers).timeout(_timeout);

      if (res.statusCode != 200) {
        return UsdaFoodDetail(brix: hint?.defaultBrix, density: hint?.defaultDensity);
      }

      final json = jsonDecode(res.body);
      final dataType = (json['dataType'] as String?)?.toLowerCase();

      double? brix;
      double? density;

      // 1) Try foodNutrients "Sugars (g per 100g)" — best for Foundation/SR
      final nutrients = (json['foodNutrients'] as List?) ?? const [];
      for (final n in nutrients) {
        final nutrient = n['nutrient'];
        if (nutrient == null) continue;
        final name = (nutrient['name'] as String?)?.toLowerCase() ?? '';
        final unit = (nutrient['unitName'] as String?)?.toUpperCase();
        final amount = (n['amount'] as num?)?.toDouble();
        if (amount == null) continue;

        if (name.contains('sugars') && unit == 'G') {
          brix ??= amount.clamp(0, 100);
        }
      }

      // 2) If Branded and brix missing, derive from labelNutrients + servingSize
      if (brix == null && dataType == 'branded') {
        final label = json['labelNutrients'];
        final servingSize = (json['servingSize'] as num?)?.toDouble();
        final sugars = (label is Map && label['sugars'] is Map)
            ? (label['sugars']['value'] as num?)?.toDouble()
            : null;

        if (sugars != null && servingSize != null && servingSize > 0) {
          final per100 = sugars * (100.0 / servingSize);
          brix = per100.clamp(0, 100);
        }
      }

      // 3) Convert °Bx to density/SG proxy if possible
      if (brix != null) {
        final b = brix;
        final sg = 1 + (b / (258.6 - ((b / 258.2) * 227.1)));
        density = sg; // treat SG as g/mL proxy
      }

      density ??= hint?.defaultDensity;
      brix ??= hint?.defaultBrix;

      return UsdaFoodDetail(brix: brix, density: density);
    } catch (_) {
      return UsdaFoodDetail(brix: hint?.defaultBrix, density: hint?.defaultDensity);
    }
  }

  // ————————————————— helpers —————————————————

  Future<List<UsdaChoice>> _fetchFdcSearch(
    String query, {
    required List<String> dataTypes,
    required bool allowBrands,
  }) async {
    final url = _searchUrl(query, dataTypes: dataTypes, pageSize: 25);
    final res = await _client.get(Uri.parse(url), headers: _headers).timeout(_timeout);
    if (res.statusCode != 200) throw Exception('USDA search failed');

    final jsonMap = jsonDecode(res.body);
    final foods = (jsonMap['foods'] as List?) ?? const [];

    final results = <UsdaChoice>[];
    for (final item in foods) {
      final name = (item['description'] as String?)?.trim() ?? '';
      final fdcId = (item['fdcId'] as int?) ?? -1;
      final dataType = ((item['dataType'] as String?) ?? '').toLowerCase();
      final brandOwner = (item['brandOwner'] as String?)?.trim() ?? '';

      if (!allowBrands) {
        // Strictly generic
        if (dataType == 'branded') continue;
        if (brandOwner.isNotEmpty) continue;
      }

      final type = _inferType(name.toLowerCase());
      results.add(UsdaChoice(
        name: allowBrands && brandOwner.isNotEmpty ? '$name — $brandOwner' : name,
        fdcId: fdcId,
        type: type,
        branded: dataType == 'branded' || brandOwner.isNotEmpty,
      ));
    }

    // Rank: generics first; within each group, prefer simpler names
    results.sort((a, b) {
      if (a.branded != b.branded) return a.branded ? 1 : -1; // branded after generic

      int score(String s) {
        final l = s.toLowerCase();
        int sc = 0;
        if (l.contains(',')) sc += 1;
        if (l.contains('(')) sc += 1;
        if (RegExp(r'\d').hasMatch(l)) sc += 1;
        if (l.contains('—')) sc += 1; // brand fused
        return sc;
      }

      final sa = score(a.name);
      final sb = score(b.name);
      if (sa != sb) return sa.compareTo(sb);
      return a.name.compareTo(b.name);
    });

    return results.take(12).toList(growable: false);
  }

  bool _looksLikeBrandQuery(String q) {
    final l = q.toLowerCase();
    if (l.contains('®') || l.contains('™')) return true;
    if (l.split(RegExp(r'\s+')).length >= 2) return true; // multi-word often brandy
    if (RegExp(r'[0-9]').hasMatch(l)) return true;        // SKUs, “100%”, etc.
    const brandHints = ['orchard', 'minute maid', 'ocean spray', 'welch', 'mott', 'store brand'];
    if (brandHints.any((h) => l.contains(h))) return true;
    return false;
  }

  List<UsdaChoice> _fallback(String q) {
    final pool = [
      UsdaChoice(name: 'Honey', fdcId: 20001, type: FermentableType.honey),
      UsdaChoice(name: 'Apple juice, unsweetened', fdcId: 20002, type: FermentableType.juice),
      UsdaChoice(name: 'Grape must', fdcId: 20003, type: FermentableType.fruit),
      UsdaChoice(name: 'Table sugar (sucrose)', fdcId: 20004, type: FermentableType.sugar),
      UsdaChoice(name: 'Water', fdcId: 99999, type: FermentableType.water),
    ];
    return pool.where((e) => e.name.toLowerCase().contains(q)).toList();
  }

  FermentableType _inferType(String lowerName) {
    if (lowerName.contains('honey')) return FermentableType.honey;
    if (lowerName.contains('juice')) return FermentableType.juice;
    if (lowerName.contains('must')) return FermentableType.fruit;
    if (lowerName.contains('grape') ||
        lowerName.contains('berry') ||
        lowerName.contains('apple') ||
        lowerName.contains('fruit')) {
      return FermentableType.fruit;
    }
    if (lowerName.contains('sugar') || lowerName.contains('sucrose')) return FermentableType.sugar;
    if (lowerName.contains('water')) return FermentableType.water;
    return FermentableType.fruit;
  }
}

class UsdaChoice {
  final String name;
  final int fdcId;
  final FermentableType type;
  final bool branded; // so the UI can badge/gray these if you like
  UsdaChoice({
    required this.name,
    required this.fdcId,
    required this.type,
    this.branded = false,
  });
}

class UsdaFoodDetail {
  final double? brix;    // %
  final double? density; // g/mL (≈ SG)
  const UsdaFoodDetail({this.brix, this.density});
}
