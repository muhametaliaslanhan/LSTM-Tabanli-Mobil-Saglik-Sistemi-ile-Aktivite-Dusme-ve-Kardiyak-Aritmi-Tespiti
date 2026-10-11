// lib/utils/heart_rate_thresholds.dart
import '../models/user_profile.dart';

class HeartRateThresholds {
  final int restingMin;
  final int restingMax;
  final int walkingMax;
  final int runningMax;
  final int criticalMax;
  final int criticalMin;

  const HeartRateThresholds({
    required this.restingMin,
    required this.restingMax,
    required this.walkingMax,
    required this.runningMax,
    required this.criticalMax,
    required this.criticalMin,
  });

  /// Aktivite etiketine göre max izin verilen nabız
  int maxForActivity(String activityLabel) {
    final label = activityLabel.toLowerCase();
    if (label.contains('running') || label.contains('koş')) return runningMax;
    if (label.contains('walking') || label.contains('yürü')) return walkingMax;
    if (label.contains('sitting') || label.contains('otur') ||
        label.contains('lying') || label.contains('yat')) return restingMax;
    if (label.contains('standing') || label.contains('ayak')) return walkingMax;
    return walkingMax; // varsayılan
  }

  bool isAnomalous(int heartRate, String activityLabel) {
    if (heartRate < criticalMin) return true;
    if (heartRate > criticalMax) return true;
    return heartRate > maxForActivity(activityLabel);
  }
}

/// Yaş, kronik hastalık ve aktiviteye göre dinamik eşik hesapla
HeartRateThresholds computeThresholds(UserProfile profile) {
  final age = profile.age.clamp(10, 100);
  final hasHypertension = profile.chronicConditions
      .any((c) => c.toLowerCase().contains('hipertansiyon') ||
          c.toLowerCase().contains('hypertension'));
  final hasDiabetes = profile.chronicConditions
      .any((c) => c.toLowerCase().contains('diyabet') ||
          c.toLowerCase().contains('diabetes'));
  final hasHeartDisease = profile.chronicConditions
      .any((c) => c.toLowerCase().contains('kalp') ||
          c.toLowerCase().contains('heart'));

  // Maksimum kalp atış hızı tahmini (220 - yaş formülü)
  final hrMax = (220 - age);

  // Kronik hastalıklara göre düşürme
  int adjustment = 0;
  if (hasHypertension) adjustment -= 10;
  if (hasDiabetes) adjustment -= 5;
  if (hasHeartDisease) adjustment -= 15;

  return HeartRateThresholds(
    restingMin: 45,
    restingMax: hasHypertension ? 85 : 100,
    walkingMax: ((hrMax * 0.6) + adjustment).round(),
    runningMax: ((hrMax * 0.85) + adjustment).round(),
    criticalMax: ((hrMax * 0.95) + adjustment).clamp(140, 220).round(),
    criticalMin: 40,
  );
}
