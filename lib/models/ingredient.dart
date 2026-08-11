import 'package:flutter/foundation.dart';

@immutable
class Ingredient {
  final String id;
  final String name;
  final String? category;
  final String? badge;
  final String? prepTip;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Ingredient({
    required this.id,
    required this.name,
    this.category,
    this.badge,
    this.prepTip,
    this.createdAt,
    this.updatedAt,
  });

  Ingredient copyWith({
    String? id,
    String? name,
    String? category,
    String? badge,
    String? prepTip,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Ingredient(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      badge: badge ?? this.badge,
      prepTip: prepTip ?? this.prepTip,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'category': category,
      'badge': badge,
      // Keep `prep_tip` as the canonical write column. Some projects may
      // still read from `pinch_tip` (legacy).
      'prep_tip': prepTip,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  static Ingredient fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic v) {
      if (v == null) return null;
      if (v is DateTime) return v;
      if (v is String) return DateTime.tryParse(v);
      return null;
    }

    final id = (json['id'] ?? '').toString();
    final name = (json['name'] ?? '').toString();
    if (id.isEmpty || name.isEmpty) {
      throw FormatException('Invalid Ingredient json: missing id/name');
    }

    return Ingredient(
      id: id,
      name: name,
      category: json['category']?.toString(),
      badge: json['badge']?.toString(),
      // Supabase column naming:
      // - recommended: `prep_tip`
      // - supported/legacy: `pinch_tip`
      prepTip: (json['pinch_tip'] ?? json['prep_tip'] ?? json['prepTip'])?.toString(),
      createdAt: parseDate(json['created_at'] ?? json['createdAt']),
      updatedAt: parseDate(json['updated_at'] ?? json['updatedAt']),
    );
  }
}
