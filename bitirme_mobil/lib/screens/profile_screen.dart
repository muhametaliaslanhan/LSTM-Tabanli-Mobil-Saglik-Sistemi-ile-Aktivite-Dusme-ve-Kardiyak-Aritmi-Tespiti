// lib/screens/profile_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../app_theme.dart';
import '../models/user_profile.dart';
import '../services/monitoring_controller.dart';
import '../utils/heart_rate_thresholds.dart';
import '../utils/storage_helper.dart';

// Hastalık listesi — nabız eşiklerini etkileyen hastalıklar işaretli
const List<Map<String, dynamic>> _kDiseaseList = [
  {'name': 'Hipertansiyon', 'affectsHR': true},
  {'name': 'Diyabet', 'affectsHR': true},
  {'name': 'Kalp Hastalığı', 'affectsHR': true},
  {'name': 'Astım', 'affectsHR': false},
  {'name': 'Epilepsi', 'affectsHR': false},
  {'name': 'Osteoporoz', 'affectsHR': false},
  {'name': 'Atrial Fibrilasyon', 'affectsHR': true},
  {'name': 'Koroner Arter Hastalığı', 'affectsHR': true},
  {'name': 'Aritmi', 'affectsHR': true},
  {'name': 'Taşikardi', 'affectsHR': true},
  {'name': 'Bradikardi', 'affectsHR': true},
  {'name': 'Kalp Yetmezliği', 'affectsHR': true},
  {'name': 'KOAH', 'affectsHR': false},
  {'name': 'Tiroid Bozukluğu', 'affectsHR': true},
  {'name': 'Tansiyon', 'affectsHR': true},
  {'name': 'Obezite', 'affectsHR': false},
  {'name': 'Anemi', 'affectsHR': true},
  {'name': 'Uyku Apnesi', 'affectsHR': true},
  {'name': 'Parkinson', 'affectsHR': false},
  {'name': 'Alzheimer', 'affectsHR': false},
];

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _ageCtrl;
  late TextEditingController _weightCtrl;
  late TextEditingController _heightCtrl;
  late TextEditingController _myPhoneCtrl; // Kendi telefon numaramız
  String? _avatarPath;

  late Set<String> _selectedConditions;
  bool _saving = false;
  bool _isEditingInfo = false;     // Kişisel bilgiler edit modu
  bool _isEditingConditions = false; // Kronik hastalıklar edit modu
  bool _showSavedBadge = false;

  @override
  void initState() {
    super.initState();
    final profile = context.read<MonitoringController>().profile;
    _nameCtrl = TextEditingController(text: profile.name);
    _ageCtrl = TextEditingController(text: profile.age.toString());
    _weightCtrl = TextEditingController(text: profile.weightKg.toStringAsFixed(0));
    _heightCtrl = TextEditingController(text: profile.heightCm.toStringAsFixed(0));
    _myPhoneCtrl = TextEditingController();
    _selectedConditions = Set.from(profile.chronicConditions);
    _avatarPath = profile.avatarPath;
    // Kaydedilmiş telefon numarasını yükle
    StorageHelper.getMyPhone().then((phone) {
      if (mounted) setState(() => _myPhoneCtrl.text = phone);
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _ageCtrl.dispose();
    _weightCtrl.dispose(); _heightCtrl.dispose();
    _myPhoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image =
          await ImagePicker().pickImage(source: ImageSource.gallery);
      if (image != null) setState(() => _avatarPath = image.path);
    } catch (_) {}
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    // Profil bilgilerini kaydet
    final profile = UserProfile(
      name: _nameCtrl.text.trim(),
      age: int.tryParse(_ageCtrl.text) ?? 30,
      weightKg: double.tryParse(_weightCtrl.text) ?? 70,
      heightCm: double.tryParse(_heightCtrl.text) ?? 170,
      chronicConditions: _selectedConditions.toList(),
      avatarPath: _avatarPath,
    );
    await context.read<MonitoringController>().saveProfile(profile);
    // Telefon numarasını kaydet
    if (_myPhoneCtrl.text.trim().isNotEmpty) {
      await StorageHelper.saveMyPhone(_myPhoneCtrl.text.trim());
    }
    setState(() { _saving = false; _isEditingInfo = false; _isEditingConditions = false; });
    _showSavedAnimation();
  }

  void _showSavedAnimation() {
    setState(() => _showSavedBadge = true);
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _showSavedBadge = false);
    });
  }

  void _openConditionDialog() {
    final searchCtrl = TextEditingController();
    List<Map<String, dynamic>> filtered = List.from(_kDiseaseList);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: AppTheme.bgCard,
          title: const Text('Kronik Hastalık Ekle',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                TextField(
                  controller: searchCtrl,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Hastalık ara...',
                    hintStyle: const TextStyle(color: AppTheme.textMuted),
                    prefixIcon: const Icon(Icons.search, color: AppTheme.textSecondary, size: 18),
                    filled: true,
                    fillColor: AppTheme.bgPrimary,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (val) {
                    setS(() {
                      filtered = _kDiseaseList
                          .where((d) => d['name']
                              .toString()
                              .toLowerCase()
                              .contains(val.toLowerCase()))
                          .toList();
                    });
                  },
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 280),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) =>
                        Divider(color: AppTheme.borderSubtle, height: 1),
                    itemBuilder: (_, i) {
                      final d = filtered[i];
                      final name = d['name'] as String;
                      final selected = _selectedConditions.contains(name);
                      return ListTile(
                        dense: true,
                        title: Text(name,
                            style: TextStyle(
                              color: selected
                                  ? AppTheme.primaryCyan
                                  : AppTheme.textPrimary,
                              fontSize: 13,
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            )),
                        trailing: selected
                            ? const Icon(Icons.check_circle,
                                color: AppTheme.primaryCyan, size: 18)
                            : null,
                        onTap: () {
                          setState(() {
                            if (selected) {
                              _selectedConditions.remove(name);
                            } else {
                              _selectedConditions.add(name);
                              // Nabız eşiklerini etkiliyor mu?
                              if (d['affectsHR'] == true) {
                                Future.delayed(
                                    const Duration(milliseconds: 300), () {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                            '💓 "$name" eklendi — Nabız uyarı eşiğiniz güncellendi.'),
                                        backgroundColor:
                                            AppTheme.primaryCyan.withOpacity(0.9),
                                        behavior: SnackBarBehavior.floating,
                                        shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12)),
                                        duration: const Duration(seconds: 3),
                                      ),
                                    );
                                  }
                                });
                              }
                            }
                          });
                          setS(() {});
                        },
                      );
                    },
                  ),
                ), // ConstrainedBox kapanıyor
                ],
              ),
            ),
            // SİNGLECHİLDSCROLLVİEW BURADA KAPANMALI!
          ), // BU PARANTEZİ EKLE (SizedBox veya SingleChildScrollView'ı kapatır)
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Tamam')),
          ],
        ), // AlertDialog kapanıyor
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      appBar: AppBar(
        title: const Text('Profil & Sağlık Bilgileri'),
      ),
      body: Stack(
        children: [
          Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── Avatar ──────────────────────────────────────────
                Center(
                  child: Stack(
                    children: [
                      GestureDetector(
                        onTap: _isEditingInfo ? _pickImage : null,
                        child: Container(
                          width: 88, height: 88,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppTheme.primaryCyan.withOpacity(0.1),
                            border: Border.all(color: AppTheme.primaryCyan, width: 2),
                            image: _avatarPath != null
                                ? DecorationImage(
                                    image: FileImage(File(_avatarPath!)),
                                    fit: BoxFit.cover)
                                : null,
                          ),
                          child: _avatarPath == null
                              ? const Icon(Icons.person, size: 48, color: AppTheme.primaryCyan)
                              : null,
                        ),
                      ),
                      if (_isEditingInfo)
                        Positioned(
                          right: 0, bottom: 0,
                          child: GestureDetector(
                            onTap: _pickImage,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryCyan,
                                shape: BoxShape.circle,
                                border: Border.all(color: AppTheme.bgPrimary, width: 2),
                              ),
                              child: const Icon(Icons.camera_alt, size: 14, color: Colors.white),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),

                // ── Kişisel Bilgiler Bölümü ──────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const _SectionHeader(title: 'Kişisel Bilgiler'),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: _isEditingInfo
                          ? _SaveButton(saving: _saving, onSave: _save, key: const ValueKey('save-info'))
                          : IconButton(
                              key: const ValueKey('edit-info'),
                              icon: const Icon(Icons.edit_outlined, color: AppTheme.primaryCyan, size: 20),
                              onPressed: () => setState(() => _isEditingInfo = true),
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                _buildField(controller: _nameCtrl, label: 'Ad Soyad', icon: Icons.person_outline, editing: _isEditingInfo),
                const SizedBox(height: 12),
                // Kendi telefon numaram (bildirim filtresi için)
                _buildField(
                  controller: _myPhoneCtrl,
                  label: 'Kendi Telefon Numaram (+90...)',
                  icon: Icons.phone_outlined,
                  editing: _isEditingInfo,
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: _buildField(controller: _ageCtrl, label: 'Yaş', icon: Icons.cake_outlined, keyboardType: TextInputType.number, editing: _isEditingInfo,
                    validator: (v) { final n = int.tryParse(v ?? ''); if (n == null || n < 1 || n > 120) return 'Geçersiz'; return null; })),
                  const SizedBox(width: 12),
                  Expanded(child: _buildField(controller: _weightCtrl, label: 'Kilo (kg)', icon: Icons.monitor_weight_outlined, keyboardType: TextInputType.number, editing: _isEditingInfo)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildField(controller: _heightCtrl, label: 'Boy (cm)', icon: Icons.height, keyboardType: TextInputType.number, editing: _isEditingInfo)),
                ]),
                const SizedBox(height: 24),

                // ── Kronik Hastalıklar Bölümü ────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const _SectionHeader(title: 'Kronik Hastalıklar'),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: _isEditingConditions
                          ? _SaveButton(saving: _saving, onSave: _save, key: const ValueKey('save-cond'))
                          : IconButton(
                              key: const ValueKey('edit-cond'),
                              icon: const Icon(Icons.edit_outlined, color: AppTheme.primaryCyan, size: 20),
                              onPressed: () => setState(() => _isEditingConditions = true),
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Seçilen hastalıklar nabız eşik değerlerini dinamik olarak etkiler.',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                ),
                const SizedBox(height: 12),

                Wrap(
                  spacing: 8, runSpacing: 8,
                  children: [
                    ..._selectedConditions.map((condition) => Chip(
                      label: Text(condition),
                      onDeleted: _isEditingConditions
                          ? () => setState(() => _selectedConditions.remove(condition))
                          : null,
                      backgroundColor: AppTheme.bgCard,
                      labelStyle: const TextStyle(color: AppTheme.primaryCyan, fontSize: 13),
                      side: BorderSide(color: AppTheme.primaryCyan.withOpacity(0.5)),
                    )),
                    if (_isEditingConditions)
                      ActionChip(
                        avatar: const Icon(Icons.add, size: 16, color: AppTheme.primaryCyan),
                        label: const Text('Ekle', style: TextStyle(color: AppTheme.primaryCyan)),
                        backgroundColor: AppTheme.bgCard,
                        side: BorderSide(color: AppTheme.primaryCyan.withOpacity(0.4)),
                        onPressed: _openConditionDialog,
                      ),
                  ],
                ),
                const SizedBox(height: 24),

                // Eşik önizleme
                _ThresholdPreview(
                  conditions: _selectedConditions.toList(),
                  age: int.tryParse(_ageCtrl.text) ?? 30,
                ),

                const SizedBox(height: 40),
                const _SectionHeader(title: 'Ayarlar'),
                const SizedBox(height: 12),
                _SettingsTile(icon: Icons.settings, title: 'Uygulama Ayarları',
                    onTap: () => _showMockDialog('Uygulama Ayarları', 'Bildirim ve sensör ayarları yakında.')),
                _SettingsTile(icon: Icons.contact_support, title: 'Bize Ulaşın / Geri Bildirim',
                    onTap: () => _showMockDialog('Bize Ulaşın', 'destek@vitalguard.com')),
                _SettingsTile(icon: Icons.delete_forever, title: 'Hesabımı Sil',
                    isDestructive: true,
                    onTap: () => _showMockDialog('Hesabımı Sil', 'Tüm verileriniz silinecek.', isDestructive: true)),
                const SizedBox(height: 40),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'Muhammet Ali Aslanhan - Bitirme Projesi',
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 12, fontStyle: FontStyle.italic),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── "Kaydedildi" Orta Ekran Animasyonu ──────────────────
          if (_showSavedBadge)
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.elasticOut,
                    builder: (_, val, child) => Transform.scale(
                      scale: val,
                      child: child,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F3D2E),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppTheme.accentGreen.withOpacity(0.6), width: 1.5),
                        boxShadow: [
                          BoxShadow(color: AppTheme.accentGreen.withOpacity(0.3), blurRadius: 30, spreadRadius: 4),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.check_circle_rounded, color: AppTheme.accentGreen, size: 48),
                          const SizedBox(height: 8),
                          const Text('Kaydedildi',
                              style: TextStyle(color: AppTheme.accentGreen, fontSize: 18, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showMockDialog(String title, String content, {bool isDestructive = false}) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: Text(title, style: TextStyle(color: isDestructive ? AppTheme.accentRed : AppTheme.textPrimary)),
        content: Text(content, style: const TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Kapat')),
          if (isDestructive)
            TextButton(onPressed: () => Navigator.pop(ctx),
                child: const Text('Sil', style: TextStyle(color: AppTheme.accentRed))),
        ],
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required bool editing,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      readOnly: !editing,
      style: TextStyle(color: editing ? AppTheme.textPrimary : AppTheme.textSecondary),
      decoration: InputDecoration(
        // FittedBox: küçük alanlarda (Yaş/Kilo/Boy yan yana) label kesilmez, küçülür
        label: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(label),
        ),
        prefixIcon: Icon(icon, size: 18, color: AppTheme.textSecondary),
        enabledBorder: editing ? null : const OutlineInputBorder(borderSide: BorderSide(color: Colors.transparent)),
        focusedBorder: editing ? null : const OutlineInputBorder(borderSide: BorderSide(color: Colors.transparent)),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  KAYDET BUTONU (AnimatedSwitcher ile kalem ↔ kaydet)
// ─────────────────────────────────────────────────────────────────────────────
class _SaveButton extends StatelessWidget {
  final bool saving;
  final VoidCallback onSave;
  const _SaveButton({required this.saving, required this.onSave, super.key});

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: saving ? null : onSave,
      icon: saving
          ? const SizedBox(width: 14, height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accentGreen))
          : const Icon(Icons.check, size: 16, color: AppTheme.accentGreen),
      label: const Text('Kaydet', style: TextStyle(color: AppTheme.accentGreen, fontWeight: FontWeight.w600)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  BÖLÜM BAŞLIĞI
// ─────────────────────────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 3, height: 18, color: AppTheme.primaryCyan,
            margin: const EdgeInsets.only(right: 10)),
        Text(title, style: const TextStyle(
          color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  EŞİK ÖNİZLEME
// ─────────────────────────────────────────────────────────────────────────────
class _ThresholdPreview extends StatelessWidget {
  final List<String> conditions;
  final int age;
  const _ThresholdPreview({required this.conditions, required this.age});

  @override
  Widget build(BuildContext context) {
    final profile = UserProfile(
        age: age, chronicConditions: conditions);
    final t = computeThresholds(profile);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primaryCyan.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.insights, color: AppTheme.primaryCyan, size: 16),
            SizedBox(width: 8),
            Text('Dinamik Nabız Eşikleri',
                style: TextStyle(color: AppTheme.primaryCyan, fontSize: 13, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 12),
          _TRow('İstirahat Maks.', '${t.restingMax} bpm', AppTheme.accentGreen),
          _TRow('Yürüyüş Maks.', '${t.walkingMax} bpm', AppTheme.accentGreen),
          _TRow('Koşu Maks.', '${t.runningMax} bpm', AppTheme.accentOrange),
          _TRow('Kritik Sınır', '${t.criticalMax} bpm', AppTheme.accentRed),
        ],
      ),
    );
  }
}

class _TRow extends StatelessWidget {
  final String label; final String value; final Color color;
  const _TRow(this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
      Text(value, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600)),
    ]),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  AYARLAR SATIRI
// ─────────────────────────────────────────────────────────────────────────────
class _SettingsTile extends StatelessWidget {
  final IconData icon; final String title;
  final VoidCallback onTap; final bool isDestructive;
  const _SettingsTile({required this.icon, required this.title, required this.onTap, this.isDestructive = false});
  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon, color: isDestructive ? AppTheme.accentRed : AppTheme.primaryCyan),
    title: Text(title, style: TextStyle(color: isDestructive ? AppTheme.accentRed : AppTheme.textPrimary)),
    trailing: const Icon(Icons.chevron_right, color: AppTheme.textMuted),
    onTap: onTap,
  );
}
