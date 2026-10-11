import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import '../app_theme.dart';
import '../models/emergency_contact.dart';
import '../services/monitoring_controller.dart';

class EmergencyContactsScreen extends StatefulWidget {
  const EmergencyContactsScreen({super.key});

  @override
  State<EmergencyContactsScreen> createState() =>
      _EmergencyContactsScreenState();
}

class _EmergencyContactsScreenState extends State<EmergencyContactsScreen> {
  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<MonitoringController>();
    final contacts = ctrl.contacts;

    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      appBar: AppBar(
        title: const Text('Acil Durum Kişileri'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddDialog(context, ctrl),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Ekle'),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      body: contacts.isEmpty
          ? _EmptyState()
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: contacts.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _ContactCard(
                contact: contacts[i],
                onDelete: () async {
                  final updated = List<EmergencyContact>.from(contacts)
                    ..removeAt(i);
                  await ctrl.saveContacts(updated);
                },
                onEdit: () => _showEditDialog(context, ctrl, contacts[i], i),
              ),
            ),
    );
  }

  void _showAddDialog(BuildContext context, MonitoringController ctrl) async {
    try {
      if (await FlutterContacts.requestPermission(readonly: true)) {
        final contact = await FlutterContacts.openExternalPick();
        if (contact != null) {
          final fullContact = await FlutterContacts.getContact(contact.id);
          if (fullContact != null && fullContact.phones.isNotEmpty) {
            final phone = fullContact.phones.first.number;
            _showContactDialog(
              context: context,
              title: 'Acil Kişi Ekle',
              initial: EmergencyContact(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                name: fullContact.displayName,
                phone: phone,
                relation: '',
              ),
              onSave: (c) async {
                // Yeni kişi birincilse, mevcut listedeki birincilleri temizle
                final base = c.isPrimaryCaller
                    ? ctrl.contacts
                        .map((e) => EmergencyContact(
                              id: e.id,
                              name: e.name,
                              phone: e.phone,
                              relation: e.relation,
                              isPrimaryCaller: false,
                            ))
                        .toList()
                    : List<EmergencyContact>.from(ctrl.contacts);
                await ctrl.saveContacts([...base, c]);
              },
            );
            return;
          }
        }
      }
    } catch (_) {}

    // Manuel Giriş Fallback
    _showContactDialog(
      context: context,
      title: 'Acil Kişi Ekle',
      onSave: (c) async {
        final base = c.isPrimaryCaller
            ? ctrl.contacts
                .map((e) => EmergencyContact(
                      id: e.id,
                      name: e.name,
                      phone: e.phone,
                      relation: e.relation,
                      isPrimaryCaller: false,
                    ))
                .toList()
            : List<EmergencyContact>.from(ctrl.contacts);
        await ctrl.saveContacts([...base, c]);
      },
    );
  }

  void _showEditDialog(
    BuildContext context,
    MonitoringController ctrl,
    EmergencyContact existing,
    int index,
  ) {
    _showContactDialog(
      context: context,
      title: 'Kişiyi Düzenle',
      initial: existing,
      onSave: (contact) async {
        // Düzenlenen kişi birincil işaretlendiyse diğerlerini sıfırla
        final updated = ctrl.contacts.asMap().entries.map((entry) {
          if (entry.key == index) return contact;
          if (contact.isPrimaryCaller) {
            return EmergencyContact(
              id: entry.value.id,
              name: entry.value.name,
              phone: entry.value.phone,
              relation: entry.value.relation,
              isPrimaryCaller: false,
            );
          }
          return entry.value;
        }).toList();
        await ctrl.saveContacts(updated);
      },
    );
  }

  void _showContactDialog({
    required BuildContext context,
    required String title,
    EmergencyContact? initial,
    required Future<void> Function(EmergencyContact) onSave,
  }) {
    final nameCtrl = TextEditingController(text: initial?.name ?? '');
    final phoneCtrl = TextEditingController(text: initial?.phone ?? '');
    final relationCtrl = TextEditingController(text: initial?.relation ?? '');

    bool isPrimary = initial?.isPrimaryCaller ?? false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateBuilder) => AlertDialog(
          backgroundColor: AppTheme.bgCard,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          title: Text(title, style: const TextStyle(color: AppTheme.textPrimary)),
          content: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _DialogField(controller: nameCtrl, label: 'Ad Soyad', icon: Icons.person_outline),
                  const SizedBox(height: 12),
                  _DialogField(controller: phoneCtrl, label: 'Telefon', icon: Icons.phone_outlined, keyboardType: TextInputType.phone),
                  const SizedBox(height: 12),
                  _DialogField(controller: relationCtrl, label: 'Yakınlık (ör. Eş)', icon: Icons.people_outline),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('Acil Durumda İlk Bu Kişiyi Ara', style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
                    activeColor: AppTheme.primaryCyan,
                    value: isPrimary,
                    onChanged: (val) => setStateBuilder(() => isPrimary = val),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
          ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('İptal',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.isEmpty || phoneCtrl.text.isEmpty) return;
              await onSave(EmergencyContact(
                id: initial?.id ??
                    DateTime.now().millisecondsSinceEpoch.toString(),
                name: nameCtrl.text.trim(),
                phone: phoneCtrl.text.trim(),
                relation: relationCtrl.text.trim(),
                isPrimaryCaller: isPrimary,
              ));
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  final EmergencyContact contact;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  const _ContactCard({
    required this.contact,
    required this.onDelete,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderSubtle),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppTheme.primaryCyan, AppTheme.primaryBlue],
              ),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                contact.name.isNotEmpty
                    ? contact.name[0].toUpperCase()
                    : '?',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  contact.name,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (contact.isPrimaryCaller) ...[
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryCyan.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'Birincil Arama',
                      style: TextStyle(color: AppTheme.primaryCyan, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  contact.phone,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                  ),
                ),
                if (contact.relation.isNotEmpty)
                  Text(
                    contact.relation,
                    style: const TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined,
                color: AppTheme.textSecondary, size: 20),
            onPressed: onEdit,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline,
                color: AppTheme.accentRed, size: 20),
            onPressed: () => _confirmDelete(context),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text('Kişiyi Sil',
            style: TextStyle(color: AppTheme.textPrimary)),
        content: Text(
          '${contact.name} acil kişiler listesinden silinecek.',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () {
              onDelete();
              Navigator.pop(context);
            },
            child: const Text('Sil',
                style: TextStyle(color: AppTheme.accentRed)),
          ),
        ],
      ),
    );
  }
}

class _DialogField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType keyboardType;

  const _DialogField({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboardType = TextInputType.text,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(color: AppTheme.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 18, color: AppTheme.textSecondary),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppTheme.accentRed.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.person_add_disabled,
                color: AppTheme.accentRed, size: 40),
          ),
          const SizedBox(height: 20),
          const Text(
            'Acil kişi eklenmemiş',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Anomali durumunda SMS ve arama\nyapılacak kişileri ekleyin.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
