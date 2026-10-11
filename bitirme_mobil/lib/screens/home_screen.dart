// lib/screens/home_screen.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import '../app_theme.dart';
import '../services/monitoring_controller.dart';
import '../widgets/vitals_card.dart';
import '../widgets/emergency_alert_dialog.dart';
import 'ble_scan_screen.dart';
import 'profile_screen.dart';
import 'emergency_chat_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _dialogShown = false;
  StreamSubscription<Object?>? _bgPortSub;

  @override
  void initState() {
    super.initState();
    // ── Arka plan isolate'inden gelen acil durum sinyalini dinle ────────────
    // background_task_handler.dart -> FlutterForegroundTask.sendDataToMain()
    // bu port üzerinden UI thread'e ulaşır.
    _bgPortSub = FlutterForegroundTask.receivePort?.listen((data) {
      if (data is Map && data['type'] == 'background_emergency' && mounted) {
        final ctrl = context.read<MonitoringController>();

        // Arka plan bildirimine tıklanınca uygulama öne gelir ve bu sinyal tetiklenir.
        // Acil durum modundaysa → doğrudan EmergencyChatScreen'e navigate et.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (ctrl.latestAnomaly != null && !_dialogShown) {
            _dialogShown = true;
            final eventSnapshot = ctrl.latestAnomaly!;
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => EmergencyChatScreen(
                  event: eventSnapshot,
                  contacts: ctrl.contacts,
                ),
              ),
            ).then((_) {
              _dialogShown = false;
            });
          } else if (!_dialogShown) {
            // latestAnomaly henüz set edilmemişse build() mekanizmasını tetikle
            setState(() {});
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _bgPortSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<MonitoringController>();

    // Acil durum: Uygulama AÇIKKEN → EmergencyAlertDialog (geri sayım + iptal)
    // Aynı anda EmergencyChatScreen arkada push'lanır (Firebase dinleyici hazır olur)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ctrl.isEmergencyMode && !_dialogShown && mounted) {
        _dialogShown = true;
        final eventSnapshot = ctrl.latestAnomaly!;

        // 1) Sohbet ekranını arkaya push et
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => EmergencyChatScreen(
              event: eventSnapshot,
              contacts: ctrl.contacts,
            ),
          ),
        ).then((_) {
          ctrl.dismissEmergency();
          _dialogShown = false;
        });

        // 2) Üstüne agresif uyarı dialogunu çıkar
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => EmergencyAlertDialog(
            event: eventSnapshot,
            onDismiss: () {
              ctrl.dismissEmergency();
              _dialogShown = false;
              Navigator.of(context).pop(); // Chat ekranını da kapat
            },
            onTimeout: (audioPath) {
              ctrl.triggerEmergencyNow(audioRecordPath: audioPath);
              _dialogShown = false;
            },
          ),
        );
      }
      if (!ctrl.isEmergencyMode) _dialogShown = false;
    });


    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      body: CustomScrollView(
        slivers: [
          // ── Yeni Üst Bar ────────────────────────────────────────
          SliverAppBar(
            pinned: true,
            expandedHeight: 90,
            backgroundColor: AppTheme.bgPrimary,
            automaticallyImplyLeading: false,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(color: AppTheme.bgPrimary),
            ),
            title: _TopBarContent(profile: ctrl.profile),
            actions: [
              _LocationIconButton(),
              const SizedBox(width: 8),
            ],
          ),

          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                const SizedBox(height: 8),

                // İzleme durum kartı
                _MonitoringStatusCard(
                  isActive: ctrl.isMonitoring,
                  onStop: ctrl.isMonitoring
                      ? () => ctrl.stopMonitoring()
                      : () => ctrl.startMonitoring(),
                ),

                const SizedBox(height: 20),

                // Nabız & aktivite kartı
                VitalsCard(
                  heartRate: ctrl.currentHeartRate,
                  activity: ctrl.currentActivity,
                  isWatchConnected: ctrl.isWatchConnected,
                  isAnomaly: ctrl.isEmergencyMode,
                ),

                const SizedBox(height: 16),

                // AI model durum kartı
                _InfoCard(
                  icon: Icons.psychology_rounded,
                  label: 'AI Modeli',
                  value: ctrl.modelsLoaded ? 'Hazır' : 'Heuristik',
                  color: ctrl.modelsLoaded
                      ? AppTheme.accentGreen
                      : AppTheme.accentOrange,
                ),
                const SizedBox(height: 16),

                // Son olaylar
                _RecentEventsSection(
                    events: ctrl.eventHistory.take(3).toList()),

                const SizedBox(height: 100),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  YENİ ÜST BAR — Avatar + İsim + Yaş/Boy/Kilo
// ─────────────────────────────────────────────────────────────────────────────
class _TopBarContent extends StatelessWidget {
  final dynamic profile;
  const _TopBarContent({required this.profile});

  void _openProfileSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ProfileBottomSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasAvatar =
        profile.avatarPath != null && profile.avatarPath!.isNotEmpty;
    final name =
        profile.name.isEmpty ? 'Kullanıcı' : profile.name;
    final age = profile.age;
    final weight = profile.weightKg.toStringAsFixed(0);
    final height = profile.heightCm.toStringAsFixed(0);

    return GestureDetector(
      onTap: () => _openProfileSheet(context),
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Dairesel Avatar ──────────────────────────────────
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: !hasAvatar
                  ? const LinearGradient(
                      colors: [AppTheme.primaryCyan, AppTheme.primaryBlue],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              border: Border.all(
                color: AppTheme.primaryCyan.withOpacity(0.6),
                width: 2,
              ),
              image: hasAvatar
                  ? DecorationImage(
                      image: FileImage(File(profile.avatarPath!)),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: !hasAvatar
                ? Center(
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : 'V',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 12),

          // ── İsim + Fiziksel Bilgiler ─────────────────────────
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '$age Yaş • $height cm • $weight kg',
                    style: const TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  KONUM İKON BUTONU — Google Haritalar'da açar (ücretsiz)
// ─────────────────────────────────────────────────────────────────────────────
class _LocationIconButton extends StatefulWidget {
  @override
  State<_LocationIconButton> createState() => _LocationIconButtonState();
}

class _LocationIconButtonState extends State<_LocationIconButton> {
  bool _loading = false;

  Future<void> _openLocation() async {
    if (_loading) return;
    setState(() => _loading = true);

    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        await Geolocator.requestPermission();
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );

      final lat = pos.latitude.toStringAsFixed(6);
      final lng = pos.longitude.toStringAsFixed(6);
      final uri = Uri.parse('https://maps.google.com/?q=$lat,$lng');

      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Konum alınamadı. Konum izni ve GPS\'i kontrol edin.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _openLocation,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.borderSubtle),
        ),
        child: _loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppTheme.primaryCyan,
                ),
              )
            : const Icon(
                Icons.location_on_outlined,
                color: AppTheme.primaryCyan,
                size: 20,
              ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  PROFİL MODAL BOTTOM SHEET
// ─────────────────────────────────────────────────────────────────────────────
class _ProfileBottomSheet extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),

          // Başlık
          const Row(
            children: [
              Icon(Icons.manage_accounts_outlined,
                  color: AppTheme.primaryCyan, size: 22),
              SizedBox(width: 10),
              Text(
                'Hesabım',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Seçenekler
          _SheetTile(
            icon: Icons.person_outline,
            title: 'Profil & Sağlık Bilgileri',
            subtitle: 'Kişisel bilgiler, kronik hastalıklar',
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const ProfileScreen()));
            },
          ),
          const SizedBox(height: 12),
          _SheetTile(
            icon: Icons.bluetooth_outlined,
            title: 'Bağlı Cihazlar',
            subtitle: 'Akıllı saat & sensör yönetimi',
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const BleScanScreen()));
            },
          ),
          const SizedBox(height: 12),
          _SheetTile(
            icon: Icons.settings_outlined,
            title: 'Ayarlar',
            subtitle: 'Bildirim ve uygulama tercihleri',
            onTap: () {
              Navigator.pop(context);
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: AppTheme.bgCard,
                  title: const Text('Ayarlar',
                      style: TextStyle(color: AppTheme.textPrimary)),
                  content: const Text(
                    'Uygulama ayarları yakında eklenecektir.',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Kapat')),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _SheetTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SheetTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.borderSubtle),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.primaryCyan.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppTheme.primaryCyan, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      )),
                  Text(subtitle,
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 12,
                      )),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                color: AppTheme.textMuted, size: 18),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  İZLEME DURUM KARTI
// ─────────────────────────────────────────────────────────────────────────────
class _MonitoringStatusCard extends StatelessWidget {
  final bool isActive;
  final VoidCallback onStop;

  const _MonitoringStatusCard({required this.isActive, required this.onStop});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isActive
              ? [
                  AppTheme.primaryCyan.withOpacity(0.15),
                  AppTheme.primaryBlue.withOpacity(0.08),
                ]
              : [
                  AppTheme.accentRed.withOpacity(0.08),
                  AppTheme.bgCard,
                ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isActive
              ? AppTheme.primaryCyan.withOpacity(0.4)
              : AppTheme.accentRed.withOpacity(0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          _PulseRing(active: isActive),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isActive ? 'Sistem Aktif' : 'Sistem Durduruldu',
                  style: TextStyle(
                    color: isActive
                        ? AppTheme.primaryCyan
                        : AppTheme.accentRed,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  isActive
                      ? 'Sensörler + AI otomatik çalışıyor'
                      : 'Yeniden başlatmak için dokun',
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onStop,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isActive
                    ? AppTheme.accentRed.withOpacity(0.15)
                    : AppTheme.accentGreen.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isActive
                      ? AppTheme.accentRed.withOpacity(0.4)
                      : AppTheme.accentGreen.withOpacity(0.4),
                ),
              ),
              child: Text(
                isActive ? 'Durdur' : 'Başlat',
                style: TextStyle(
                  color:
                      isActive ? AppTheme.accentRed : AppTheme.accentGreen,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  PULSE RING ANİMASYONU
// ─────────────────────────────────────────────────────────────────────────────
class _PulseRing extends StatefulWidget {
  final bool active;
  const _PulseRing({required this.active});

  @override
  State<_PulseRing> createState() => _PulseRingState();
}

class _PulseRingState extends State<_PulseRing>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _anim = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    if (widget.active) _ctrl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_PulseRing old) {
    super.didUpdateWidget(old);
    if (widget.active && !_ctrl.isAnimating) {
      _ctrl.repeat(reverse: true);
    } else if (!widget.active && _ctrl.isAnimating) {
      _ctrl.stop();
      _ctrl.reset();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.active ? AppTheme.primaryCyan : AppTheme.textMuted;
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, child) => Stack(
        alignment: Alignment.center,
        children: [
          if (widget.active)
            Transform.scale(
              scale: _anim.value,
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.primaryCyan.withOpacity(0.1),
                ),
              ),
            ),
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withOpacity(0.15),
              border: Border.all(color: color.withOpacity(0.4), width: 1.5),
            ),
            child: Icon(Icons.monitor_heart, color: color, size: 24),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  BİLGİ KARTI (AI Modeli vb.)
// ─────────────────────────────────────────────────────────────────────────────
class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _InfoCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.borderSubtle),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  SON OLAYLAR
// ─────────────────────────────────────────────────────────────────────────────
class _RecentEventsSection extends StatelessWidget {
  final List events;
  const _RecentEventsSection({required this.events});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Son Olaylar',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        if (events.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.bgCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.borderSubtle),
            ),
            child: const Center(
              child: Text(
                'Henüz anomali tespit edilmedi ✓',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
              ),
            ),
          )
        else
          ...events.map((e) => _EventTile(event: e)),
      ],
    );
  }
}

class _EventTile extends StatelessWidget {
  final dynamic event;
  const _EventTile({required this.event});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.accentRed.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: AppTheme.accentOrange, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.typeLabel ?? '',
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  event.description ?? '',
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Text(
            _formatTime(event.timestamp),
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}dk önce';
    if (diff.inHours < 24) return '${diff.inHours}s önce';
    return '${dt.day}/${dt.month}';
  }
}
