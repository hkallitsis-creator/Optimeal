class RecipeIngredient {
  final String name;
  final double amount;
  final String unit; // e.g. "g", "ml", "tbsp", "piece"

  RecipeIngredient({
    required this.name,
    required this.amount,
    required this.unit,
  });

  factory RecipeIngredient.fromJson(Map<String, dynamic> json) {
    return RecipeIngredient(
      name: json['name'] as String,
      amount: (json['amount'] as num).toDouble(),
      unit: json['unit'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'amount': amount,
        'unit': unit,
      };

  /// Returns a new ingredient with amount scaled by [factor],
  /// e.g. factor = 2.0 doubles the recipe.
  RecipeIngredient scaled(double factor) {
    return RecipeIngredient(
      name: name,
      amount: amount * factor,
      unit: unit,
    );
  }
}

