import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import '../app_theme.dart';
import '../models/sensor_data.dart';

class EmergencyAlertDialog extends StatefulWidget {
  final AnomalyEvent event;
  /// Kullanıcı "İyiyim / İptal" derse çağrılır — acil protokol tetiklenmez.
  final VoidCallback onDismiss;
  /// 12 saniye dolduğunda çağrılır — SMS + arama başlar.
  final void Function(String?) onTimeout;

  const EmergencyAlertDialog({
    super.key,
    required this.event,
    required this.onDismiss,
    required this.onTimeout,
  });

  @override
  State<EmergencyAlertDialog> createState() => _EmergencyAlertDialogState();
}

class _EmergencyAlertDialogState extends State<EmergencyAlertDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late Animation<double> _scaleAnim;

  // *** 12 saniye geri sayım ***
  static const int _totalSeconds = 12;
  int _countdown = _totalSeconds;
  Timer? _timer;
  bool _userCancelled = false;

  final _audioRecorder = Record();
  String? _recordPath;

  @override
  void initState() {
    super.initState();

    // Pulsing animasyon
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat(reverse: true);
    _scaleAnim = Tween<double>(begin: 0.97, end: 1.03).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    // 12 saniye titreşim başlat
    _startVibration();

    // Ses kaydı başlat (Asenkron bloklama yapmaması için unawaited kullanıyoruz)
    unawaited(_startRecording());

    // Geri sayım başlat
    _timer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!mounted) return;
      setState(() => _countdown--);
      if (_countdown <= 0) {
        _timer?.cancel();
        _stopVibration();
        if (!_userCancelled) {
          await _stopRecording();
          widget.onTimeout(_recordPath); // Süre doldu → SMS + arama
          if (mounted) Navigator.of(context).pop();
        }
      }
    });
  }

  Future<void> _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final dir = await getApplicationDocumentsDirectory();
        _recordPath = '${dir.path}/emergency_record_${DateTime.now().millisecondsSinceEpoch}.m4a';
        
        await _audioRecorder.start(
          path: _recordPath,
          encoder: AudioEncoder.aacLc,
        );
      }
    } catch (_) {}
  }

  Future<void> _stopRecording() async {
    try {
      if (await _audioRecorder.isRecording()) {
        await _audioRecorder.stop();
      }
    } catch (_) {}
  }

  Future<void> _startVibration() async {
    try {
      final hasVibrator = await Vibration.hasVibrator() ?? false;
      if (!hasVibrator) return;
      // 12 saniye boyunca: 800ms titreşim, 200ms dur, tekrarla
      Vibration.vibrate(
        pattern: [0, 800, 200, 800, 200, 800, 200, 800, 200,
                  800, 200, 800, 200, 800, 200, 800, 200,
                  800, 200, 800, 200, 800, 200, 800],
        intensities: [0, 255, 0, 255, 0, 255, 0, 255, 0,
                      255, 0, 255, 0, 255, 0, 255, 0,
                      255, 0, 255, 0, 255, 0, 255],
      );
    } catch (_) {}
  }

  void _stopVibration() {
    try { Vibration.cancel(); } catch (_) {}
  }

  void _handleDismiss() async {
    _userCancelled = true;
    _timer?.cancel();
    _stopVibration();
    await _stopRecording();
    if (_recordPath != null) {
      try {
        final path = _recordPath;
        if (path != null) {
          final file = File(path);
          if (file.existsSync()) file.deleteSync();
        }
      } catch (_) {}
    }
    widget.onDismiss();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseCtrl.dispose();
    _stopVibration();
    _audioRecorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _countdown / _totalSeconds;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20),
      child: AnimatedBuilder(
        animation: _scaleAnim,
        builder: (_, child) => Transform.scale(
          scale: _scaleAnim.value,
          child: child,
        ),
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF2A0A0A), Color(0xFF1A0808)],
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: AppTheme.accentRed.withOpacity(0.85),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.accentRed.withOpacity(0.4),
                blurRadius: 40,
                spreadRadius: 6,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Dairesel geri sayım göstergesi
              SizedBox(
                width: 90,
                height: 90,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 90,
                      height: 90,
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 5,
                        backgroundColor: AppTheme.accentRed.withOpacity(0.15),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          _countdown <= 4
                              ? AppTheme.accentRed
                              : AppTheme.accentOrange,
                        ),
                      ),
                    ),
                    Text(
                      '$_countdown',
                      style: TextStyle(
                        color: _countdown <= 4
                            ? AppTheme.accentRed
                            : AppTheme.accentOrange,
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              const Text(
                '🚨 ACİL DURUM TESPİT EDİLDİ',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.accentRed,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.event.typeLabel,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.event.description,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 16),

              // Bilgi metni
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.accentOrange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppTheme.accentOrange.withOpacity(0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.timer_outlined,
                        size: 14, color: AppTheme.accentOrange),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Süre bitince acil kişiler otomatik uyarılacak',
                        style: const TextStyle(
                          color: AppTheme.accentOrange,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 22),

              // İPTAL butonu — büyük ve belirgin
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _handleDismiss,
                  icon: const Icon(Icons.check_circle_outline, size: 20),
                  label: const Text(
                    'İYİYİM — İPTAL ET',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accentGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 10),

              // Şimdi ara butonu
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    _timer?.cancel();
                    _stopVibration();
                    await _stopRecording();
                    if (mounted) Navigator.of(context).pop();
                    widget.onTimeout(_recordPath); // Hemen tetikle
                  },
                  icon: const Icon(Icons.phone, size: 18),
                  label: const Text('Şimdi Yardım İste'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.accentRed,
                    side: BorderSide(
                        color: AppTheme.accentRed.withOpacity(0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
