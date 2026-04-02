import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../senior/home_screen.dart';

class SetupWizardScreen extends StatefulWidget {
  final String email;
  final String? fullName;

  const SetupWizardScreen({super.key, required this.email, this.fullName});

  @override
  State<SetupWizardScreen> createState() => _SetupWizardScreenState();
}

class _SetupWizardScreenState extends State<SetupWizardScreen> {
  int _step = 0;
  bool _loading = false;
  String? _error;

  // Step 1: Role
  String _role = 'senior';

  // Step 2: Name & phone
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  // Step 3: Check-in window (senior only)
  TimeOfDay _windowStart = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _windowEnd = const TimeOfDay(hour: 10, minute: 0);

  // Step 4: Add first contact (senior only)
  final _contactNameController = TextEditingController();
  final _contactEmailController = TextEditingController();
  final _contactRelationController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.fullName != null && widget.fullName!.isNotEmpty) {
      _nameController.text = widget.fullName!;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _contactNameController.dispose();
    _contactEmailController.dispose();
    _contactRelationController.dispose();
    super.dispose();
  }

  int get _totalSteps => _role == 'senior' ? 4 : 2;

  Future<void> _next() async {
    if (_step == 0) {
      setState(() => _step = 1);
      return;
    }

    if (_step == 1) {
      if (_nameController.text.trim().isEmpty) {
        setState(() => _error = 'Please enter your name');
        return;
      }

      setState(() {
        _loading = true;
        _error = null;
      });

      try {
        await Provider.of<AuthService>(context, listen: false).registerProfile(
          fullName: _nameController.text.trim(),
          email: widget.email,
          phone: _phoneController.text.trim().isNotEmpty
              ? _phoneController.text.trim()
              : null,
          role: _role,
        );

        if (_role == 'caregiver') {
          _finish();
          return;
        }

        setState(() => _step = 2);
      } catch (e) {
        setState(() => _error = 'Setup failed. Please try again.');
      } finally {
        if (mounted) setState(() => _loading = false);
      }
      return;
    }

    if (_step == 2) {
      // Save check-in window settings
      setState(() {
        _loading = true;
        _error = null;
      });

      try {
        final startStr =
            '${_windowStart.hour.toString().padLeft(2, '0')}:${_windowStart.minute.toString().padLeft(2, '0')}';
        final endStr =
            '${_windowEnd.hour.toString().padLeft(2, '0')}:${_windowEnd.minute.toString().padLeft(2, '0')}';

        await ApiService.updateSettings({
          'windowStart': startStr,
          'windowEnd': endStr,
        });

        setState(() => _step = 3);
      } catch (e) {
        setState(() => _error = 'Failed to save settings.');
      } finally {
        if (mounted) setState(() => _loading = false);
      }
      return;
    }

    if (_step == 3) {
      // Add first emergency contact
      if (_contactNameController.text.trim().isNotEmpty &&
          _contactEmailController.text.trim().isNotEmpty) {
        setState(() {
          _loading = true;
          _error = null;
        });

        try {
          await ApiService.addContact(
            fullName: _contactNameController.text.trim(),
            email: _contactEmailController.text.trim(),
            relationship: _contactRelationController.text.trim().isNotEmpty
                ? _contactRelationController.text.trim()
                : null,
          );
        } catch (e) {
          // Non-blocking — they can add contacts later
        } finally {
          if (mounted) setState(() => _loading = false);
        }
      }

      _finish();
    }
  }

  void _finish() {
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const SeniorHomeScreen()),
        (route) => false,
      );
    }
  }

  Future<void> _pickTime(bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _windowStart : _windowEnd,
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _windowStart = picked;
        } else {
          _windowEnd = picked;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Setup (${_step + 1} of $_totalSteps)'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Progress indicator
              LinearProgressIndicator(
                value: (_step + 1) / _totalSteps,
                backgroundColor: Colors.grey[300],
                valueColor: const AlwaysStoppedAnimation(AppTheme.primaryGreen),
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
              ),

              const SizedBox(height: 32),

              Expanded(child: _buildStep()),

              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      color: AppTheme.alertRed,
                      fontSize: AppTheme.fontSmall,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),

              SizedBox(
                height: 60,
                child: ElevatedButton(
                  onPressed: _loading ? null : _next,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _loading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(
                          _step == _totalSteps - 1 ? 'Finish' : 'Next',
                          style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.w600),
                        ),
                ),
              ),

              if (_step == 3)
                TextButton(
                  onPressed: _finish,
                  child: const Text(
                    'Skip for now',
                    style: TextStyle(fontSize: AppTheme.fontSmall),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 0:
        return _buildRoleStep();
      case 1:
        return _buildProfileStep();
      case 2:
        return _buildWindowStep();
      case 3:
        return _buildContactStep();
      default:
        return const SizedBox();
    }
  }

  Widget _buildRoleStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('I am a...', style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 32),
        _RoleCard(
          icon: Icons.person,
          title: 'Senior',
          subtitle: 'I want to check in daily',
          selected: _role == 'senior',
          onTap: () => setState(() => _role = 'senior'),
        ),
        const SizedBox(height: 16),
        _RoleCard(
          icon: Icons.favorite,
          title: 'Caregiver',
          subtitle: 'I want to monitor a loved one',
          selected: _role == 'caregiver',
          onTap: () => setState(() => _role = 'caregiver'),
        ),
      ],
    );
  }

  Widget _buildProfileStep() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Your details', style: Theme.of(context).textTheme.headlineLarge),
          const SizedBox(height: 32),
          TextFormField(
            controller: _nameController,
            style: const TextStyle(fontSize: AppTheme.fontBody),
            decoration: const InputDecoration(
              labelText: 'Full Name',
              prefixIcon: Icon(Icons.person_outline, size: 28),
            ),
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            style: const TextStyle(fontSize: AppTheme.fontBody),
            decoration: const InputDecoration(
              labelText: 'Phone (optional)',
              prefixIcon: Icon(Icons.phone_outlined, size: 28),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWindowStep() {
    String formatTime(TimeOfDay t) =>
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Check-in window',
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 12),
        Text(
          'Choose a daily time window when you will tap the safety button.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 40),
        _TimePickerTile(
          label: 'Window opens',
          time: formatTime(_windowStart),
          onTap: () => _pickTime(true),
        ),
        const SizedBox(height: 20),
        _TimePickerTile(
          label: 'Window closes',
          time: formatTime(_windowEnd),
          onTap: () => _pickTime(false),
        ),
        const SizedBox(height: 24),
        Text(
          'If you miss this window, your contacts will be alerted.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppTheme.alertRed,
              ),
        ),
      ],
    );
  }

  Widget _buildContactStep() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Emergency contact',
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 12),
          Text(
            'Who should we notify if you miss a check-in?',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 32),
          TextFormField(
            controller: _contactNameController,
            style: const TextStyle(fontSize: AppTheme.fontBody),
            decoration: const InputDecoration(
              labelText: 'Contact Name',
              prefixIcon: Icon(Icons.person_outline, size: 28),
            ),
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _contactEmailController,
            keyboardType: TextInputType.emailAddress,
            style: const TextStyle(fontSize: AppTheme.fontBody),
            decoration: const InputDecoration(
              labelText: 'Contact Email',
              prefixIcon: Icon(Icons.email_outlined, size: 28),
            ),
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _contactRelationController,
            style: const TextStyle(fontSize: AppTheme.fontBody),
            decoration: const InputDecoration(
              labelText: 'Relationship (e.g., Son, Daughter)',
              prefixIcon: Icon(Icons.family_restroom, size: 28),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '$title: $subtitle',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: selected ? AppTheme.primaryGreen.withAlpha(25) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? AppTheme.primaryGreen : Colors.grey[300]!,
              width: selected ? 3 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 40, color: selected ? AppTheme.primaryGreen : Colors.grey),
              const SizedBox(width: 20),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: selected ? AppTheme.primaryGreen : AppTheme.textPrimary,
                    ),
                  ),
                  Text(subtitle, style: const TextStyle(fontSize: 16, color: AppTheme.textSecondary)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimePickerTile extends StatelessWidget {
  final String label;
  final String time;
  final VoidCallback onTap;

  const _TimePickerTile({
    required this.label,
    required this.time,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$label: $time',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(fontSize: 20, color: AppTheme.textSecondary)),
              Text(
                time,
                style: const TextStyle(
                  fontSize: 24,
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
