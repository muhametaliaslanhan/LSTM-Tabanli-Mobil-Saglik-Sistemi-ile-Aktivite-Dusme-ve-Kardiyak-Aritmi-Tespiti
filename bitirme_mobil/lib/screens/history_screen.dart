// lib/screens/history_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app_theme.dart';
import '../models/sensor_data.dart';
import '../services/monitoring_controller.dart';
import 'emergency_chat_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final Set<String> _selectedIds = {};
  bool get _isSelectionMode => _selectedIds.isNotEmpty;

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedIds.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final events = context.watch<MonitoringController>().eventHistory;

    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      appBar: AppBar(
        title: Text(_isSelectionMode ? '${_selectedIds.length} Seçildi' : 'Olay Geçmişi'),
        backgroundColor: _isSelectionMode ? AppTheme.primaryCyan.withOpacity(0.2) : null,
        leading: _isSelectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _clearSelection,
              )
            : null,
        actions: [
          if (_isSelectionMode)
            IconButton(
              icon: const Icon(Icons.delete, color: AppTheme.accentRed),
              tooltip: 'Seçilenleri Sil',
              onPressed: () {
                final newHistory = events.where((e) => !_selectedIds.contains(e.timestamp.toString())).toList();
                context.read<MonitoringController>().updateHistory(newHistory);
                _clearSelection();
              },
            )
          else if (events.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep, color: AppTheme.accentRed),
              tooltip: 'Tümünü Temizle',
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: AppTheme.bgCard,
                    title: const Text('Geçmişi Temizle', style: TextStyle(color: AppTheme.textPrimary)),
                    content: const Text('Tüm olay geçmişini silmek istediğinize emin misiniz?', style: TextStyle(color: AppTheme.textSecondary)),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('İptal', style: TextStyle(color: AppTheme.textSecondary)),
                      ),
                      TextButton(
                        onPressed: () {
                          context.read<MonitoringController>().clearHistory();
                          Navigator.pop(ctx);
                        },
                        child: const Text('Sil', style: TextStyle(color: AppTheme.accentRed)),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
      body: events.isEmpty
          ? _EmptyHistory()
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: events.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final eventId = events[i].timestamp.toString();
                final isSelected = _selectedIds.contains(eventId);
                
                return Dismissible(
                  key: ValueKey(eventId),
                  direction: _isSelectionMode ? DismissDirection.none : DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    decoration: BoxDecoration(
                      color: AppTheme.accentRed,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  onDismissed: (direction) {
                    final newHistory = List<AnomalyEvent>.from(events)..removeAt(i);
                    context.read<MonitoringController>().updateHistory(newHistory);
                  },
                  child: GestureDetector(
                    onLongPress: () => _toggleSelection(eventId),
                    onTap: () {
                      if (_isSelectionMode) {
                        _toggleSelection(eventId);
                      }
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: isSelected ? Border.all(color: AppTheme.primaryCyan, width: 2) : null,
                      ),
                      child: Row(
                        children: [
                          if (_isSelectionMode)
                            Checkbox(
                              value: isSelected,
                              onChanged: (_) => _toggleSelection(eventId),
                              activeColor: AppTheme.primaryCyan,
                            ),
                          Expanded(child: _HistoryCard(event: events[i])),
                          // ── Aksiyon butonları — kart dışında, overflow yaratmaz ──
                          if (events[i].latitude != null)
                            IconButton(
                              icon: const Icon(Icons.location_on_outlined,
                                  color: AppTheme.primaryCyan, size: 20),
                              tooltip: 'Haritada Aç',
                              onPressed: () async {
                                final uri = Uri.parse(
                                    'https://maps.google.com/?q=${events[i].latitude},${events[i].longitude}');
                                if (await canLaunchUrl(uri)) {
                                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                                }
                              },
                            ),
                          IconButton(
                            icon: const Icon(Icons.chat_bubble_outline,
                                color: AppTheme.primaryCyan, size: 20),
                            tooltip: 'Sohbeti Gör',
                            onPressed: () {
                              final contacts = context.read<MonitoringController>().contacts;
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => EmergencyChatScreen(
                                    event: events[i],
                                    contacts: contacts,
                                    isHistoricalView: true, // Otomatik arama YAPILMAZ
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final AnomalyEvent event;
  const _HistoryCard({required this.event});

  Color _getColor() {
    switch (event.type) {
      case AnomalyType.fall:
        return AppTheme.accentOrange;
      case AnomalyType.heartRateAnomaly:
        return AppTheme.accentRed;
      case AnomalyType.impact:
        return AppTheme.accentYellow;
      case AnomalyType.arrhythmia:
        return AppTheme.primaryCyan;
    }
  }

  IconData _getIcon() {
    switch (event.type) {
      case AnomalyType.fall:
        return Icons.personal_injury;
      case AnomalyType.heartRateAnomaly:
        return Icons.favorite;
      case AnomalyType.impact:
        return Icons.bolt;
      case AnomalyType.arrhythmia:
        return Icons.monitor_heart;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _getColor();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            color.withOpacity(0.05),
            AppTheme.bgCard,
          ],
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(_getIcon(), color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.typeLabel,
                  style: TextStyle(
                    color: color,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  event.description,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.access_time,
                        size: 11, color: AppTheme.textMuted),
                    const SizedBox(width: 4),
                    Text(
                      _formatDateTime(event.timestamp),
                      style: const TextStyle(
                          color: AppTheme.textMuted, fontSize: 11),
                    ),
                    if (event.confidence != null) ...[
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '%${(event.confidence! * 100).toStringAsFixed(0)}',
                          style: TextStyle(
                              color: color,
                              fontSize: 10,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/'
        '${dt.month.toString().padLeft(2, '0')}/'
        '${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _EmptyHistory extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history_toggle_off,
              size: 64, color: AppTheme.textMuted),
          SizedBox(height: 16),
          Text(
            'Olay Geçmişi Boş',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'İzleme aktifken tespit edilen\nanomali olayları burada görünür.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
