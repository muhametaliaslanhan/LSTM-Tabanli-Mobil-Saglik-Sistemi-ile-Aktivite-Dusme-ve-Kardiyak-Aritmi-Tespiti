// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';

import 'app_theme.dart';
import 'services/monitoring_controller.dart';
import 'screens/home_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/emergency_contacts_screen.dart';
import 'screens/history_screen.dart';
import 'screens/ble_scan_screen.dart';
import 'screens/auth_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:firebase_core/firebase_core.dart';
import 'services/background_task_handler.dart';
import 'utils/storage_helper.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Status bar rengi
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  // Firebase Başlatma
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint("Firebase başlatılamadı: $e");
  }

  // ── 1. Foreground Task ÖNCE yapılandırılmalı ─────────────
  // startService() controller.init() → startMonitoring() içinde çağrılır.
  // Sıra: init task → izinler → controller init (startService burada tetiklenir)
  _initForegroundTask();

  // ── 2. Tüm izinleri al (bildirim dahil, senkron bekleniyor) ──
  await _requestPermissions();

  // ── 3. Controller başlat (içinde startMonitoring → startService var) ──
  final controller = MonitoringController();
  await controller.init();

  final prefs = await SharedPreferences.getInstance();
  final isLoggedIn = prefs.getBool('is_logged_in') ?? false;

  // Kullanıcı kimliğini oluştur/yükle (Firebase için)
  await StorageHelper.getOrCreateUserId();

  runApp(
    ChangeNotifierProvider.value(
      value: controller,
      child: VitalGuardApp(isLoggedIn: isLoggedIn),
    ),
  );
}

void _initForegroundTask() {
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'vitalguard_foreground',
      channelName: 'VitalGuard İzleme',
      channelDescription: 'Sağlık izleme arka planda çalışıyor.',
      channelImportance: NotificationChannelImportance.HIGH,
      priority: NotificationPriority.HIGH,

    ),
    iosNotificationOptions: const IOSNotificationOptions(
      showNotification: true,
      playSound: false,
    ),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.repeat(5000),
      autoRunOnBoot: true,
      allowWakeLock: true,
      allowWifiLock: true,
    ),
  );
}

Future<void> _requestPermissions() async {
  await FlutterForegroundTask.requestNotificationPermission();
  await [
    Permission.locationWhenInUse,
    Permission.locationAlways,
    Permission.activityRecognition,
    Permission.sensors,
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
    Permission.phone,
    Permission.sms,
    Permission.notification,
    Permission.ignoreBatteryOptimizations, // Foreground service için
    Permission.systemAlertWindow, // Draw Over Other Apps izni (Arka plandan öne çıkmak için)
  ].request();
}

class VitalGuardApp extends StatelessWidget {
  final bool isLoggedIn;
  const VitalGuardApp({super.key, required this.isLoggedIn});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VitalGuard',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: isLoggedIn ? const MainNavigation() : const AuthScreen(),
    );
  }
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  final List<Widget> _screens = const [
    HomeScreen(),
    HistoryScreen(),
    EmergencyContactsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(), // Kaydırma iptal, sadece tıklama ile
        children: _screens,
        onPageChanged: (i) {
          setState(() => _currentIndex = i);
        },
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppTheme.borderSubtle)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (i) {
            _pageController.jumpToPage(i);
          },
          backgroundColor: AppTheme.bgSecondary,
          selectedItemColor: AppTheme.primaryCyan,
          unselectedItemColor: AppTheme.textMuted,
          type: BottomNavigationBarType.fixed,
          selectedFontSize: 11,
          unselectedFontSize: 11,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.monitor_heart_outlined),
              activeIcon: Icon(Icons.monitor_heart),
              label: 'İzleme',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.history_outlined),
              activeIcon: Icon(Icons.history),
              label: 'Geçmiş',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.emergency_outlined),
              activeIcon: Icon(Icons.emergency),
              label: 'Acil',
            ),
          ],
        ),
      ),
    );
  }
}
