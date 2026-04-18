import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../widgets/glass_card.dart';

class ReminderScreen extends StatefulWidget {
  const ReminderScreen({super.key});

  @override
  State<ReminderScreen> createState() => _ReminderScreenState();
}

class _ReminderScreenState extends State<ReminderScreen> {
  List<dynamic> _upcoming = [];
  List<dynamic> _todaySchedule = [];
  List<dynamic> _allEvents = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final reminders = await ApiService.getReminders(minutes: 1440);
      final events = await ApiService.getEvents();
      if (!mounted) return;
      setState(() {
        _upcoming = reminders['upcoming'] ?? [];
        _todaySchedule = reminders['todays_schedule'] ?? [];
        _allEvents = events['events'] ?? [];
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Plan'),
        actions: [
          IconButton(onPressed: _loadData, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: Color(0xFF888888),
                ),
              ),
            )
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 40,
                        color: Color(0xFF666666)),
                    const SizedBox(height: 8),
                    Text(
                      'Could not load reminders: $_error',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFF999999)),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _loadData,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadData,
              color: Colors.white,
              backgroundColor: const Color(0xFF1A1A1A),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
                children: [
                  Text(
                    'Stay ahead, not stressed.',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Auto reminders from your captured conversations.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 16),
                  _buildSection(
                    context,
                    title: 'Coming up (24h)',
                    subtitle: '${_upcoming.length} event(s)',
                    items: _upcoming,
                    emptyText: 'No upcoming reminders right now.',
                    showMinutes: true,
                  ),
                  const SizedBox(height: 14),
                  _buildSection(
                    context,
                    title: 'Today',
                    subtitle: '${_todaySchedule.length} item(s)',
                    items: _todaySchedule,
                    emptyText: 'No schedule for today.',
                  ),
                  const SizedBox(height: 14),
                  _buildSection(
                    context,
                    title: 'All memory events',
                    subtitle: '${_allEvents.length} stored',
                    items: _allEvents,
                    emptyText: 'No saved events yet.',
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Tip: pull down to refresh reminders after new conversations are saved.',
                    style: TextStyle(color: Color(0xFF666666)),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required String title,
    required String subtitle,
    required List<dynamic> items,
    required String emptyText,
    bool showMinutes = false,
  }) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 2),
          Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 12),
          if (items.isEmpty)
            Text(emptyText, style: Theme.of(context).textTheme.bodyLarge)
          else
            ...items.map(
              (item) => _buildEventTile(item, showMinutes: showMinutes),
            ),
        ],
      ),
    );
  }

  Widget _buildEventTile(dynamic item, {bool showMinutes = false}) {
    final type = (item['type'] ?? 'event').toString().toUpperCase();
    final desc = item['description'] ?? 'Unknown';
    final parsedDate = item['parsed_date'];
    final parsedTime = item['parsed_time'] ?? item['time'];
    final minsUntil = item['minutes_until'];

    IconData icon;
    Color color;
    switch (type) {
      case 'MEETING':
        icon = Icons.groups;
        color = const Color(0xFFCCCCCC);
        break;
      case 'TASK':
        icon = Icons.task_alt;
        color = const Color(0xFFAAAAAA);
        break;
      case 'MEDICATION':
        icon = Icons.medication;
        color = const Color(0xFFDDDDDD);
        break;
      default:
        icon = Icons.event;
        color = const Color(0xFF888888);
    }

    String subtitle = '';
    if (parsedDate != null) subtitle += 'Date: $parsedDate';
    if (parsedTime != null) subtitle += '   Time: $parsedTime';
    if (showMinutes && minsUntil != null) subtitle += '   In $minsUntil min';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D0D),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF222222),
          width: 0.5,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 19),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  desc.toString(),
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFF5F5F5),
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(subtitle, style: const TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFF888888),
                  )),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(type, style: TextStyle(
            fontSize: 11,
            color: color,
            fontWeight: FontWeight.w500,
          )),
        ],
      ),
    );
  }
}
