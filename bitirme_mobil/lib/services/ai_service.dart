// lib/services/ai_service.dart
import 'dart:math';
import 'package:tflite_flutter/tflite_flutter.dart';
import '../models/sensor_data.dart';

/// MHEALTH (12 sınıf) modeli için aktivite etiketleri.
const List<String> activityLabels = [
  'Standing',                  // L1
  'Sitting',                   // L2
  'Lying',                     // L3
  'Walking',                   // L4
  'Climbing Stairs',           // L5
  'Waist Bends Forward',       // L6
  'Frontal Elevation of Arms', // L7
  'Knees Bending',             // L8
  'Cycling',                   // L9
  'Jogging',                   // L10
  'Running',                   // L11
  'Jump Front & Back',         // L12
];

class AiService {
  Interpreter? _activityInterpreter;
  Interpreter? _arrhythmiaInterpreter;

  bool get isReady =>
      _activityInterpreter != null && _arrhythmiaInterpreter != null;

  /// Modelleri yükle
  Future<void> loadModels() async {
    try {
      final opts = InterpreterOptions();
      opts.threads = 2;
      _activityInterpreter = await Interpreter.fromAsset(
        'model.tflite',
        options: opts,
      );
    } catch (e) {
      // TFLite flex delegate uyumsuzluğu durumunda null kalır
      _activityInterpreter = null;
    }

    try {
      final opts2 = InterpreterOptions();
      opts2.threads = 2;
      _arrhythmiaInterpreter = await Interpreter.fromAsset(
        'kalp_aritmi_model_mobil_saf.tflite',
        options: opts2,
      );
    } catch (e) {
      _arrhythmiaInterpreter = null;
    }
  }

  /// Aktivite sınıflandırma: 128 adımlık pencere (128 x 6) döndürür
  /// [windowData]: Son 128 sensör okuması
  ActivityResult classifyActivity(List<SensorData> windowData) {
    if (_activityInterpreter == null || windowData.length < 10) {
      return _heuristicActivity(windowData);
    }

    try {
      final inputShape = _activityInterpreter!.getInputTensor(0).shape;
      final outputShape = _activityInterpreter!.getOutputTensor(0).shape;
      final numClasses = outputShape.last;

      final int seqLen = inputShape[1];
      final int features = inputShape[2];

      // Pencereyi model boyutuna göre doldur/kes (Data Imputation)
      final List<List<List<double>>> input = List.generate(1, (_) =>
        List.generate(seqLen, (i) {
          if (i < windowData.length) {
            final data = windowData[i];
            
            // MHEALTH beklentisi: 23 özellik.
            // 0-2: Telefon Acc (m/s² → g'ye normalize ediyoruz: / 9.81)
            // 3-5: Telefon Gyro
            // 6-22: Eksik sensörler (Göğüs, Sol Ayak vs.) -> 0.0 imputation
            final accX = data.accX / 9.81;
            final accY = data.accY / 9.81;
            final accZ = data.accZ / 9.81;
            
            final row = [accX, accY, accZ, data.gyroX, data.gyroY, data.gyroZ];
            
            // Geri kalan sütunları 0 ile doldur
            if (features > 6) {
              row.addAll(List.filled(features - 6, 0.0));
            }
            return row.take(features).toList();
          }
          return List.filled(features, 0.0);
        })
      );

      final output = List.generate(1, (_) =>
          List<double>.filled(numClasses, 0.0));

      _activityInterpreter!.run(input, output);

      final probs = output[0];
      final maxIdx = probs.indexOf(probs.reduce(max));
      final confidence = probs[maxIdx];

      final label = maxIdx < activityLabels.length
          ? activityLabels[maxIdx]
          : 'Unknown';

      return ActivityResult(
        label: label,
        confidence: confidence,
        probabilities: Map.fromIterables(
          activityLabels.take(probs.length),
          probs,
        ),
      );
    } catch (e) {
      return _heuristicActivity(windowData);
    }
  }

  /// Aritmik nabız tespiti
  bool detectArrhythmia(List<int> rrIntervals) {
    if (_arrhythmiaInterpreter == null || rrIntervals.length < 10) {
      return _heuristicArrhythmia(rrIntervals);
    }

    try {
      final inputShape = _arrhythmiaInterpreter!.getInputTensor(0).shape;
      final seqLen = inputShape[1];

      final input = List.generate(1, (_) =>
        List.generate(seqLen, (i) =>
          [i < rrIntervals.length ? rrIntervals[i].toDouble() : 0.0]
        )
      );

      final output = List.generate(1, (_) => [0.0]);
      _arrhythmiaInterpreter!.run(input, output);

      return output[0][0] > 0.5;
    } catch (e) {
      return _heuristicArrhythmia(rrIntervals);
    }
  }

  /// Model yoksa ivme büyüklüğüne dayalı basit sınıflandırma
  ActivityResult _heuristicActivity(List<SensorData> data) {
    if (data.isEmpty) {
      return ActivityResult(label: 'Unknown', confidence: 0.0);
    }

    final recent = data.length > 20 ? data.sublist(data.length - 20) : data;
    final magnitudes = recent.map((d) =>
        sqrt(d.accX * d.accX + d.accY * d.accY + d.accZ * d.accZ)).toList();
    final avgMag = magnitudes.reduce((a, b) => a + b) / magnitudes.length;
    final maxMag = magnitudes.reduce(max);

    // Ani yüksek ivme → Heuristik impact (artık model label'ı değil)
    if (maxMag > 25) {
      return ActivityResult(label: 'Unknown', confidence: 0.0);
    }
    // Düşük varyans → Oturuyor/Yatıyor
    final variance = magnitudes.map((m) => (m - avgMag) * (m - avgMag))
        .reduce((a, b) => a + b) / magnitudes.length;
    if (variance < 0.3) {
      if (avgMag < 9.5) return ActivityResult(label: 'Lying', confidence: 0.65);
      return ActivityResult(label: 'Sitting', confidence: 0.65);
    }
    if (avgMag > 12) return ActivityResult(label: 'Running', confidence: 0.70);
    return ActivityResult(label: 'Walking', confidence: 0.70);
  }

  /// Model yoksa RR intervali varyasyonuna dayalı aritmik kontrol
  bool _heuristicArrhythmia(List<int> rrIntervals) {
    if (rrIntervals.length < 5) return false;
    final avg = rrIntervals.reduce((a, b) => a + b) / rrIntervals.length;
    final variance = rrIntervals.map((r) => (r - avg) * (r - avg))
        .reduce((a, b) => a + b) / rrIntervals.length;
    return variance > 1500; // 38ms+ SD → yüksek HRV anomalisi
  }

  void dispose() {
    _activityInterpreter?.close();
    _arrhythmiaInterpreter?.close();
  }
}

class ActivityResult {
  final String label;
  final double confidence;
  final Map<String, double>? probabilities;

  const ActivityResult({
    required this.label,
    required this.confidence,
    this.probabilities,
  });

  // MHEALTH modelinde düşme sınıfı yoktur, bu yüzden modelden 'Fall' dönmez.
  // Düşmeyi sadece ham sensör Heuristic filtresi (Impact > 38g vb.) yakalayacak.
  bool get isFallRelated => false;

  bool get isLowActivity =>
      label == 'Sitting' || label == 'Lying' || label == 'Standing';
}
