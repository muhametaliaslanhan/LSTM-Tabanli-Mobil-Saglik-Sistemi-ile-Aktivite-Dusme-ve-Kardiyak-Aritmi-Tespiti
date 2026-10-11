// lib/models/emergency_contact.dart
class EmergencyContact {
  String id;
  String name;
  String phone;
  String relation;
  bool isPrimaryCaller;

  EmergencyContact({
    required this.id,
    required this.name,
    required this.phone,
    this.relation = '',
    this.isPrimaryCaller = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phone': phone,
        'relation': relation,
        'isPrimaryCaller': isPrimaryCaller,
      };

  factory EmergencyContact.fromJson(Map<String, dynamic> json) =>
      EmergencyContact(
        id: json['id'] ?? '',
        name: json['name'] ?? '',
        phone: json['phone'] ?? '',
        relation: json['relation'] ?? '',
        isPrimaryCaller: json['isPrimaryCaller'] ?? false,
      );
}
