// lib/utils/id.dart
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Generate a stable, random string ID for new entities.
String generateId() => _uuid.v4();
