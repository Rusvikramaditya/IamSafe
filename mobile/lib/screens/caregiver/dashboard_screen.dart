import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/status_helpers.dart';
import '../auth/welcome_screen.dart';
import 'check_in_detail_screen.dart';
import 'settings_screen.dart';

class CaregiverDashboardScreen extends StatefulWidget {
  const CaregiverDashboardScreen({super.key});

  @override
  State<CaregiverDashboardScreen> createState() => _CaregiverDashboardScreenState();
}

class _CaregiverDashboardScreenState extends State<CaregiverDashboardScreen> {
  static const _storage = FlutterSecureStorage();
  static const _seniorIdKey = 'linked_senior_id';
  static const _seniorNameKey = 'linked_senior_name';

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
      // First try to get linked seniors from the backend
      final linkedResult = await ApiService.getLinkedSeniors();
      final seniors = linkedResult['seniors'] as List? ?? [];

      if (seniors.isNotEmpty) {
        final senior = seniors[0]; // Use first linked senior
        _seniorId = senior['seniorId'];
        _seniorName = senior['fullName'];

        // Persist for offline access
        if (_seniorId != null) {
          await _storage.write(key: _seniorIdKey, value: _seniorId!);
          await _storage.write(key: _seniorNameKey, value: _seniorName ?? '');
        }

        await _fetchSeniorData(_seniorId!);
        return;
      }

      // No linked seniors on backend — try cached ID
      final cachedId = await _storage.read(key: _seniorIdKey);
      if (cachedId != null) {
        _seniorId = cachedId;
        _seniorName = await _storage.read(key: _seniorNameKey);
        await _fetchSeniorData(cachedId);
        return;
      }

      // No seniors found at all
      setState(() {
        _loading = false;
        _hasLinkedSenior = false;
      });
    } catch (e) {
      // Try cached senior ID on network error
      try {
        final cachedId = await _storage.read(key: _seniorIdKey);
        if (cachedId != null) {
          _seniorId = cachedId;
          _seniorName = await _storage.read(key: _seniorNameKey);
          await _fetchSeniorData(cachedId);
          return;
        }
      } catch (_) {}

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
      final seniorId = result['seniorId'] as String?;
      final seniorName = result['seniorName'] as String?;

      if (seniorId != null) {
        // Persist the linked senior
        await _storage.write(key: _seniorIdKey, value: seniorId);
        await _storage.write(key: _seniorNameKey, value: seniorName ?? '');

        setState(() {
          _seniorId = seniorId;
          _seniorName = seniorName;
        });
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _buildErrorView()
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

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: AppTheme.alertRed),
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(fontSize: 20), textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadDashboard,
              child: const Text('Retry', style: TextStyle(fontSize: 18)),
            ),
          ],
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
          icon: const Icon(Icons.settings, size: 28),
          tooltip: 'Settings',
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CaregiverSettingsScreen()),
            );
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
    // Build a date-ordered grid from the _days data
    final dayMap = <String, Map<String, dynamic>>{};
    for (final d in _days) {
      dayMap[d['date']] = d;
    }

    // Show last 28 days (4 rows of 7) for a clean grid
    final today = DateTime.now();
    const gridDays = 28;

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
          itemCount: gridDays,
          itemBuilder: (context, index) {
            // Oldest first: item 0 = 27 days ago, item 27 = today
            final date = today.subtract(Duration(days: gridDays - 1 - index));
            final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
            final dayData = dayMap[dateStr];
            final status = dayData?['status'] as String?;

            return GestureDetector(
              onTap: dayData != null
                  ? () => _onDayTapped(dateStr, status ?? 'unknown', dayData)
                  : null,
              child: Semantics(
                label: '$dateStr: ${status ?? 'no data'}',
                child: Container(
                  decoration: BoxDecoration(
                    color: StatusHelpers.statusColor(status),
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
                            StatusHelpers.statusIcon(status),
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
                  StatusHelpers.statusIcon(d['status']),
                  color: StatusHelpers.statusColor(d['status']),
                  size: 32,
                ),
                title: Text(d['date'] ?? '', style: const TextStyle(fontSize: 18)),
                subtitle: Text(
                  StatusHelpers.statusLabel(d['status']),
                  style: const TextStyle(fontSize: 16),
                ),
                trailing: const Icon(Icons.chevron_right, size: 28),
                onTap: () => _onDayTapped(d['date'], d['status'], d),
              ),
            )),
      ],
    );
  }

  void _onDayTapped(String date, String status, Map<String, dynamic> dayData) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CheckInDetailScreen(
          seniorId: _seniorId!,
          date: date,
          status: status,
          checkedInAt: dayData['checkedInAt'],
          checkInId: dayData['checkInId'],
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
