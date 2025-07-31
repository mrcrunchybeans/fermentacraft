import '../utils/utils.dart';

enum AbvSource {
  measured,
  adjusted,
}

class Ingredient {
  final double? amount;
  final VolumeUnit? unit;
  final double? sg;

  Ingredient({this.amount, this.unit, this.sg});
}
