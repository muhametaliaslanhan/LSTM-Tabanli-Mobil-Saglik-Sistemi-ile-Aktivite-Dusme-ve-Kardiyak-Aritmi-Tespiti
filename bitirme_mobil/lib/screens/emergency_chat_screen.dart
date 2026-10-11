// lib/screens/emergency_chat_screen.dart
//
// ACİL DURUM SOHBET EKRANI (FIREBASE REALTIME CHAT MİMARİSİ)
// WhatsApp benzeri arayüzde:
//   1. Kırmızı uyarı mesaj balonu
//   2. GPS konum linki balonu
//   3. Ses kaydı dinleyici (oynatma çubuğu) balonu
//   Mesajlar Firebase'den canlı olarak (StreamBuilder) çekilir.
//   12 Saniyelik geri sayım bittiğinde birincil kişi OTOMATİK aranır.
//

import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
import 'package:telephony/telephony.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:audioplayers/audioplayers.dart';
import '../app_theme.dart';
import '../models/emergency_contact.dart';
import '../models/sensor_data.dart';
import '../services/firebase_service.dart';
import '../utils/storage_helper.dart';

class EmergencyChatScreen extends StatefulWidget {
  final AnomalyEvent event;
  final List<EmergencyContact> contacts;
  final String? audioRecordPath;
  final bool isHistoricalView;

  const EmergencyChatScreen({
    super.key,
    required this.event,
    required this.contacts,
    this.audioRecordPath,
    this.isHistoricalView = false,
  });

  @override
  State<EmergencyChatScreen> createState() => _EmergencyChatScreenState();
}

class _EmergencyChatScreenState extends State<EmergencyChatScreen> {
  final ScrollController _scrollCtrl = ScrollController();
  bool _callInitiated = false;
  
  // Geri sayım
  static const int _totalSeconds = 12;
  int _countdown = _totalSeconds;
  Timer? _timer;
  bool _userCancelled = false;

  String _userId = '';

  @override
  void initState() {
    super.initState();
    _initChat();
  }

  Future<void> _initChat() async {
    _userId = await StorageHelper.getOrCreateUserId();
    setState(() {});

    if (!widget.isHistoricalView) {
      // 1. Firebase'e Veriyi Yükle
      final locationUrl = await _getLocationUrl();
      double lat = 0.0;
      double lng = 0.0;
      try {
        final pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ));
        lat = pos.latitude;
        lng = pos.longitude;
      } catch (_) {}

      final primaryContact = widget.contacts.isNotEmpty
          ? widget.contacts.firstWhere((c) => c.isPrimaryCaller,
              orElse: () => widget.contacts.first)
          : null;

      await FirebaseService().writeEmergencyData(
        userId: _userId,
        lat: lat,
        lng: lng,
        type: widget.event.type.name.toUpperCase(),
        recipient: primaryContact?.name ?? 'Bilinmiyor',
        recipientPhone: primaryContact?.phone.replaceAll(RegExp(r'[^\d+]'), '').trim() ?? '',
        voiceNoteUrl: widget.audioRecordPath,
      );

      // 2. Geri Sayım (Timer) Başlat
      _timer = Timer.periodic(const Duration(seconds: 1), (_) async {
        if (!mounted) return;
        setState(() => _countdown--);
        if (_countdown <= 0) {
          _timer?.cancel();
          if (!_userCancelled && !_callInitiated) {
            _callInitiated = true;
            await _sendSilentSms(locationUrl);
            _callPrimary();
          }
        }
      });
    }
  }

  void _handleCancel() {
    setState(() {
      _userCancelled = true;
    });
    _timer?.cancel();
    FirebaseService().updateStatus(_userId, 'cancelled');
    Navigator.of(context).pop();
  }

  Future<String> _getLocationUrl() async {
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return 'Konum izni yok';
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
      final lat = pos.latitude.toStringAsFixed(6);
      final lng = pos.longitude.toStringAsFixed(6);
      return 'https://maps.google.com/?q=$lat,$lng';
    } catch (_) {
      return 'Konum alınamadı';
    }
  }

  void _callPrimary() {
    if (widget.isHistoricalView) return;
    if (widget.contacts.isEmpty) return;
    final primary = widget.contacts.firstWhere(
      (c) => c.isPrimaryCaller,
      orElse: () => widget.contacts.first,
    );
    final phone = primary.phone.replaceAll(RegExp(r'[^\d+]'), '').trim();
    if (phone.isNotEmpty) {
      FlutterPhoneDirectCaller.callNumber(phone);
    }
  }

  Future<void> _sendSilentSms(String locationUrl) async {
    if (widget.contacts.isEmpty) return;
    final primary = widget.contacts.firstWhere(
      (c) => c.isPrimaryCaller,
      orElse: () => widget.contacts.first,
    );
    final phone = primary.phone.replaceAll(RegExp(r'[^\d+]'), '').trim();
    if (phone.isEmpty) return;

    final String message =
        '🚨 VITALGUARD ACİL DURUM! Kaza/Anomali algılandı. '
        'Konum: $locationUrl';

    if (!await Permission.sms.isGranted) return;

    try {
      Telephony.instance.sendSms(
        to: phone,
        message: message,
      );
    } catch (e) {
      debugPrint('[EmergencyScreen] SMS hatası: $e');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primaryName = widget.contacts.isNotEmpty
        ? widget.contacts
            .firstWhere((c) => c.isPrimaryCaller,
                orElse: () => widget.contacts.first)
            .name
        : 'Bilinmiyor';

    return PopScope(
      canPop: widget.isHistoricalView,
      child: Scaffold(
        backgroundColor: const Color(0xFF0B141A), // WhatsApp Koyu Arka Plan
        appBar: _buildAppBar(primaryName),
        body: Column(
          children: [
            // Geri Sayım Alanı
            if (!widget.isHistoricalView && !_userCancelled && _countdown > 0)
              _buildTimerBanner(primaryName),
            
            // Firebase Canlı Mesaj Listesi
            Expanded(
              child: _userId.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : StreamBuilder<EmergencySnapshot?>(
                      stream: FirebaseService().watchEmergency(_userId),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting &&
                            !snapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(
                              color: AppTheme.accentRed,
                            ),
                          );
                        }
                        
                        final data = snapshot.data;
                        if (data == null) {
                          return const Center(
                            child: Text(
                              'Firebase verisi bekleniyor veya silindi...',
                              style: TextStyle(color: Colors.white54),
                            ),
                          );
                        }

                        // Mesajları Oluştur
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (_scrollCtrl.hasClients) {
                            _scrollCtrl.animateTo(
                              _scrollCtrl.position.maxScrollExtent,
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOut,
                            );
                          }
                        });

                        return ListView(
                          controller: _scrollCtrl,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 16),
                          children: [
                            _AlertBubble(
                              type: data.type,
                              time: data.timestamp,
                              desc: widget.event.description,
                            ),
                            if (data.lat != 0.0 && data.lng != 0.0)
                              _LocationBubble(
                                lat: data.lat,
                                lng: data.lng,
                                time: data.timestamp,
                              ),
                            if (data.voiceNoteBase64.isNotEmpty)
                              _AudioBubble(
                                base64Data: data.voiceNoteBase64,
                                time: data.timestamp,
                              ),
                          ],
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(String primaryName) {
    return AppBar(
      backgroundColor: const Color(0xFF1F2C33),
      elevation: 0,
      automaticallyImplyLeading: false,
      title: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.accentRed.withAlpha(51), // 0.2 opacity
              border: Border.all(color: AppTheme.accentRed, width: 1.5),
            ),
            child: const Icon(Icons.emergency, color: AppTheme.accentRed, size: 22),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Gönderen: Kaza Yapan',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'Kime: $primaryName',
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        IconButton(
          onPressed: _callPrimary,
          icon: const Icon(Icons.phone, color: Color(0xFF25D366)),
          tooltip: 'Tekrar Ara',
        ),
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close, color: Colors.white54),
          tooltip: 'Kapat',
        ),
      ],
    );
  }

  Widget _buildTimerBanner(String primaryName) {
    return Container(
      color: const Color(0xFF1A2F38),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              'Birincil Kişi Aranıyor: $primaryName... ($_countdown)',
              style: const TextStyle(
                color: AppTheme.accentOrange,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: _handleCancel,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentRed,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: const Text('İptal Et', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

// ─── Alert Balonu ─────────────────────────────────────────────────────────
class _AlertBubble extends StatelessWidget {
  final String type;
  final DateTime time;
  final String desc;

  const _AlertBubble({required this.type, required this.time, required this.desc});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12, right: 60),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFFE53935).withAlpha(230), // 0.9 opacity
                    const Color(0xFFB71C1C).withAlpha(204), // 0.8 opacity
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(18),
                  bottomLeft: Radius.circular(18),
                  bottomRight: Radius.circular(18),
                ),
              ),
              child: Text(
                '🚨 Acil Durum Tespit Edildi!\nTür: $type\n$desc\n\nHastanın yardıma ihtiyacı olabilir.',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _timeStr(time),
              style: const TextStyle(color: Colors.white38, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Konum Balonu ─────────────────────────────────────────────────────────
class _LocationBubble extends StatelessWidget {
  final double lat;
  final double lng;
  final DateTime time;

  const _LocationBubble({required this.lat, required this.lng, required this.time});

  @override
  Widget build(BuildContext context) {
    final locationUrl = 'https://maps.google.com/?q=$lat,$lng';
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12, right: 60),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () async {
                final uri = Uri.parse(locationUrl);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A2F38),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4),
                    topRight: Radius.circular(18),
                    bottomLeft: Radius.circular(18),
                    bottomRight: Radius.circular(18),
                  ),
                  border: Border.all(
                    color: const Color(0xFF25D366).withAlpha(127), // 0.5 opacity
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.location_on, color: Color(0xFF25D366), size: 22),
                    const SizedBox(width: 10),
                    const Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Anlık Konum',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Google Maps\'te Aç',
                            style: TextStyle(
                              color: Color(0xFF25D366),
                              fontSize: 12,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _timeStr(time),
              style: const TextStyle(color: Colors.white38, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Ses Balonu (Base64'ten Çözülen Ses) ─────────────────────────────────
class _AudioBubble extends StatefulWidget {
  final String base64Data;
  final DateTime time;

  const _AudioBubble({required this.base64Data, required this.time});

  @override
  State<_AudioBubble> createState() => _AudioBubbleState();
}

class _AudioBubbleState extends State<_AudioBubble> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  String? _tempFilePath;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state == PlayerState.playing;
        });
      }
    });
    _audioPlayer.onDurationChanged.listen((newDuration) {
      if (mounted) setState(() => _duration = newDuration);
    });
    _audioPlayer.onPositionChanged.listen((newPosition) {
      if (mounted) setState(() => _position = newPosition);
    });
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    if (_tempFilePath != null) {
      try {
        File(_tempFilePath!).deleteSync();
      } catch (_) {}
    }
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (_isPlaying) {
      await _audioPlayer.pause();
      return;
    }

    if (_tempFilePath == null) {
      setState(() => _isLoading = true);
      try {
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/emergency_audio_${DateTime.now().millisecondsSinceEpoch}.m4a');
        final bytes = base64Decode(widget.base64Data);
        await file.writeAsBytes(bytes);
        _tempFilePath = file.path;
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ses dosyası oluşturulamadı: $e')),
          );
        }
        setState(() => _isLoading = false);
        return;
      }
      setState(() => _isLoading = false);
    }

    if (_tempFilePath != null) {
      await _audioPlayer.play(DeviceFileSource(_tempFilePath!));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12, right: 60),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 240,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF1A2F38),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(18),
                  bottomLeft: Radius.circular(18),
                  bottomRight: Radius.circular(18),
                ),
                border: Border.all(
                  color: AppTheme.accentOrange.withAlpha(102), // 0.4 opacity
                ),
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _togglePlay,
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.accentOrange.withAlpha(51), // 0.2 opacity
                        border: Border.all(
                          color: AppTheme.accentOrange.withAlpha(153), // 0.6 opacity
                        ),
                      ),
                      child: _isLoading 
                        ? const Padding(
                            padding: EdgeInsets.all(10.0),
                            child: CircularProgressIndicator(color: AppTheme.accentOrange, strokeWidth: 2),
                          )
                        : Icon(
                            _isPlaying ? Icons.pause : Icons.play_arrow,
                            color: AppTheme.accentOrange,
                            size: 24,
                          ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '🎙️ Acil Ses Kaydı',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 4),
                        // Oynatma ilerleme çubuğu
                        SliderTheme(
                          data: SliderThemeData(
                            trackHeight: 3,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                            overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                            activeTrackColor: AppTheme.accentOrange,
                            inactiveTrackColor: Colors.white12,
                            thumbColor: AppTheme.accentOrange,
                          ),
                          child: Slider(
                            min: 0.0,
                            max: _duration.inSeconds.toDouble() > 0 ? _duration.inSeconds.toDouble() : 1.0,
                            value: _position.inSeconds.toDouble().clamp(0.0, _duration.inSeconds.toDouble() > 0 ? _duration.inSeconds.toDouble() : 1.0),
                            onChanged: (val) {
                              _audioPlayer.seek(Duration(seconds: val.toInt()));
                            },
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _formatDuration(_position),
                              style: const TextStyle(color: Colors.white38, fontSize: 11),
                            ),
                            Text(
                              _formatDuration(_duration),
                              style: const TextStyle(color: Colors.white38, fontSize: 11),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _timeStr(widget.time),
              style: const TextStyle(color: Colors.white38, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final m = twoDigits(d.inMinutes.remainder(60));
    final s = twoDigits(d.inSeconds.remainder(60));
    return '$m:$s';
  }
}

// ─── Yardımcı ────────────────────────────────────────────────────────────
String _timeStr(DateTime t) {
  final h = t.hour.toString().padLeft(2, '0');
  final m = t.minute.toString().padLeft(2, '0');
  return '$h:$m';
}
