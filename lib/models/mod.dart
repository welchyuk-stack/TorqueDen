/// A modification logged against a car. Mirrors the `mods` table in Supabase.
class Mod {
  const Mod({
    required this.id,
    required this.carId,
    required this.category,
    required this.name,
    this.notes,
  });

  final String id;
  final String carId;

  /// Preset bucket, e.g. "Exhaust" or "Suspension". Defaults to "Other".
  final String category;
  final String name;
  final String? notes;

  factory Mod.fromMap(Map<String, dynamic> map) {
    return Mod(
      id: map['id'] as String,
      carId: map['car_id'] as String,
      category: map['category'] as String? ?? 'Other',
      name: map['name'] as String,
      notes: map['notes'] as String?,
    );
  }
}
