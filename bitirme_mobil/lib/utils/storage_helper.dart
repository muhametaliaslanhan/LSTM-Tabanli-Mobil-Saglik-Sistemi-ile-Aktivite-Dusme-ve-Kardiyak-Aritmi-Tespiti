// lib/utils/storage_helper.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_profile.dart';
import '../models/emergency_contact.dart';
import '../models/sensor_data.dart';

class StorageHelper {
  static const _keyProfile = 'user_profile';
  static const _keyContacts = 'emergency_contacts';
  static const _keyEvents = 'anomaly_events';
  static const _keyMonitoring = 'monitoring_active';
  static const _keyUserId = 'user_id';
  static const _keyMyPhone = 'my_phone_number'; // Kullanıcının kendi numarası

  // --- Kullanıcı Kimliği ---
  /// İlk çağrıda rastgele bir ID oluşturur ve kaydeder; sonraki çağrılarda aynı ID'yi döner.
  static Future<String> getOrCreateUserId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_keyUserId);
    if (existing != null && existing.isNotEmpty) return existing;
    // Basit UUID: timestamp + rastgele sayı
    final newId = 'user_${DateTime.now().millisecondsSinceEpoch}';
    await prefs.setString(_keyUserId, newId);
    return newId;
  }

  // --- Profil ---
  static Future<void> saveProfile(UserProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyProfile, jsonEncode(profile.toJson()));
  }

  static Future<UserProfile> loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyProfile);
    if (raw == null) return UserProfile();
    return UserProfile.fromJson(jsonDecode(raw));
  }

  // --- Acil Kişiler ---
  static Future<void> saveContacts(List<EmergencyContact> contacts) async {
    final prefs = await SharedPreferences.getInstance();
    final list = contacts.map((c) => jsonEncode(c.toJson())).toList();
    await prefs.setStringList(_keyContacts, list);
  }

  static Future<List<EmergencyContact>> loadContacts() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_keyContacts) ?? [];
    return list.map((s) => EmergencyContact.fromJson(jsonDecode(s))).toList();
  }

  // --- Anomali Olayları ---
  static Future<void> saveEvent(AnomalyEvent event) async {
    final prefs = await SharedPreferences.getInstance();
    final events = prefs.getStringList(_keyEvents) ?? [];
    events.insert(0, jsonEncode({
      'timestamp': event.timestamp.toIso8601String(),
      'type': event.type.name,
      'description': event.description,
      'confidence': event.confidence,
      'latitude': event.latitude,
      'longitude': event.longitude,
    }));
    // Maksimum 100 olay sakla
    if (events.length > 100) events.removeLast();
    await prefs.setStringList(_keyEvents, events);
  }

  static Future<void> saveEvents(List<AnomalyEvent> eventsList) async {
    final prefs = await SharedPreferences.getInstance();
    final list = eventsList.map((event) => jsonEncode({
      'timestamp': event.timestamp.toIso8601String(),
      'type': event.type.name,
      'description': event.description,
      'confidence': event.confidence,
      'latitude': event.latitude,
      'longitude': event.longitude,
    })).toList();
    await prefs.setStringList(_keyEvents, list);
  }

  static Future<List<AnomalyEvent>> loadEvents() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_keyEvents) ?? [];
    return list.map((s) {
      final m = jsonDecode(s) as Map<String, dynamic>;
      return AnomalyEvent(
        timestamp: DateTime.parse(m['timestamp']),
        type: AnomalyType.values.firstWhere(
          (t) => t.name == m['type'],
          orElse: () => AnomalyType.impact,
        ),
        description: m['description'] ?? '',
        confidence: m['confidence']?.toDouble(),
        latitude: m['latitude']?.toDouble(),
        longitude: m['longitude']?.toDouble(),
      );
    }).toList();
  }

  // --- İzleme durumu ---
  static Future<void> setMonitoringActive(bool active) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyMonitoring, active);
  }

  static Future<bool> isMonitoringActive() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyMonitoring) ?? false;
  }

  // --- Kendi Telefon Numaram (Bildirim Filtresi) ---
  static Future<void> saveMyPhone(String phone) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyMyPhone, phone.trim());
  }

  static Future<String> getMyPhone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyMyPhone) ?? '';
  }
}
