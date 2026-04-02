import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../auth/welcome_screen.dart';
import 'check_in_detail_screen.dart';

class CaregiverDashboardScreen extends StatefulWidget {
  const CaregiverDashboardScreen({super.key});

  @override
  State<CaregiverDashboardScreen> createState() => _CaregiverDashboardScreenState();
}

class _CaregiverDashboardScreenState extends State<CaregiverDashboardScreen> {
  bool _loading = true;
  String? _error;
  String? _seniorId;
  String? _seniorName;
  int _streak = 0;
  List<Map<String, dynamic>> _days = [];
  bool _hasLinkedSenior = false;

  final _inviteController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  @override
  void dispose() {
    _inviteController.dispose();
    super.dispose();
  }

  Future<void> _loadDashboard() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // For now, use the current user's ID as the senior to view their own dashboard,
      // or find linked senior. We'll try getting the user profile first.
      final profile = await ApiService.getUserProfile();

      if (profile['role'] == 'caregiver') {
        // Try to get linked seniors - use dashboard endpoint with own ID which will fail,
        // then we know we need to link. For a real implementation we'd need a
        // "get linked seniors" endpoint. For now, we'll use a stored seniorId.
        // Let's check if we have a senior linked by trying the summary endpoint.
        if (_seniorId == null) {
          setState(() {
            _loading = false;
            _hasLinkedSenior = false;
          });
          return;
        }
      } else {
        // Senior viewing own dashboard
        _seniorId = null; // Will use own UID
      }

      if (_seniorId != null) {
        await _fetchSeniorData(_seniorId!);
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Could not load dashboard.';
      });
    }
  }

  Future<void> _fetchSeniorData(String seniorId) async {
    try {
      final results = await Future.wait([
        ApiService.getDashboardSummary(seniorId),
        ApiService.getStreak(seniorId),
      ]);

      final summaryData = results[0];
      final streakData = results[1];

      setState(() {
        _days = (summaryData['days'] as List)
            .map((d) => Map<String, dynamic>.from(d))
            .toList();
        _streak = streakData['streak'] ?? 0;
        _hasLinkedSenior = true;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Could not load senior data.';
      });
    }
  }

  Future<void> _linkSenior() async {
    final code = _inviteController.text.trim();
    if (code.isEmpty) return;

    try {
      final result = await ApiService.linkSenior(code);
      final seniorId = result['seniorId'];
      if (seniorId != null) {
        setState(() => _seniorId = seniorId);
        await _fetchSeniorData(seniorId);
        _inviteController.clear();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invalid or expired invite code.', style: TextStyle(fontSize: 18)),
            backgroundColor: AppTheme.alertRed,
          ),
        );
      }
    }
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'on_time':
        return AppTheme.safeGreen;
      case 'late':
        return AppTheme.warningYellow;
      case 'missed':
        return AppTheme.alertRed;
      default:
        return Colors.grey[300]!;
    }
  }

  IconData _statusIcon(String? status) {
    switch (status) {
      case 'on_time':
        return Icons.check_circle;
      case 'late':
        return Icons.access_time;
      case 'missed':
        return Icons.cancel;
      default:
        return Icons.circle_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : !_hasLinkedSenior
                ? _buildLinkSeniorView()
                : RefreshIndicator(
                    onRefresh: () => _fetchSeniorData(_seniorId!),
                    child: ListView(
                      padding: const EdgeInsets.all(24),
                      children: [
                        _buildHeader(),
                        const SizedBox(height: 24),
                        _buildStreakCard(),
                        const SizedBox(height: 24),
                        _buildCalendarGrid(),
                        const SizedBox(height: 24),
                        _buildRecentActivity(),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Dashboard',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            if (_seniorName != null)
              Text(
                _seniorName!,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
          ],
        ),
        IconButton(
          icon: const Icon(Icons.logout, size: 28),
          tooltip: 'Sign Out',
          onPressed: () async {
            await Provider.of<AuthService>(context, listen: false).signOut();
            if (context.mounted) {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const WelcomeScreen()),
                (route) => false,
              );
            }
          },
        ),
      ],
    );
  }

  Widget _buildStreakCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(13),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppTheme.primaryGreen.withAlpha(26),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$_streak',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.safeGreen,
                ),
              ),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Day Streak',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                Text(
                  _streak > 0
                      ? 'Consecutive days checked in'
                      : 'No active streak',
                  style: const TextStyle(fontSize: 16, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarGrid() {
    // Build a 30-day grid going back from today
    final today = DateTime.now();
    final dayMap = <String, String>{};
    for (final d in _days) {
      dayMap[d['date']] = d['status'];
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Recent Check-ins',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
          ),
          itemCount: _days.isEmpty ? 7 : (_days.length > 30 ? 30 : _days.length + (7 - _days.length % 7) % 7),
          itemBuilder: (context, index) {
            final date = today.subtract(Duration(days: index));
            final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
            final status = dayMap[dateStr];

            return GestureDetector(
              onTap: status != null ? () => _onDayTapped(dateStr, status) : null,
              child: Semantics(
                label: '$dateStr: ${status ?? 'no data'}',
                child: Container(
                  decoration: BoxDecoration(
                    color: _statusColor(status),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${date.day}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: status != null ? Colors.white : AppTheme.textSecondary,
                          ),
                        ),
                        if (status != null)
                          Icon(
                            _statusIcon(status),
                            size: 14,
                            color: Colors.white,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        // Legend
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _legendItem(AppTheme.safeGreen, 'On time'),
            _legendItem(AppTheme.warningYellow, 'Late'),
            _legendItem(AppTheme.alertRed, 'Missed'),
            _legendItem(Colors.grey[300]!, 'No data'),
          ],
        ),
      ],
    );
  }

  Widget _legendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
      ],
    );
  }

  Widget _buildRecentActivity() {
    final recent = _days.take(5).toList();
    if (recent.isEmpty) {
      return const Text(
        'No check-in data yet.',
        style: TextStyle(fontSize: 18, color: AppTheme.textSecondary),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Recent Activity',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        ...recent.map((d) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Icon(
                  _statusIcon(d['status']),
                  color: _statusColor(d['status']),
                  size: 32,
                ),
                title: Text(d['date'] ?? '', style: const TextStyle(fontSize: 18)),
                subtitle: Text(
                  d['status'] == 'on_time'
                      ? 'Checked in on time'
                      : d['status'] == 'late'
                          ? 'Checked in late'
                          : 'Missed check-in',
                  style: const TextStyle(fontSize: 16),
                ),
                trailing: const Icon(Icons.chevron_right, size: 28),
                onTap: () => _onDayTapped(d['date'], d['status']),
              ),
            )),
      ],
    );
  }

  void _onDayTapped(String date, String status) {
    // Find the check-in for this date to get the ID
    final day = _days.firstWhere(
      (d) => d['date'] == date,
      orElse: () => {},
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CheckInDetailScreen(
          seniorId: _seniorId!,
          date: date,
          status: status,
          checkedInAt: day['checkedInAt'],
        ),
      ),
    );
  }

  Widget _buildLinkSeniorView() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.link, size: 80, color: AppTheme.primaryGreen),
          const SizedBox(height: 24),
          const Text(
            'Link a Senior',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          const Text(
            'Enter the invite code from your loved one to start monitoring their check-ins.',
            style: TextStyle(fontSize: 18, color: AppTheme.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          TextField(
            controller: _inviteController,
            style: const TextStyle(fontSize: 22, letterSpacing: 4),
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              hintText: 'INVITE CODE',
              hintStyle: const TextStyle(fontSize: 20, letterSpacing: 2),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _linkSenior,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryGreen,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Link', style: TextStyle(fontSize: 22)),
            ),
          ),
          const SizedBox(height: 24),
          TextButton(
            onPressed: () async {
              await Provider.of<AuthService>(context, listen: false).signOut();
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const WelcomeScreen()),
                  (route) => false,
                );
              }
            },
            child: const Text('Sign Out', style: TextStyle(fontSize: 18, color: AppTheme.alertRed)),
          ),
        ],
      ),
    );
  }
}
