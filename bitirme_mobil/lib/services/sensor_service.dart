// lib/services/sensor_service.dart
import 'dart:async';
import 'dart:math';
import 'package:sensors_plus/sensors_plus.dart';
import '../models/sensor_data.dart';

class SensorService {
  StreamSubscription<AccelerometerEvent>? _accSub;
  StreamSubscription<GyroscopeEvent>? _gyroSub;

  double _accX = 0, _accY = 0, _accZ = 0;
  double _gyroX = 0, _gyroY = 0, _gyroZ = 0;

  final _controller = StreamController<SensorData>.broadcast();
  Stream<SensorData> get stream => _controller.stream;

  Timer? _emitTimer;

  void start() {
    _accSub = accelerometerEventStream(
      samplingPeriod: SensorInterval.normalInterval,
    ).listen((event) {
      _accX = event.x;
      _accY = event.y;
      _accZ = event.z;
    });

    _gyroSub = gyroscopeEventStream(
      samplingPeriod: SensorInterval.normalInterval,
    ).listen((event) {
      _gyroX = event.x;
      _gyroY = event.y;
      _gyroZ = event.z;
    });

    // 20ms'de bir (50 Hz) sensör verisi yayınla - MHEALTH model standardı
    _emitTimer = Timer.periodic(const Duration(milliseconds: 20), (_) {
      _controller.add(SensorData(
        timestamp: DateTime.now(),
        accX: _accX,
        accY: _accY,
        accZ: _accZ,
        gyroX: _gyroX,
        gyroY: _gyroY,
        gyroZ: _gyroZ,
      ));
    });
  }

  void stop() {
    _accSub?.cancel();
    _gyroSub?.cancel();
    _emitTimer?.cancel();
  }

  void dispose() {
    stop();
    _controller.close();
  }

  /// Ani düşme tespiti için ham ivme büyüklüğü hesapla
  static double computeMagnitude(double x, double y, double z) {
    return sqrt(x * x + y * y + z * z);
  }
}
