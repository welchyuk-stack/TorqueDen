/// A single performance/spec row for a car. Mirrors the `car_specs` table
/// in Supabase: a free-form label/value pair (e.g. "Power" / "473 hp").
class CarSpec {
  const CarSpec({
    required this.id,
    required this.carId,
    required this.label,
    required this.value,
    this.position = 0,
  });

  final String id;
  final String carId;
  final String label;
  final String value;

  /// Manual sort order within a car's spec list; lower comes first.
  final int position;

  factory CarSpec.fromMap(Map<String, dynamic> map) {
    return CarSpec(
      id: map['id'] as String,
      carId: map['car_id'] as String,
      label: map['label'] as String,
      value: map['value'] as String,
      position: (map['position'] as int?) ?? 0,
    );
  }
}
