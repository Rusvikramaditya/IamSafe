import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/api_service.dart';
import '../../services/subscription_service.dart';
import '../../theme/app_theme.dart';
import '../auth/welcome_screen.dart';
import '../paywall_screen.dart';

class CaregiverSettingsScreen extends StatefulWidget {
  const CaregiverSettingsScreen({super.key});

  @override
  State<CaregiverSettingsScreen> createState() => _CaregiverSettingsScreenState();
}

class _CaregiverSettingsScreenState extends State<CaregiverSettingsScreen> {
  bool _loading = true;
  String? _linkedSeniorName;
  String? _linkedSeniorId;
  final _inviteController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadLinkedSenior();
  }

  @override
  void dispose() {
    _inviteController.dispose();
    super.dispose();
  }

  Future<void> _loadLinkedSenior() async {
    try {
      final result = await ApiService.getLinkedSeniors();
      final seniors = result['seniors'] as List? ?? [];
      if (seniors.isNotEmpty && mounted) {
        setState(() {
          _linkedSeniorId = seniors[0]['seniorId'];
          _linkedSeniorName = seniors[0]['fullName'] ?? 'Linked Senior';
          _loading = false;
        });
        return;
      }
    } catch (_) {
      // Network error — show empty state
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _linkSenior() async {
    final code = _inviteController.text.trim();
    if (code.isEmpty) return;

    try {
      final result = await ApiService.linkSenior(code);
      final seniorId = result['seniorId'] as String?;
      if (seniorId != null && mounted) {
        setState(() {
          _linkedSeniorId = seniorId;
          _linkedSeniorName = result['seniorName'] as String? ?? 'Linked Senior';
        });
        _inviteController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Senior linked successfully!', style: TextStyle(fontSize: 18)),
            backgroundColor: AppTheme.safeGreen,
          ),
        );
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
    final sub = Provider.of<SubscriptionService>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                // Linked seniors section
                Text(
                  'Linked Seniors',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 16),
                if (_linkedSeniorId != null)
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.person, size: 32, color: AppTheme.primaryGreen),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            _linkedSeniorName ?? 'Senior',
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                          ),
                        ),
                        const Icon(Icons.check_circle, color: AppTheme.safeGreen, size: 28),
                      ],
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'No senior linked yet.',
                          style: TextStyle(fontSize: 18, color: AppTheme.textSecondary),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _inviteController,
                          style: const TextStyle(fontSize: 20, letterSpacing: 3),
                          textAlign: TextAlign.center,
                          decoration: InputDecoration(
                            hintText: 'INVITE CODE',
                            hintStyle: const TextStyle(fontSize: 18, letterSpacing: 2),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _linkSenior,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryGreen,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text('Link Senior', style: TextStyle(fontSize: 20)),
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 32),

                // Subscription section
                Text(
                  'Subscription',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 16),
                if (sub.isSubscribed)
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryGreen.withAlpha(20),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.primaryGreen),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.star_rounded, color: AppTheme.primaryGreen, size: 32),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            sub.isFamily ? 'Family Plan' : 'Premium Plan',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.safeGreen,
                            ),
                          ),
                        ),
                        const Icon(Icons.check_circle, color: AppTheme.safeGreen, size: 28),
                      ],
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Free Plan',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Upgrade to get SMS alerts, unlimited history, and more.',
                          style: TextStyle(fontSize: 18, color: AppTheme.textSecondary),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: () => PaywallScreen.show(context),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryGreen,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'Upgrade to Premium',
                              style: TextStyle(fontSize: 20),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 32),

                // Sign out
                SizedBox(
                  height: 56,
                  child: OutlinedButton(
                    onPressed: () async {
                      await Provider.of<AuthService>(context, listen: false).signOut();
                      if (context.mounted) {
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(builder: (_) => const WelcomeScreen()),
                          (route) => false,
                        );
                      }
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.alertRed,
                      side: const BorderSide(color: AppTheme.alertRed),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Sign Out', style: TextStyle(fontSize: 20)),
                  ),
                ),
              ],
            ),
    );
  }
}
