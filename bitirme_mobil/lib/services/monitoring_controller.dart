// lib/services/monitoring_controller.dart
// Ana izleme kontrolcüsü - tüm servisleri koordine eder.
// Foreground Service ile iletişim köprüsüdür.
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import '../models/sensor_data.dart';
import '../models/user_profile.dart';
import '../models/emergency_contact.dart';
import '../utils/storage_helper.dart';
import 'sensor_service.dart';
import 'ble_service.dart';
import 'ai_service.dart';
import 'anomaly_detector.dart';
import 'emergency_service.dart';
import 'background_task_handler.dart';

class MonitoringController extends ChangeNotifier {
  static final MonitoringController _instance = MonitoringController._();
  factory MonitoringController() => _instance;
  MonitoringController._();

  final SensorService _sensorService = SensorService();
  final BleService _bleService = BleService();
  final AiService _aiService = AiService();
  final EmergencyService _emergencyService = EmergencyService();

  AnomalyDetector? _detector;
  StreamSubscription<SensorData>? _sensorSub;
  StreamSubscription<int>? _hrSub;
  StreamSubscription<bool>? _watchCancelSub;

  bool _isMonitoring = false;
  bool _modelsLoaded = false;
  bool _isEmergencyMode = false;
  
  // Global Cooldown: 180 saniye
  bool _isCooldownActive = false;
  Timer? _cooldownTimer;

  UserProfile _profile = UserProfile();
  List<EmergencyContact> _contacts = [];
  final List<AnomalyEvent> _eventHistory = [];

  // Gerçek zamanlı veri
  String _currentActivity = 'Bekleniyor...';
  int _currentHeartRate = 0;
  double _currentAccMag = 0;
  BleStatus _bleStatus = BleStatus.ready;
  AnomalyEvent? _latestAnomaly;

  // Getters
  bool get isMonitoring => _isMonitoring;
  bool get modelsLoaded => _modelsLoaded;
  bool get isEmergencyMode => _isEmergencyMode;
  UserProfile get profile => _profile;
  List<EmergencyContact> get contacts => _contacts;
  List<AnomalyEvent> get eventHistory => _eventHistory;
  String get currentActivity => _currentActivity;
  int get currentHeartRate => _currentHeartRate;
  double get currentAccMag => _currentAccMag;
  BleStatus get bleStatus => _bleStatus;
  AnomalyEvent? get latestAnomaly => _latestAnomaly;
  BleService get bleService => _bleService;
  bool get isWatchConnected => _bleService.isConnected;

  Future<void> init() async {
    _profile = await StorageHelper.loadProfile();
    _contacts = await StorageHelper.loadContacts();
    _eventHistory.addAll(await StorageHelper.loadEvents());

    _bleService.init();
    _bleService.statusStream.listen((status) {
      _bleStatus = status;
      notifyListeners();
    });

    await _aiService.loadModels();
    _modelsLoaded = _aiService.isReady;
    notifyListeners();

    // Uygulama açılır açılmaz izlemeyi otomatik başlat
    await startMonitoring();
  }

  Future<void> startMonitoring() async {
    if (_isMonitoring) return;
    _isMonitoring = true;

    _detector = AnomalyDetector(
      ai: _aiService,
      profile: _profile,
      onAnomaly: _handleAnomaly,
    );

    _sensorService.start();
    _sensorSub = _sensorService.stream.listen((data) {
      _currentAccMag = data.accMagnitude;
      _detector?.processSensorData(data);

      // Aktivite güncelle
      final activity = _detector?.currentActivity ?? 'Unknown';
      if (activity != _currentActivity) {
        _currentActivity = activity;
        notifyListeners();
      }
    });

    // BLE nabız (varsa)
    _hrSub = _bleService.heartRateStream.listen((hr) {
      _currentHeartRate = hr;
      _detector?.updateHeartRate(hr);
      notifyListeners();
    });

    // Saatten iptal sinyali dinle
    _watchCancelSub = _bleService.watchCancelStream.listen((cancel) {
      if (cancel && _isEmergencyMode) {
        dismissEmergency();
      }
    });

    // Arka plan servisini başlat
    if (!await FlutterForegroundTask.isRunningService) {
      FlutterForegroundTask.startService(
        notificationTitle: 'VitalGuard Arka Planda Çalışıyor',
        notificationText: 'Sizi Koruyor',
        callback: startCallback,
      );
    }

    await StorageHelper.setMonitoringActive(true);
    notifyListeners();
  }

  Future<void> stopMonitoring() async {
    _isMonitoring = false;
    _sensorSub?.cancel();
    _hrSub?.cancel();
    _watchCancelSub?.cancel();
    _sensorService.stop();
    _detector?.dispose();
    _detector = null;
    
    await FlutterForegroundTask.stopService();
    
    await StorageHelper.setMonitoringActive(false);
    notifyListeners();
  }

  void _startGlobalCooldown() {
    _isCooldownActive = true;
    _cooldownTimer?.cancel();
    // DEMO MODU: 5 saniye cooldown (sunum için)
    _cooldownTimer = Timer(const Duration(seconds: 5), () {
      _isCooldownActive = false;
    });
  }

  void _handleAnomaly(AnomalyEvent event) async {
    if (_isCooldownActive) {
      debugPrint('[Monitoring] Anomali engellendi: Cooldown devrede.');
      return;
    }

    _startGlobalCooldown();
    _latestAnomaly = event;
    _isEmergencyMode = true;
    
    // Saatte Alarm Başlat
    unawaited(_bleService.sendAlarmToWatch(true));

    _eventHistory.insert(0, event);
    await StorageHelper.saveEvent(event);
    // UI'ya bildir — 12 saniyelik geri sayım EmergencyAlertDialog'da yönetilir.
    // Dialog süresi dolarsa triggerEmergencyNow() çağrılır.
    notifyListeners();
  }

  /// Dialog geri sayımı bittikten sonra çağrılır: SMS + arama
  /// UI thread bloklanmaması için emergency protokolü arka planda başlatılır.
  /// NOT: Chat screen latestAnomaly'yi home_screen.dart'ta snapshot aldığı için
  /// burada null'a çekiyoruz — chat screen kendi event kopyasını tutmaktadır.
  Future<void> triggerEmergencyNow({String? audioRecordPath}) async {
    // Snapshot al — async gap'te değişebilir
    final contacts = List.of(_contacts);
    final event = _latestAnomaly;

    // UI'ı hemen güncelle (donma yok)
    // NOT: latestAnomaly'yi hemen null yapmıyoruz; home_screen.dart
    // chat ekranını açarken hâlâ kullanabiliyor. Bir frame sonra temizle.
    _isEmergencyMode = false;
    notifyListeners();

    // Bir frame bekleyip temizle — chat screen push'u tamamlanmış olur
    await Future.delayed(Duration.zero);
    _latestAnomaly = null;
    notifyListeners();

    // SMS + arama arka planda — UI thread'i bloke etme
    if (contacts.isNotEmpty && event != null) {
      scheduleMicrotask(() {
        _emergencyService.triggerEmergency(
          contacts: contacts,
          event: event,
          audioRecordPath: audioRecordPath,
        );
      });
    }
  }

  void dismissEmergency() {
    _isEmergencyMode = false;
    _latestAnomaly = null;
    // Saatte Alarmı Sustur
    unawaited(_bleService.sendAlarmToWatch(false));
    notifyListeners();
  }

  Future<void> saveProfile(UserProfile profile) async {
    _profile = profile;
    _detector?.updateProfile(profile);
    await StorageHelper.saveProfile(profile);
    notifyListeners();
  }

  /// Kişileri kaydet.
  /// Birden fazla "isPrimaryCaller" işaretliyse sadece listedeki
  /// ilk birincil kişi korunur, diğerleri false yapılır.
  Future<void> saveContacts(List<EmergencyContact> contacts) async {
    // Tek birincil kişi zorlaması
    bool foundPrimary = false;
    final normalized = contacts.map((c) {
      if (c.isPrimaryCaller) {
        if (!foundPrimary) {
          foundPrimary = true;
          return c; // ilk birinciliği koru
        } else {
          // Sonraki birincillerin işaretini kaldır
          return EmergencyContact(
            id: c.id,
            name: c.name,
            phone: c.phone,
            relation: c.relation,
            isPrimaryCaller: false,
          );
        }
      }
      return c;
    }).toList();

    _contacts = normalized;
    await StorageHelper.saveContacts(normalized);
    notifyListeners();
  }

  Future<void> clearHistory() async {
    _eventHistory.clear();
    await StorageHelper.saveEvents(_eventHistory);
    notifyListeners();
  }

  Future<void> updateHistory(List<AnomalyEvent> newHistory) async {
    _eventHistory.clear();
    _eventHistory.addAll(newHistory);
    await StorageHelper.saveEvents(_eventHistory);
    notifyListeners();
  }

  @override
  void dispose() {
    stopMonitoring();
    _bleService.dispose();
    _aiService.dispose();
    _sensorService.dispose();
    super.dispose();
  }
}
