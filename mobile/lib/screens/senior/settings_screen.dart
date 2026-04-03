import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/subscription_service.dart';
import '../../theme/app_theme.dart';
import '../auth/welcome_screen.dart';
import '../paywall_screen.dart';

class SeniorSettingsScreen extends StatefulWidget {
  const SeniorSettingsScreen({super.key});

  @override
  State<SeniorSettingsScreen> createState() => _SeniorSettingsScreenState();
}

class _SeniorSettingsScreenState extends State<SeniorSettingsScreen> {
  bool _loading = true;
  TimeOfDay _windowStart = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _windowEnd = const TimeOfDay(hour: 10, minute: 0);
  bool _selfieEnabled = false;
  List<Map<String, dynamic>> _contacts = [];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final results = await Future.wait([
        ApiService.getSettings(),
        ApiService.getContacts(),
      ]);

      final settings = results[0]['settings'];
      final contacts = (results[1]['contacts'] as List)
          .map((c) => Map<String, dynamic>.from(c))
          .toList();

      if (settings != null) {
        final startParts = (settings['windowStart'] as String).split(':');
        final endParts = (settings['windowEnd'] as String).split(':');
        setState(() {
          _windowStart = TimeOfDay(
            hour: int.parse(startParts[0]),
            minute: int.parse(startParts[1]),
          );
          _windowEnd = TimeOfDay(
            hour: int.parse(endParts[0]),
            minute: int.parse(endParts[1]),
          );
          _selfieEnabled = settings['selfieEnabled'] ?? false;
          _contacts = contacts;
          _loading = false;
        });
      }
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _pickTime(bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _windowStart : _windowEnd,
    );
    if (picked == null) return;

    setState(() {
      if (isStart) {
        _windowStart = picked;
      } else {
        _windowEnd = picked;
      }
    });

    final startStr =
        '${_windowStart.hour.toString().padLeft(2, '0')}:${_windowStart.minute.toString().padLeft(2, '0')}';
    final endStr =
        '${_windowEnd.hour.toString().padLeft(2, '0')}:${_windowEnd.minute.toString().padLeft(2, '0')}';

    await ApiService.updateSettings({
      'windowStart': startStr,
      'windowEnd': endStr,
    });
  }

  Future<void> _showAddContactDialog() async {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final phoneController = TextEditingController();
    String relationship = 'Family';
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Contact', style: TextStyle(fontSize: 24)),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  style: const TextStyle(fontSize: 18),
                  decoration: const InputDecoration(labelText: 'Full Name'),
                  validator: (v) => v != null && v.trim().isNotEmpty ? null : 'Required',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(fontSize: 18),
                  decoration: const InputDecoration(labelText: 'Email'),
                  validator: (v) => v != null && RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(v) ? null : 'Valid email required',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(fontSize: 18),
                  decoration: const InputDecoration(labelText: 'Phone (optional)'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: relationship,
                  style: const TextStyle(fontSize: 18, color: AppTheme.textPrimary),
                  decoration: const InputDecoration(labelText: 'Relationship'),
                  items: const [
                    DropdownMenuItem(value: 'Family', child: Text('Family')),
                    DropdownMenuItem(value: 'Friend', child: Text('Friend')),
                    DropdownMenuItem(value: 'Neighbor', child: Text('Neighbor')),
                    DropdownMenuItem(value: 'Caregiver', child: Text('Caregiver')),
                    DropdownMenuItem(value: 'Other', child: Text('Other')),
                  ],
                  onChanged: (v) => relationship = v ?? 'Family',
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(fontSize: 18)),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(ctx, true);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGreen),
            child: const Text('Add', style: TextStyle(fontSize: 18, color: Colors.white)),
          ),
        ],
      ),
    );

    if (result == true) {
      try {
        await ApiService.addContact(
          fullName: nameController.text.trim(),
          email: emailController.text.trim(),
          phone: phoneController.text.trim().isEmpty ? null : phoneController.text.trim(),
          relationship: relationship,
        );
        await _loadSettings();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Contact added', style: TextStyle(fontSize: 18))),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not add contact. Free tier allows 1 contact.', style: TextStyle(fontSize: 18)),
              backgroundColor: AppTheme.alertRed,
            ),
          );
        }
      }
    }

    nameController.dispose();
    emailController.dispose();
    phoneController.dispose();
  }

  Future<bool> _confirmDeleteContact(Map<String, dynamic> contact) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Contact', style: TextStyle(fontSize: 24)),
        content: Text(
          'Remove ${contact['fullName']}? They will no longer be alerted.',
          style: const TextStyle(fontSize: 18),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(fontSize: 18)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.alertRed),
            child: const Text('Delete', style: TextStyle(fontSize: 18, color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true && contact['id'] != null) {
      try {
        await ApiService.deleteContact(contact['id']);
        await _loadSettings();
        return true;
      } catch (_) {}
    }
    return false;
  }

  String _formatTime(TimeOfDay t) {
    final hour = t.hour > 12 ? t.hour - 12 : (t.hour == 0 ? 12 : t.hour);
    final amPm = t.hour >= 12 ? 'PM' : 'AM';
    final min = t.minute.toString().padLeft(2, '0');
    return '$hour:$min $amPm';
  }

  Widget _buildSubscriptionSection(BuildContext context) {
    final sub = Provider.of<SubscriptionService>(context);

    if (sub.isSubscribed) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Subscription', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 12),
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
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Subscription', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 12),
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
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
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
                // Check-in window section
                Text(
                  'Check-in Window',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 16),
                _SettingsTile(
                  icon: Icons.access_time,
                  label: 'Window opens',
                  value: _formatTime(_windowStart),
                  onTap: () => _pickTime(true),
                ),
                const SizedBox(height: 12),
                _SettingsTile(
                  icon: Icons.access_time_filled,
                  label: 'Window closes',
                  value: _formatTime(_windowEnd),
                  onTap: () => _pickTime(false),
                ),

                const SizedBox(height: 32),

                // Contacts section
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Emergency Contacts',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle, size: 32, color: AppTheme.primaryGreen),
                      onPressed: _showAddContactDialog,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_contacts.isEmpty)
                  const Text(
                    'No contacts yet. Add someone to alert.',
                    style: TextStyle(fontSize: 18, color: AppTheme.textSecondary),
                  ),
                ..._contacts.map((c) => Dismissible(
                      key: Key(c['id'] ?? c['fullName']),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 24),
                        color: AppTheme.alertRed,
                        child: const Icon(Icons.delete, color: Colors.white, size: 32),
                      ),
                      confirmDismiss: (_) => _confirmDeleteContact(c),
                      child: Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: const Icon(Icons.person, size: 32),
                          title: Text(
                            c['fullName'] ?? '',
                            style: const TextStyle(fontSize: 20),
                          ),
                          subtitle: Text(
                            c['email'] ?? '',
                            style: const TextStyle(fontSize: 16),
                          ),
                          trailing: Text(
                            c['relationship'] ?? '',
                            style: const TextStyle(fontSize: 16, color: AppTheme.textSecondary),
                          ),
                        ),
                      ),
                    )),

                const SizedBox(height: 32),

                // Subscription section
                _buildSubscriptionSection(context),

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

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$label: $value',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: Row(
            children: [
              Icon(icon, size: 28, color: AppTheme.primaryGreen),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontSize: 20, color: AppTheme.textSecondary),
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
