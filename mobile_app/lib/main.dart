import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/home_screen.dart';
import 'screens/insights_screen.dart';
import 'screens/onboarding/first_time_tour_screen.dart';
import 'screens/query_screen.dart';
import 'screens/reminder_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/splash_screen.dart';
import 'services/reminder_notification_service.dart';
import 'theme/app_theme.dart';
import 'widgets/nebula_background.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ReminderNotificationService.instance.initialize();
  runApp(const MemoryAssistantApp());
}

class MemoryAssistantApp extends StatelessWidget {
  const MemoryAssistantApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MIRA',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      home: const LaunchGate(),
    );
  }
}

class LaunchGate extends StatefulWidget {
  const LaunchGate({super.key});

  @override
  State<LaunchGate> createState() => _LaunchGateState();
}

class _LaunchGateState extends State<LaunchGate> {
  bool _showSplash = true;
  bool _needsTour = false;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _loadLaunchState();
  }

  Future<void> _loadLaunchState() async {
    final prefs = await SharedPreferences.getInstance();
    final seenTour = prefs.getBool('has_seen_tour_v2') ?? false;
    if (!mounted) return;
    setState(() {
      _needsTour = !seenTour;
      _ready = true;
    });
  }

  Future<void> _completeTour() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_seen_tour_v2', true);
    if (!mounted) return;
    setState(() => _needsTour = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready || _showSplash) {
      return SplashScreen(
        onComplete: () => setState(() => _showSplash = false),
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeIn,
      child: _needsTour
          ? FirstTimeTourScreen(
              key: const ValueKey('tour'),
              onFinished: _completeTour,
            )
          : const MainNavigation(key: ValueKey('main')),
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

  List<Widget> _buildScreens() {
    return [
      const HomeScreen(),
      const InsightsScreen(),
      const QueryScreen(),
      const ReminderScreen(),
      const SettingsScreen(),
    ];
  }

  @override
  void initState() {
    super.initState();
    ReminderNotificationService.instance.startMonitoring();
  }

  @override
  void dispose() {
    ReminderNotificationService.instance.stopMonitoring();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screens = _buildScreens();

    return Scaffold(
      extendBody: true,
      body: NebulaBackground(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 360),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, animation) {
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.04, 0),
                  end: Offset.zero,
                ).animate(CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutCubic,
                )),
                child: child,
              ),
            );
          },
          child: KeyedSubtree(
            key: ValueKey(_currentIndex),
            child: screens[_currentIndex],
          ),
        ),
      ),
      bottomNavigationBar: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 28.0, sigmaY: 28.0),
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xC0080808),
                  Color(0xE6030303),
                ],
              ),
              border: Border(
                top: BorderSide(color: Color(0x18FFFFFF), width: 0.5),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 10, 6, 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _NavItem(
                      index: 0,
                      currentIndex: _currentIndex,
                      icon: Icons.fiber_manual_record_outlined,
                      activeIcon: Icons.fiber_manual_record_rounded,
                      label: 'Capture',
                      onTap: () => setState(() => _currentIndex = 0),
                    ),
                    _NavItem(
                      index: 1,
                      currentIndex: _currentIndex,
                      icon: Icons.auto_awesome_outlined,
                      activeIcon: Icons.auto_awesome_rounded,
                      label: 'Insights',
                      onTap: () => setState(() => _currentIndex = 1),
                    ),
                    _NavItem(
                      index: 2,
                      currentIndex: _currentIndex,
                      icon: Icons.forum_outlined,
                      activeIcon: Icons.forum_rounded,
                      label: 'Ask',
                      onTap: () => setState(() => _currentIndex = 2),
                    ),
                    _NavItem(
                      index: 3,
                      currentIndex: _currentIndex,
                      icon: Icons.event_note_outlined,
                      activeIcon: Icons.event_note_rounded,
                      label: 'Agenda',
                      onTap: () => setState(() => _currentIndex = 3),
                    ),
                    _NavItem(
                      index: 4,
                      currentIndex: _currentIndex,
                      icon: Icons.person_outline_rounded,
                      activeIcon: Icons.person_rounded,
                      label: 'Profile',
                      onTap: () => setState(() => _currentIndex = 4),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Custom premium bottom nav item with animated indicator and icon transitions.
class _NavItem extends StatelessWidget {
  final int index;
  final int currentIndex;
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final VoidCallback onTap;

  const _NavItem({
    required this.index,
    required this.currentIndex,
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = index == currentIndex;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Animated icon with scale
            AnimatedScale(
              scale: isActive ? 1.15 : 1.0,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: Icon(
                  isActive ? activeIcon : icon,
                  key: ValueKey('${index}_$isActive'),
                  size: 23,
                  color: isActive
                      ? const Color(0xFFFFFFFF)
                      : const Color(0xFF555555),
                ),
              ),
            ),
            const SizedBox(height: 5),
            // Label
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 220),
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive
                    ? const Color(0xFFFFFFFF)
                    : const Color(0xFF555555),
                letterSpacing: 0.3,
              ),
              child: Text(label),
            ),
            const SizedBox(height: 4),
            // Active indicator dot
            AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              width: isActive ? 18 : 0,
              height: 2.5,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                gradient: isActive
                    ? const LinearGradient(
                        colors: [
                          Color(0xFF96E6FF),
                          Color(0xFFC084FC),
                          Color(0xFFFB7185),
                        ],
                      )
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
