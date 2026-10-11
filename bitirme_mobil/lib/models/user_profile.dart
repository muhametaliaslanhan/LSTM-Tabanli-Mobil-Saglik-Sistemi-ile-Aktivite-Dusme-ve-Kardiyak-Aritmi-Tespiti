// lib/models/user_profile.dart
class UserProfile {
  String name;
  int age;
  double weightKg;
  double heightCm;
  List<String> chronicConditions;
  String? avatarPath;

  UserProfile({
    this.name = '',
    this.age = 30,
    this.weightKg = 70,
    this.heightCm = 170,
    List<String>? chronicConditions,
    this.avatarPath,
  }) : chronicConditions = chronicConditions ?? [];

  double get bmi => weightKg / ((heightCm / 100) * (heightCm / 100));

  Map<String, dynamic> toJson() => {
        'name': name,
        'age': age,
        'weightKg': weightKg,
        'heightCm': heightCm,
        'chronicConditions': chronicConditions,
        'avatarPath': avatarPath,
      };

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        name: json['name'] ?? '',
        age: json['age'] ?? 30,
        weightKg: (json['weightKg'] ?? 70).toDouble(),
        heightCm: (json['heightCm'] ?? 170).toDouble(),
        chronicConditions: List<String>.from(json['chronicConditions'] ?? []),
        avatarPath: json['avatarPath'],
      );
}
