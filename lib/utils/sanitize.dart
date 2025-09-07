// lib/utils/sanitize.dart
import 'package:cloud_firestore/cloud_firestore.dart';

/// Recursively converts any structure to JSON-encodable types.
/// - DateTime -> ISO 8601 string (UTC)
/// - Duration -> milliseconds (int)
dynamic _jsonSan(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v.toUtc().toIso8601String();
  if (v is Duration) return v.inMilliseconds;
  if (v is Iterable) return v.map(_jsonSan).toList();
  if (v is Map) {
    return v.map((k, val) => MapEntry(k.toString(), _jsonSan(val)));
  }
  return v; // num, String, bool are fine
}

/// Recursively converts to Firestore-friendly types.
/// - DateTime -> Timestamp
/// - Duration -> milliseconds (int)
dynamic _fsSan(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return Timestamp.fromDate(v);
  if (v is Duration) return v.inMilliseconds;
  if (v is Iterable) return v.map(_fsSan).toList();
  if (v is Map) {
    return v.map((k, val) => MapEntry(k.toString(), _fsSan(val)));
  }
  return v;
}

Map<String, dynamic> sanitizeForJson(Map<String, dynamic> m) =>
    _jsonSan(m) as Map<String, dynamic>;

Map<String, dynamic> sanitizeForFirestore(Map<String, dynamic> m) =>
    _fsSan(m) as Map<String, dynamic>;
