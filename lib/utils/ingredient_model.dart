class Ingredient {
  String name;
  double amount;
  String unit;
  double og; // Original gravity potential
  double pH;

  Ingredient({
    required this.name,
    required this.amount,
    required this.unit,
    required this.og,
    required this.pH,
  });
}
