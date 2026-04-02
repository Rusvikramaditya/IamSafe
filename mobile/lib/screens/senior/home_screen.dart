import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/check_in_button.dart';
import 'settings_screen.dart';

class SeniorHomeScreen extends StatefulWidget {
  const SeniorHomeScreen({super.key});

  @override
  State<SeniorHomeScreen> createState() => _SeniorHomeScreenState();
}

class _SeniorHomeScreenState extends State<SeniorHomeScreen> {
  bool _checkedIn = false;
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  String? _checkInTime;
  int _streak = 0;
  String? _lastCheckInId;
  bool _selfieEnabled = false;
  bool _selfieUploaded = false;
  bool _uploadingSelfie = false;

  @override
  void initState() {
    super.initState();
    _loadTodayStatus();
  }

  Future<void> _loadTodayStatus() async {
    setState(() => _loading = true);

    try {
      final results = await Future.wait([
        ApiService.getTodayCheckIn(),
        ApiService.getSettings(),
      ]);

      final checkInResult = results[0];
      final settingsResult = results[1];

      setState(() {
        _checkedIn = checkInResult['checkedIn'] == true;
        if (_checkedIn && checkInResult['checkIn'] != null) {
          _checkInTime = _formatTime(checkInResult['checkIn']['checkedInAt']);
          _lastCheckInId = checkInResult['checkIn']['id'];
          _selfieUploaded = checkInResult['checkIn']['selfiePath'] != null;
        }
        _selfieEnabled = settingsResult['settings']?['selfieEnabled'] == true;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Could not load status. Pull down to retry.';
      });
    }
  }

  Future<void> _submitCheckIn() async {
    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final result = await ApiService.submitCheckIn();
      final checkIn = result['checkIn'];
      setState(() {
        _checkedIn = true;
        _submitting = false;
        _checkInTime = _formatTime(DateTime.now().toIso8601String());
        _lastCheckInId = checkIn?['id'];
        _streak++;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Check-in recorded! You are safe.',
              style: TextStyle(fontSize: 18),
            ),
            backgroundColor: AppTheme.safeGreen,
            duration: Duration(seconds: 3),
          ),
        );
      }

      // Offer selfie if enabled
      if (_selfieEnabled && _lastCheckInId != null && mounted) {
        _promptSelfie();
      }
    } catch (e) {
      setState(() {
        _submitting = false;
        _error = 'Check-in failed. Please try again.';
      });
    }
  }

  void _promptSelfie() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.camera_alt, size: 48, color: AppTheme.primaryGreen),
              const SizedBox(height: 12),
              const Text(
                'Add a selfie?',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Your loved ones will see it with your check-in.',
                style: TextStyle(fontSize: 18, color: AppTheme.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.camera_alt, color: Colors.white),
                  label: const Text('Take Photo', style: TextStyle(fontSize: 20, color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryGreen,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _takeSelfie();
                  },
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Skip', style: TextStyle(fontSize: 18)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _takeSelfie() async {
    try {
      final picker = ImagePicker();
      final photo = await picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80,
      );

      if (photo == null) return;

      setState(() => _uploadingSelfie = true);

      // Read and compress
      final bytes = await photo.readAsBytes();
      Uint8List jpegBytes = bytes;

      // Extra compression if > 1MB
      if (bytes.length > 1024 * 1024) {
        final decoded = img.decodeImage(bytes);
        if (decoded != null) {
          jpegBytes = Uint8List.fromList(img.encodeJpg(decoded, quality: 60));
        }
      }

      // Get presigned upload URL
      final urlResult = await ApiService.getSelfieUploadUrl(_lastCheckInId!);
      final uploadUrl = urlResult['uploadUrl'] as String;

      // Upload
      await ApiService.uploadSelfie(uploadUrl, jpegBytes);

      setState(() {
        _uploadingSelfie = false;
        _selfieUploaded = true;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Selfie uploaded!', style: TextStyle(fontSize: 18)),
            backgroundColor: AppTheme.safeGreen,
          ),
        );
      }
    } catch (e) {
      setState(() => _uploadingSelfie = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not upload selfie. Try again later.', style: TextStyle(fontSize: 18)),
            backgroundColor: AppTheme.alertRed,
          ),
        );
      }
    }
  }

  String _formatTime(String? isoString) {
    if (isoString == null) return '';
    try {
      final dt = DateTime.parse(isoString).toLocal();
      final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final amPm = dt.hour >= 12 ? 'PM' : 'AM';
      final min = dt.minute.toString().padLeft(2, '0');
      return '$hour:$min $amPm';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadTodayStatus,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: SizedBox(
              height: MediaQuery.of(context).size.height -
                  MediaQuery.of(context).padding.top -
                  MediaQuery.of(context).padding.bottom,
              child: Column(
                children: [
                  // Top bar
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'IamSafe',
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.settings, size: 32),
                          tooltip: 'Settings',
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const SeniorSettingsScreen(),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),

                  // Status message
                  if (_checkedIn && _checkInTime != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Checked in at $_checkInTime',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppTheme.safeGreen,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),

                  const Spacer(),

                  // The big button — center of the screen
                  if (_loading)
                    const CircularProgressIndicator()
                  else
                    CheckInButton(
                      checkedIn: _checkedIn,
                      loading: _submitting,
                      onPressed: _submitCheckIn,
                    ),

                  const SizedBox(height: 24),

                  // Instruction text
                  Text(
                    _checkedIn
                        ? 'You are safe today!'
                        : 'Tap the button to check in',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: _checkedIn
                              ? AppTheme.safeGreen
                              : AppTheme.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                  ),

                  // Selfie status / add selfie button
                  if (_checkedIn && _selfieEnabled) ...[
                    const SizedBox(height: 16),
                    if (_uploadingSelfie)
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                          SizedBox(width: 12),
                          Text('Uploading selfie...', style: TextStyle(fontSize: 18, color: AppTheme.textSecondary)),
                        ],
                      )
                    else if (_selfieUploaded)
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle, color: AppTheme.safeGreen, size: 24),
                          SizedBox(width: 8),
                          Text('Selfie sent', style: TextStyle(fontSize: 18, color: AppTheme.safeGreen)),
                        ],
                      )
                    else
                      TextButton.icon(
                        icon: const Icon(Icons.camera_alt, size: 24),
                        label: const Text('Add selfie', style: TextStyle(fontSize: 18)),
                        onPressed: _takeSelfie,
                      ),
                  ],

                  const Spacer(),

                  // Error message
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        children: [
                          Text(
                            _error!,
                            style: const TextStyle(
                              color: AppTheme.alertRed,
                              fontSize: AppTheme.fontSmall,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 52,
                            child: ElevatedButton(
                              onPressed: _loadTodayStatus,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.alertRed,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text(
                                'Try Again',
                                style: TextStyle(fontSize: 18),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
