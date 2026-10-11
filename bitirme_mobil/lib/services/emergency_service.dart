// lib/services/emergency_service.dart
//
// ACİL DURUM PROTOKOLÜ — Kesin İş Akışı:
//
//  triggerEmergency() çağrıldığında:
//  ┌─────────────────────────────────────────────────────────────┐
//  │  ADIM 1 — Konum al (max 8 sn)                              │
//  │  ADIM 2 — Arka planda GİZLİ SMS gönder (telephony)         │
//  │           "🚨 VITALGUARD ACİL DURUM! ... Konum: {url}"      │
//  │  ADIM 3 — Arama başlat (flutter_phone_direct_caller)        │
//  │                                                             │
//  ⚠ WhatsApp / share_plus / url_launcher yönlendirmesi YOK.    │
//  ⚠ Ses kaydı sadece cihazda (kara kutu). Hiçbir yere gönderilmez.│
//  └─────────────────────────────────────────────────────────────┘
//
import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:telephony/telephony.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/emergency_contact.dart';
import '../models/sensor_data.dart';

class EmergencyService {
  static final EmergencyService _instance = EmergencyService._();
  factory EmergencyService() => _instance;
  EmergencyService._();

  final Telephony _telephony = Telephony.instance;

  // ─────────────────────────────────────────────────────────────
  //  ANA PROTOKOL — ADIM 1 → 2 → 3 (sıralı)
  // ─────────────────────────────────────────────────────────────

  Future<void> triggerEmergency({
    required List<EmergencyContact> contacts,
    required AnomalyEvent event,
    String? audioRecordPath, // Kara kutu: sadece cihazda, hiçbir yere gönderilmez
  }) async {
    if (contacts.isEmpty) return;

    final primaryContact = contacts.firstWhere(
      (c) => c.isPrimaryCaller == true,
      orElse: () => contacts.first,
    );
    final primaryPhone = _cleanPhone(primaryContact.phone);

    // ── ADIM 1: Konum al ─────────────────────────────────────
    final locationUrl = await _fetchLocationUrl();

    // ── ADIM 2: Arka planda gizli SMS gönder ─────────────────
    final smsText =
        '🚨 VITALGUARD ACİL DURUM! Kaza/Anomali algılandı. '
        'Konum: $locationUrl';
    await _sendSilentSms(primaryPhone, smsText);

    // ── ADIM 3: Otomatik arama (SMS fırlatıldıktan hemen sonra) ─
    if (primaryPhone.isNotEmpty) {
      await _directCall(primaryPhone);
    }
  }

  // ─────────────────────────────────────────────────────────────
  //  ADIM 1 — KONUM
  // ─────────────────────────────────────────────────────────────

  Future<String> _fetchLocationUrl() async {
    try {
      final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      final LocationPermission permission = await Geolocator.checkPermission();

      if (!serviceEnabled ||
          (permission != LocationPermission.always &&
              permission != LocationPermission.whileInUse)) {
        return 'Konum alınamadı (izin yok)';
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );

      final lat = pos.latitude.toStringAsFixed(6);
      final lng = pos.longitude.toStringAsFixed(6);
      return 'https://maps.google.com/?q=$lat,$lng';
    } catch (_) {
      return 'Konum alınamadı';
    }
  }

  // ─────────────────────────────────────────────────────────────
  //  ADIM 2 — GİZLİ SMS (telephony — kullanıcı müdahalesi yok)
  // ─────────────────────────────────────────────────────────────

  Future<void> _sendSilentSms(String phone, String message) async {
    if (phone.isEmpty) return;

    // İzin kontrolü
    if (!await Permission.sms.isGranted) {
      await Permission.sms.request();
    }
    if (!await Permission.sms.isGranted) {
      debugPrint('[EmergencyService] SEND_SMS izni yok, SMS atlanıyor.');
      return;
    }

    try {
      final completer = Completer<void>();

      _telephony.sendSms(
        to: phone,
        message: message,
        statusListener: (SendStatus status) {
          if (!completer.isCompleted &&
              (status == SendStatus.SENT ||
                  status == SendStatus.DELIVERED)) {
            debugPrint('[EmergencyService] SMS gönderildi → $phone');
            completer.complete();
          }
        },
      );

      // En fazla 5 saniye bekle, sonra devam et (aramayı bloklamayalım)
      await Future.any([
        completer.future,
        Future.delayed(const Duration(seconds: 5)),
      ]);
    } catch (e) {
      debugPrint('[EmergencyService] telephony SMS hatası: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────
  //  ADIM 3 — OTOMATİK ARAMA
  // ─────────────────────────────────────────────────────────────

  Future<void> _directCall(String phone) async {
    try {
      await FlutterPhoneDirectCaller.callNumber(phone);
    } catch (e) {
      debugPrint('[EmergencyService] Arama hatası: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────
  //  YARDIMCI
  // ─────────────────────────────────────────────────────────────

  String _cleanPhone(String raw) =>
      raw.replaceAll(RegExp(r'[^\d+]'), '').trim();

  /// Profil/harita ekranları için public konum yardımcısı
  Future<String> getCurrentLocationUrl() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 5),
        ),
      );
      return 'https://maps.google.com/?q=${pos.latitude},${pos.longitude}';
    } catch (_) {
      return '';
    }
  }
}
