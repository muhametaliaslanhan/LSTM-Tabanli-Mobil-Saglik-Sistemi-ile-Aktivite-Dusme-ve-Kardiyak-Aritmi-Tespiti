// lib/services/background_task_handler.dart
//
// ARKA PLAN TASK HANDLER
//
// Kurallar:
//  1. Normal durumda bildirim HİÇBİR ZAMAN güncellenmez → spam yok.
//  2. Sadece anomali anında bildirim güncellenir + launchApp() tetiklenir.
//  3. 180 saniyelik cooldown ile tekrar tetiklenme engellenir.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'monitoring_controller.dart';

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(MyTaskHandler());
}

class MyTaskHandler extends TaskHandler {
  MonitoringController? _controller;

  StreamSubscription<int>? _hrSub;
  int _lastHeartRate = 0;
  bool _emergencyTriggeredInBackground = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('[TaskHandler] onStart() - Background service başlatıldı.');

    // ── Bildirim sadece 1 kez, başlangıçta oluşturulur ─────────────────
    // Sonraki onRepeatEvent'lerde normal durumda ASLA güncellenmez.
    // Bu sayede her nabız güncellemesinde bildirim spam'i olmaz.
    FlutterForegroundTask.updateService(
      notificationTitle: 'VitalGuard Arka Planda Çalışıyor',
      notificationText: 'Sağlık izleme aktif — Sizi Koruyor',
    );

    _controller = MonitoringController();
    await _controller!.init();

    // BLE nabız stream — UI'dan bağımsız, arka planda canlı kalır
    _hrSub = _controller!.bleService.heartRateStream.listen((hr) {
      _lastHeartRate = hr;
    });

    _emergencyTriggeredInBackground = false;
  }

  @override
  Future<void> onRepeatEvent(DateTime timestamp) async {
    // ── SPAM KORUMASI: Normal durumda updateService() ÇAĞIRMA ─────────
    // Sadece eşik aşılırsa aşağıdaki blok çalışır.
    if (_controller == null || _lastHeartRate == 0) return;
    if (_emergencyTriggeredInBackground) return;

    // Profil bazlı kritik nabız eşiği
    final profile = _controller!.profile;
    final criticalHr = (profile.age < 50) ? 150 : 140;

    if (_lastHeartRate >= criticalHr) {
      _emergencyTriggeredInBackground = true;

      debugPrint(
          '[TaskHandler] ⚠️ Kritik nabız arka planda: $_lastHeartRate bpm >= $criticalHr');

      // ── 0. Telefon numarası filtresi ──────────────────────────────────────────────
      // Diğer kullanıcıların anomali bildirimini almamaları için:
      // Firebase'deki recipientPhone, cihazda kaydedilen kendi numaramla eşleşiyorsa bildir.
      // Numara kaydedilmemişse (demo modu) filtreleme atlanır.
      final prefs = await SharedPreferences.getInstance();
      final myPhone = (prefs.getString('my_phone_number') ?? '').replaceAll(RegExp(r'[^\d+]'), '').trim();
      // Not: Arka planda recipientPhone'u Firebase'den çekmek yerine
      // yerel olarak FiltreSiz bırakıyoruz (arka plan izolate'i). 
      // Filtre emergency_chat_screen'deki StreamBuilder'da UI tarafında çalışır.
      // Buraya numara kaydedilmişse sadece log at, bildirimi her zaman tetikle.
      if (myPhone.isNotEmpty) {
        debugPrint('[TaskHandler] Bildirim filtresi: myPhone=$myPhone (UI tarafında filtrelenir)');
      }

      // ── 1. Bildirim: yüksek öncelikli, kullanıcıyı uyandır ────────────
      // Bu TEK güncelleme: sadece anomali anında yapılır.
      FlutterForegroundTask.updateService(
        notificationTitle: '🚨 VitalGuard — ACİL DURUM',
        notificationText:
            'Kritik nabız: $_lastHeartRate bpm! Açmak için dokun.',
      );

      // Full-Screen Intent Local Notification fırlat (Kilit ekranını delip geçmek için):
      try {
        final flnp = FlutterLocalNotificationsPlugin();
        await flnp.initialize(const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ));
        const androidDetails = AndroidNotificationDetails(
          'emergency_channel_id',
          'Acil Durum Bildirimleri',
          channelDescription: 'Kritik durumlarda ekranı uyandıran bildirim kanalı',
          importance: Importance.max,
          priority: Priority.high,
          fullScreenIntent: true,
          ticker: 'ticker',
          playSound: true,
          enableVibration: true,
          channelShowBadge: true,
        );
        const notifDetails = NotificationDetails(android: androidDetails);
        await flnp.show(
          999,
          '\u{1F6A8} VitalGuard \u2014 AC\u0130L DURUM',
          'Kritik nabız: $_lastHeartRate bpm! Açmak için dokun.',
          notifDetails,
        );
      } catch (e) {
        debugPrint('[TaskHandler] Local Notification Error: $e');
      }

      // ── 2. Uygulamayı ZORLA ön plana getir ────────────────────────────
      // launchApp(): telefon kilitli veya başka uygulama açık olsa bile
      // VitalGuard'ı Intent ile foreground'a çeker.
      // AndroidManifest'te USE_FULL_SCREEN_INTENT + SYSTEM_ALERT_WINDOW
      // izinleri ile kilitli ekranda da çalışır.
      FlutterForegroundTask.launchApp();

      // ── 3. UI thread'e sinyal gönder ──────────────────────────────────
      // home_screen.dart'taki receivePort bu mesajı alır,
      // EmergencyAlertDialog veya EmergencyChatScreen'i açar.
      FlutterForegroundTask.sendDataToMain({
        'type': 'background_emergency',
        'heartRate': _lastHeartRate,
        'timestamp': timestamp.toIso8601String(),
      });

      // ── 4. 180 saniyelik cooldown ──────────────────────────────────────
      Future.delayed(const Duration(seconds: 180), () {
        _emergencyTriggeredInBackground = false;
        // Cooldown sonrası bildirimi sessiz haline döndür
        FlutterForegroundTask.updateService(
          notificationTitle: 'VitalGuard Arka Planda Çalışıyor',
          notificationText: 'Sağlık izleme aktif — Sizi Koruyor',
        );
      });
    }
    // NOT: else bloğu YOK — normal durumda updateService() HİÇ çağrılmaz.
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    debugPrint('[TaskHandler] onDestroy() - Background service durduruldu.');
    await _hrSub?.cancel();
    _hrSub = null;
    await _controller?.stopMonitoring();
  }

  @override
  void onNotificationButtonPressed(String id) {
    debugPrint('[TaskHandler] onNotificationButtonPressed() - id: $id');
  }

  @override
  void onNotificationPressed() {
    debugPrint('[TaskHandler] onNotificationPressed()');
    FlutterForegroundTask.launchApp();
  }
}