// lib/services/temp_unit_service.dart
enum TempUnit { c, f }

class TempUnitService {
  final TempUnit userUnit; // inject from settings/provider

  const TempUnitService(this.userUnit);

  // Store canonical (°C)
  double toCanonicalC(double input) =>
      userUnit == TempUnit.f ? ((input - 32.0) * 5.0 / 9.0) : input;

  // Show in user’s unit
  double toDisplay(double storedC) =>
      userUnit == TempUnit.f ? (storedC * 9.0 / 5.0 + 32.0) : storedC;

  String label() => userUnit == TempUnit.f ? '°F' : '°C';
}
