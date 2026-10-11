// lib/services/firebase_service.dart
//
// FIREBASE GERÇEK ZAMANLI VERİTABANI SERVİSİ
//
// Görevler:
//  1. Acil durum tetiklenince emergency_chat_screen açılır →
//     writeEmergencyData() ile konum + ses kaydı yolunu DB'ye yazar.
//  2. Karşı tarafın uygulaması watchEmergency() stream'ini dinler,
//     yeni veri geldiğinde chat ekranında gösterir (StreamBuilder).
//  3. Kırmızı çizgiler: record: 4.4.4 ve FlutterBluePlus.systemDevices([]) değiştirilmez.

import 'dart:io';
import 'dart:convert';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

class FirebaseService {
  static final FirebaseService _instance = FirebaseService._();
  factory FirebaseService() => _instance;
  FirebaseService._();

  final FirebaseDatabase _db = FirebaseDatabase.instance;

  // ── VERİ YAZMA ──────────────────────────────────────────────────────────────
  /// emergency_chat_screen açıldığı anda çağrılır.
  Future<void> writeEmergencyData({
    required String userId,
    required double lat,
    required double lng,
    required String type,
    required String recipient,
    required String recipientPhone, // Filtre için altanın telefon numarası
    String? voiceNoteUrl,
  }) async {
    try {
      String base64Audio = '';
      if (voiceNoteUrl != null && voiceNoteUrl.isNotEmpty) {
        // record.stop() diske yazmayı bitirmeden dosyayı okuma riskini önlemek
        // için 500ms bekle, sonra async exists() ile varlık ve boyut kontrolü yap.
        await Future.delayed(const Duration(milliseconds: 500));
        final file = File(voiceNoteUrl);
        if (await file.exists()) {
          final fileSize = await file.length();
          if (fileSize > 0) {
            final bytes = await file.readAsBytes();
            base64Audio = base64Encode(bytes);
            debugPrint('[Firebase] Ses dosyası okundu: $fileSize byte → Base64 uzunluk: ${base64Audio.length}');
          } else {
            // Dosya henüz tam yazılmamış olabilir; 800ms daha bekle ve tekrar dene
            await Future.delayed(const Duration(milliseconds: 800));
            if (await file.exists() && await file.length() > 0) {
              final bytes = await file.readAsBytes();
              base64Audio = base64Encode(bytes);
              debugPrint('[Firebase] (Retry) Ses dosyası okundu → Base64 uzunluk: ${base64Audio.length}');
            } else {
              debugPrint('[Firebase] ⚠️ Ses dosyası boş veya bulunamadı: $voiceNoteUrl');
            }
          }
        } else {
          debugPrint('[Firebase] ⚠️ Ses dosyası yok: $voiceNoteUrl');
        }
      }

      final ref = _db.ref('emergencies/$userId');
      await ref.set({
        'lat': lat,
        'lng': lng,
        'type': type,
        'recipient': recipient,
        'recipientPhone': recipientPhone,
        'voiceNoteBase64': base64Audio,
        'timestamp': ServerValue.timestamp,
        'status': 'active',
      });
      debugPrint('[Firebase] Acil durum verisi yazıldı (Base64 Ses) → emergencies/$userId');
    } catch (e) {
      debugPrint('[Firebase] Yazma hatası: $e');
    }
  }

  // ── VERİ DİNLEME ────────────────────────────────────────────────────────────
  /// Belirli bir userId'nin acil durum verisini gerçek zamanlı dinler.
  Stream<EmergencySnapshot?> watchEmergency(String userId) {
    final ref = _db.ref('emergencies/$userId');
    return ref.onValue.map((event) {
      final data = event.snapshot.value;
      if (data == null || data is! Map) return null;
      final map = Map<String, dynamic>.from(data as Map);
      return EmergencySnapshot(
        lat: (map['lat'] as num?)?.toDouble() ?? 0.0,
        lng: (map['lng'] as num?)?.toDouble() ?? 0.0,
        type: map['type'] as String? ?? 'UNKNOWN',
        recipient: map['recipient'] as String? ?? 'Bilinmiyor',
        recipientPhone: map['recipientPhone'] as String? ?? '',
        voiceNoteBase64: map['voiceNoteBase64'] as String? ?? '',
        timestamp: map['timestamp'] is int
            ? DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int)
            : DateTime.now(),
        status: map['status'] as String? ?? 'active',
      );
    });
  }

  // ── DURUMU GÜNCELLE ─────────────────────────────────────────────────────────
  /// Acil durum tamamlandığında veya reddedildiğinde status'ü günceller.
  Future<void> updateStatus(String userId, String status) async {
    try {
      await _db.ref('emergencies/$userId/status').set(status);
    } catch (e) {
      debugPrint('[Firebase] Durum güncelleme hatası: $e');
    }
  }

  // ── TEMİZLE ─────────────────────────────────────────────────────────────────
  /// Eski acil durum kaydını siler.
  Future<void> clearEmergency(String userId) async {
    try {
      await _db.ref('emergencies/$userId').remove();
    } catch (e) {
      debugPrint('[Firebase] Silme hatası: $e');
    }
  }
}

// ── Snapshot Modeli ──────────────────────────────────────────────────────────
class EmergencySnapshot {
  final double lat;
  final double lng;
  final String type;
  final String recipient;
  final String recipientPhone;
  final String voiceNoteBase64;
  final DateTime timestamp;
  final String status;

  const EmergencySnapshot({
    required this.lat,
    required this.lng,
    required this.type,
    required this.recipient,
    required this.recipientPhone,
    required this.voiceNoteBase64,
    required this.timestamp,
    required this.status,
  });
}
