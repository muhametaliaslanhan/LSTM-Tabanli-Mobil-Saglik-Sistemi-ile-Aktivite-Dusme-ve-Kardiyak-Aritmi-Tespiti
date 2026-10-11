// lib/models/sensor_data.dart
class SensorData {
  final DateTime timestamp;
  final double accX;
  final double accY;
  final double accZ;
  final double gyroX;
  final double gyroY;
  final double gyroZ;
  final int? heartRate;
  final String? activityLabel;

  const SensorData({
    required this.timestamp,
    required this.accX,
    required this.accY,
    required this.accZ,
    required this.gyroX,
    required this.gyroY,
    required this.gyroZ,
    this.heartRate,
    this.activityLabel,
  });

  double get accMagnitude =>
      (accX * accX + accY * accY + accZ * accZ);

  List<double> toModelInput() =>
      [accX, accY, accZ, gyroX, gyroY, gyroZ];
}

class AnomalyEvent {
  final DateTime timestamp;
  final AnomalyType type;
  final String description;
  final double? confidence;
  final double? latitude;
  final double? longitude;

  const AnomalyEvent({
    required this.timestamp,
    required this.type,
    required this.description,
    this.confidence,
    this.latitude,
    this.longitude,
  });

  String get typeLabel {
    switch (type) {
      case AnomalyType.fall:
        return 'Düşme Tespiti';
      case AnomalyType.heartRateAnomaly:
        return 'Nabız Anomalisi';
      case AnomalyType.impact:
        return 'Ani Darbe';
      case AnomalyType.arrhythmia:
        return 'Aritmi Tespiti';
    }
  }
}

enum AnomalyType { fall, heartRateAnomaly, impact, arrhythmia }
