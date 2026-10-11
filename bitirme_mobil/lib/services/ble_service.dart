// lib/services/ble_service.dart
import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// BLE servisi - Polar/Garmin/WearOS cihazlarından Heart Rate okur.
/// Bağlı cihaz yoksa "Watch-Less Mode" aktif olur.
class BleService {
  static final BleService _instance = BleService._();
  factory BleService() => _instance;
  BleService._();

  // Bluetooth Heart Rate Service UUID (standart GATT)
  static const String hrServiceUuid = '0000180d-0000-1000-8000-00805f9b34fb';
  static const String hrMeasurementUuid = '00002a37-0000-1000-8000-00805f9b34fb';

  BluetoothDevice? _connectedDevice;
  StreamSubscription<List<int>>? _hrSub;
  StreamSubscription<BluetoothAdapterState>? _adapterSub;
  StreamSubscription<List<ScanResult>>? _scanSub;

  final _heartRateController = StreamController<int>.broadcast();
  final _statusController = StreamController<BleStatus>.broadcast();
  final _devicesController = StreamController<List<ScanResult>>.broadcast();
  final _watchCancelController = StreamController<bool>.broadcast();

  Stream<int> get heartRateStream => _heartRateController.stream;
  Stream<BleStatus> get statusStream => _statusController.stream;
  Stream<List<ScanResult>> get scanResultsStream => _devicesController.stream;
  Stream<bool> get watchCancelStream => _watchCancelController.stream;

  BluetoothDevice? get connectedDevice => _connectedDevice;
  bool get isConnected => _connectedDevice != null;

  // Taranan cihaz listesi
  final List<ScanResult> _scanResults = [];

  /// Bluetooth adaptörü hazır olduğunda sistemde zaten bağlı olan HR cihazını bul.
  void init() {
    _adapterSub = FlutterBluePlus.adapterState.listen((state) {
      if (state == BluetoothAdapterState.on) {
        _statusController.add(BleStatus.ready);
        // Bluetooth açıldığında hemen sistem bağlantılarını kontrol et
        _autoConnectSystemDevice();
      } else {
        _statusController.add(BleStatus.off);
      }
    });
  }

  /// Telefon sisteminde halihazırda bağlı (paired + connected) BLE cihazları tara.
  /// Heart Rate Service sunan ilk cihaza otomatik bağlan.
  Future<void> _autoConnectSystemDevice() async {
    if (isConnected) return; // Zaten bağlıysa gerek yok

    try {
      // Sistemde bağlı (eşleşmiş) tüm BLE cihazlarını al
      final connectedSystemDevices = await FlutterBluePlus.systemDevices([]);

      for (final device in connectedSystemDevices) {
        // Sistemde bağlıysa uygulamada da bağlantı kurmalıyız (GATT için)
        try {
          await device.connect(autoConnect: false, timeout: const Duration(seconds: 2));
          final services = await device.discoverServices();
          final hasHrService = services.any(
            (s) => s.uuid.toString().toLowerCase().contains('180d'),
          );
          if (hasHrService) {
            // HR servisi olan ilk sistem cihazına bağlan
            await _connectSystemDevice(device);
            return;
          } else {
            // HR yoksa kopar
            await device.disconnect();
          }
        } catch (_) {
          continue;
        }
      }
    } catch (_) {
      // Sistem cihazı bulunamazsa sessizce devam et (Watch-Less Mode)
    }
  }

  /// Sistem bağlantısından gelen cihazla HR aboneliği kur (connect() çağrılmaz)
  Future<void> _connectSystemDevice(BluetoothDevice device) async {
    try {
      _connectedDevice = device;
      _statusController.add(BleStatus.connected);

      device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _onDisconnected();
        }
      });

      await _subscribeHeartRate(device);
    } catch (_) {
      _connectedDevice = null;
    }
  }

  Future<void> startScan({Duration timeout = const Duration(seconds: 12)}) async {
    _scanResults.clear();
    _statusController.add(BleStatus.scanning);

    try {
      await FlutterBluePlus.startScan(
        withServices: [Guid(hrServiceUuid)],
        timeout: timeout,
      );
    } catch (_) {
      // Bazı cihazlarda withServices filtresi sorun çıkarabilir; filtresiz tara
      await FlutterBluePlus.startScan(timeout: timeout);
    }

    _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        if (!_scanResults.any((s) => s.device.remoteId == r.device.remoteId)) {
          _scanResults.add(r);
        }
      }
      _devicesController.add(List.from(_scanResults));
    });
  }

  Future<void> stopScan() async {
    _scanSub?.cancel();
    await FlutterBluePlus.stopScan();
    _statusController.add(BleStatus.ready);
  }

  Future<void> connectToDevice(BluetoothDevice device) async {
    try {
      _statusController.add(BleStatus.connecting);
      await device.connect(timeout: const Duration(seconds: 15));
      _connectedDevice = device;

      device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _onDisconnected();
        }
      });

      await _subscribeHeartRate(device);
      _statusController.add(BleStatus.connected);
    } catch (e) {
      _statusController.add(BleStatus.error);
    }
  }

  Future<void> _subscribeHeartRate(BluetoothDevice device) async {
    final services = await device.discoverServices();
    for (final service in services) {
      if (service.uuid.toString().toLowerCase().contains('180d')) {
        for (final char in service.characteristics) {
          if (char.uuid.toString().toLowerCase().contains('2a37')) {
            await char.setNotifyValue(true);
            _hrSub?.cancel();
            _hrSub = char.lastValueStream.listen((value) {
              if (value.isNotEmpty) {
                // FALLBACK: Eğer saat "İptal" sinyalini nabız sensörü üzerinden
                // 255 (0xFF) vb. olarak gönderiyorsa (bazı custom saatler yapar):
                if (value.length == 1 && value[0] == 255) {
                  _watchCancelController.add(true);
                  return;
                }
                
                final hr = _parseHeartRate(value);
                if (hr > 0 && hr < 255) _heartRateController.add(hr);
              }
            });
          }
        }
      }
    }
  }

  /// Acil durum tetiklendiğinde saati titretmek/alarm çalmak için
  Future<void> sendAlarmToWatch(bool active) async {
    if (_connectedDevice == null) return;
    try {
      final services = await _connectedDevice!.discoverServices();
      
      // Standart Immediate Alert Service (0x1802) arıyoruz.
      // EĞER İLERİDE KENDİ SAATİNİZİN ÖZEL UUID'Sİ GEREKİRSE BURAYA EKLEYİN.
      // Örnek: final customServiceId = '0000aaaa-0000-1000-8000-00805f9b34fb';
      
      for (final service in services) {
        if (service.uuid.toString().toLowerCase().contains('1802')) {
          for (final char in service.characteristics) {
            // Alert Level Characteristic (0x2A06)
            if (char.uuid.toString().toLowerCase().contains('2a06')) {
              // 0x02 = High Alert, 0x00 = No Alert
              final payload = active ? [0x02] : [0x00];
              await char.write(payload, withoutResponse: true);
              return;
            }
          }
        }
      }
    } catch (_) {}
  }

  /// BLE Heart Rate ölçüm formatını parse et (GATT spec)
  int _parseHeartRate(List<int> value) {
    if (value.isEmpty) return 0;
    final flags = value[0];
    final is16bit = (flags & 0x01) != 0;
    if (is16bit && value.length >= 3) {
      return value[1] | (value[2] << 8);
    } else if (value.length >= 2) {
      return value[1];
    }
    return 0;
  }

  void _onDisconnected() {
    _hrSub?.cancel();
    _hrSub = null;
    _connectedDevice = null;
    _statusController.add(BleStatus.disconnected);
  }

  Future<void> disconnect() async {
    await _connectedDevice?.disconnect();
    _onDisconnected();
  }

  void dispose() {
    _scanSub?.cancel();
    _hrSub?.cancel();
    _adapterSub?.cancel();
    _heartRateController.close();
    _statusController.close();
    _devicesController.close();
    _watchCancelController.close();
  }
}

enum BleStatus { off, ready, scanning, connecting, connected, disconnected, error }
