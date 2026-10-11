// lib/screens/ble_scan_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../app_theme.dart';
import '../services/ble_service.dart';

class BleScanScreen extends StatefulWidget {
  const BleScanScreen({super.key});

  @override
  State<BleScanScreen> createState() => _BleScanScreenState();
}

class _BleScanScreenState extends State<BleScanScreen> {
  final BleService _ble = BleService();
  List<ScanResult> _results = [];
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    _ble.scanResultsStream.listen((results) {
      if (mounted) setState(() => _results = results);
    });
    _ble.statusStream.listen((status) {
      if (mounted) {
        setState(() {
          _scanning = status == BleStatus.scanning;
        });
      }
    });
    // Otomatik başlat
    if (!_ble.isConnected) {
      _startScan();
    }
  }

  Future<void> _startScan() async {
    setState(() {
      _results.clear();
      _scanning = true;
    });
    await _ble.startScan();
    if (mounted) setState(() => _scanning = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      appBar: AppBar(
        title: const Text('Cihaz Tara (BLE)'),
        actions: [
          IconButton(
            icon: _scanning
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppTheme.primaryCyan),
                  )
                : const Icon(Icons.refresh),
            onPressed: _scanning ? null : _startScan,
          ),
        ],
      ),
      body: Column(
        children: [
          // Bağlı cihaz
          if (_ble.isConnected && _ble.connectedDevice != null)
            _ConnectedDeviceBanner(device: _ble.connectedDevice!),

          // Tarama listesi
          Expanded(
            child: _results.isEmpty
                ? _ScanEmptyState(scanning: _scanning)
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _results.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _DeviceTile(
                      result: _results[i],
                      onConnect: () => _connect(_results[i].device),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _connect(BluetoothDevice device) async {
    await _ble.stopScan();
    await _ble.connectToDevice(device);
    if (mounted) {
      Navigator.pop(context);
    }
  }
}

class _ConnectedDeviceBanner extends StatelessWidget {
  final BluetoothDevice device;
  const _ConnectedDeviceBanner({required this.device});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.accentGreen.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.accentGreen.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.bluetooth_connected,
              color: AppTheme.accentGreen, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Bağlı: ${device.platformName.isEmpty ? device.remoteId : device.platformName}',
              style: const TextStyle(
                  color: AppTheme.accentGreen, fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(
            onPressed: () => BleService().disconnect(),
            child: const Text('Kopar',
                style: TextStyle(color: AppTheme.accentRed)),
          ),
        ],
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  final ScanResult result;
  final VoidCallback onConnect;
  const _DeviceTile({required this.result, required this.onConnect});

  @override
  Widget build(BuildContext context) {
    final name = result.device.platformName.isEmpty
        ? result.device.remoteId.toString()
        : result.device.platformName;
    final rssi = result.rssi;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.borderSubtle),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppTheme.primaryCyan.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.watch, color: AppTheme.primaryCyan, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  result.device.remoteId.toString(),
                  style: const TextStyle(
                      color: AppTheme.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
          Column(
            children: [
              Text(
                '$rssi dBm',
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 11),
              ),
              const SizedBox(height: 4),
              ElevatedButton(
                onPressed: onConnect,
                style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  minimumSize: Size.zero,
                  textStyle: const TextStyle(fontSize: 12),
                ),
                child: const Text('Bağlan'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ScanEmptyState extends StatelessWidget {
  final bool scanning;
  const _ScanEmptyState({required this.scanning});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (scanning)
            const CircularProgressIndicator(color: AppTheme.primaryCyan)
          else
            const Icon(Icons.bluetooth_searching,
                size: 64, color: AppTheme.textMuted),
          const SizedBox(height: 16),
          Text(
            scanning ? 'BLE Cihazlar Taranıyor...' : 'Cihaz Bulunamadı',
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Sadece Heart Rate Service destekleyen\ncihazlar listelenir.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
