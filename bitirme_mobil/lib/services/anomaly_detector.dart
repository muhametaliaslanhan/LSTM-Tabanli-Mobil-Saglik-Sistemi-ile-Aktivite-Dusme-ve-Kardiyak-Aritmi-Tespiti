// lib/services/anomaly_detector.dart
import 'dart:async';
import 'dart:math';
import '../models/sensor_data.dart';
import '../models/user_profile.dart';
import '../utils/heart_rate_thresholds.dart';
import 'ai_service.dart';

typedef AnomalyCallback = void Function(AnomalyEvent event);

/// ─────────────────────────────────────────────
///  Heuristic Pre-Processing — Yalancı Kaza Filtresi
/// ─────────────────────────────────────────────
///
/// Gerçek Düşme:    [hareket] → [ani darbe ~35g+] → [1.5s+ hareketsizlik]
/// Yalancı Kaza:   [hareket] → [ani darbe]       → [< 1.5s'de stabilite]  → IGNORE
/// Zıplama:        model 'Jumping' döndürmeli                               → IGNORE
/// Telefon Fırlatma: [düşük aktivite] → [ani darbe] → [hemen stabilite]   → IGNORE
///
class AnomalyDetector {
  final AiService _ai;
  final AnomalyCallback onAnomaly;

  // Sensör penceresi (LSTM için son 128 okuma)
  final List<SensorData> _window = [];
  static const int _windowSize = 128;

  // ── Düşme Durum Makinesi ──────────────────────────────
  DateTime? _impactTime;
  bool _immobilityConfirmed = false;

  /// Pre-impact varyans: Darbe anında hareket halinde miydik?
  double _preImpactVariance = 0.0;

  /// Post-impact ilk 1.5 saniyeyi izle: Hemen stabilleştiyse → yalancı kaza
  bool _waitingForRecoveryCheck = false;

  // ── Nabız Anomalisi ───────────────────────────────────
  int _consecutiveHrAnomalies = 0;
  static const int _hrAnomalyThreshold = 5;

  // ── Aktivite ─────────────────────────────────────────
  String _currentActivity = 'Unknown';
  DateTime _lastAiRun = DateTime.fromMillisecondsSinceEpoch(0);

  // Debounce
  String? _persistentActivity;
  DateTime? _activityStartTime;

  // Mevcut nabız
  int _currentHr = 0;

  UserProfile _profile;
  late HeartRateThresholds _thresholds;

  bool _alertCooldown = false;
  Timer? _cooldownTimer;

  AnomalyDetector({
    required AiService ai,
    required UserProfile profile,
    required this.onAnomaly,
  })  : _ai = ai,
        _profile = profile {
    _thresholds = computeThresholds(profile);
  }

  void updateProfile(UserProfile profile) {
    _profile = profile;
    _thresholds = computeThresholds(profile);
  }

  void updateHeartRate(int hr) {
    _currentHr = hr;
    _checkHeartRateAnomaly(hr);
  }

  void processSensorData(SensorData data) {
    _window.add(data);
    if (_window.length > _windowSize) _window.removeAt(0);

    // AI sınıflandırma — 1 saniyede bir (performans)
    final now = DateTime.now();
    if (now.difference(_lastAiRun).inMilliseconds > 1000 &&
        _window.length >= 20) {
      _lastAiRun = now;
      final result = _ai.classifyActivity(_window);
      _currentActivity = result.label;
      _checkFallLogic(data, result);
    } else {
      // AI çalışmadığı anlarda ham sensör heuristiği
      _checkImpactHeuristic(data);
    }
  }

  // ─────────────────────────────────────────────────────────
  //  NABIZ ANOMALİSİ
  // ─────────────────────────────────────────────────────────
  void _checkHeartRateAnomaly(int hr) {
    if (_thresholds.isAnomalous(hr, _currentActivity)) {
      _consecutiveHrAnomalies++;
      if (_consecutiveHrAnomalies >= _hrAnomalyThreshold) {
        _triggerAnomaly(AnomalyEvent(
          timestamp: DateTime.now(),
          type: AnomalyType.heartRateAnomaly,
          description:
              'Nabız anomalisi: $hr bpm (Aktivite: $_currentActivity)',
          confidence: 0.9,
        ));
        _consecutiveHrAnomalies = 0;
      }
    } else {
      _consecutiveHrAnomalies = 0;
    }
  }

  // ─────────────────────────────────────────────────────────
  //  DÜŞME MANTIĞI — Gelişmiş Heuristic Filter
  // ─────────────────────────────────────────────────────────
  void _checkFallLogic(SensorData data, ActivityResult result) {
    // ── 1. Yanlış Pozitif Filtresi (Yüksek eforlu aktiviteler) ──
    // MHEALTH modeline göre bu hareketlerde yüksek sarsıntı normaldir.
    final falsePositiveActivities = [
      'Jump Front & Back',
      'Jogging',
      'Running',
      'Cycling',
    ];

    if (falsePositiveActivities.contains(result.label)) {
      _resetImpactState();
      return;
    }

    // ── 2. Debounce: Aktivite 3 saniye boyunca aynı mı? ─────
    if (_persistentActivity != result.label) {
      _persistentActivity = result.label;
      _activityStartTime = DateTime.now();
    }

    // ── 3. Impact + hareketsizlik heuristiği ─────────────────
    // isFallRelated artık her zaman false dönüyor, modelden gelmiyor.
    // Düşme kararı sadece _checkImpactHeuristic içinden impactTime tetiklenirse yapılır.
    if (_impactTime == null) {
        return; // Darbe yoksa bekle
    }
      final timeSinceImpact = DateTime.now().difference(_impactTime!);

      // ── 4a. İlk 1.5 saniye — Yalancı Kaza Recovery Check ──
      if (_waitingForRecoveryCheck &&
          timeSinceImpact.inMilliseconds <= 1500) {
        final currentVariance = _computeVariance(lookback: 5);
        // Hemen stabilleşti → YALANCI KAZA → sıfırla (Tolerans düşürüldü: daha zor sıfırlansın)
        if (currentVariance < 0.10) {
          _resetImpactState();
          return;
        }
      }

      // ── 4b. 1.5 – 10 saniye arası — Gerçek Düşme Kontrolü ─
      if (timeSinceImpact.inMilliseconds > 1500 &&
          timeSinceImpact.inSeconds <= 10) {
        _waitingForRecoveryCheck = false;

        // Hareketsizlik teyidi (Tolerans artırıldı: ufak sarsıntılar hareketsizlik sayılır)
        final isImmobile =
            result.isLowActivity || _computeVariance(lookback: 10) < 1.5;

        if (isImmobile && !_immobilityConfirmed) {
          _immobilityConfirmed = true;

          // Yüksek pre-impact varyans + hızlı iyileşme = daha düşük güven
          final double confidenceAdjustment =
              _preImpactVariance > 3.0 ? -0.08 : 0.0;

          _triggerAnomaly(AnomalyEvent(
            timestamp: DateTime.now(),
            type: AnomalyType.fall,
            description:
                'Düşme tespiti: Ani darbe + ${timeSinceImpact.inSeconds}s hareketsizlik',
            confidence: (0.78 + confidenceAdjustment).clamp(0.5, 1.0),
          ));
        }
      } else if (timeSinceImpact.inSeconds > 10) {
        // Süre doldu, hareketsizlik gelmedi → yalancı kaza
        _resetImpactState();
      }
  }

  // ─────────────────────────────────────────────────────────
  //  HAM SENSÖR HEURİSTİĞİ (AI çalışmayan anlarda)
  // ─────────────────────────────────────────────────────────
  void _checkImpactHeuristic(SensorData data) {
    final mag = sqrt(
        data.accX * data.accX + data.accY * data.accY + data.accZ * data.accZ);

    // Eşik düşürüldü: 38g → 25g (daha hassas düşme algılama)
    if (mag > 25 && _impactTime == null) {
      _preImpactVariance = _computeVariance(lookback: 15);
      _impactTime = DateTime.now();
      _waitingForRecoveryCheck = true;
      _immobilityConfirmed = false;
    }
  }

  // ─────────────────────────────────────────────────────────
  //  YARDIMCI METODLAR
  // ─────────────────────────────────────────────────────────

  /// Son [lookback] okumada ivmeölçer varyansını hesapla
  double _computeVariance({int lookback = 10}) {
    if (_window.length < 3) return 999;
    final count = lookback.clamp(3, _window.length);
    final recent = _window.sublist(_window.length - count);
    final mags = recent.map((d) =>
        sqrt(d.accX * d.accX + d.accY * d.accY + d.accZ * d.accZ)).toList();
    final avg = mags.reduce((a, b) => a + b) / mags.length;
    return mags.map((m) => (m - avg) * (m - avg)).reduce((a, b) => a + b) /
        mags.length;
  }

  void _resetImpactState() {
    _impactTime = null;
    _immobilityConfirmed = false;
    _waitingForRecoveryCheck = false;
    _preImpactVariance = 0.0;
  }

  void _triggerAnomaly(AnomalyEvent event) {
    if (_alertCooldown) return;
    _alertCooldown = true;
    onAnomaly(event);
    // 60 saniye cooldown — art arda alarm önleme
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer(const Duration(seconds: 60), () {
      _alertCooldown = false;
    });
  }

  String get currentActivity => _currentActivity;
  int get currentHeartRate => _currentHr;

  void dispose() {
    _cooldownTimer?.cancel();
  }
}
