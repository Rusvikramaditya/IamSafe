import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';

class CheckInDetailScreen extends StatefulWidget {
  final String seniorId;
  final String date;
  final String status;
  final String? checkedInAt;

  const CheckInDetailScreen({
    super.key,
    required this.seniorId,
    required this.date,
    required this.status,
    this.checkedInAt,
  });

  @override
  State<CheckInDetailScreen> createState() => _CheckInDetailScreenState();
}

class _CheckInDetailScreenState extends State<CheckInDetailScreen> {
  bool _loading = false;
  String? _error;
  String? _checkInId;
  String? _selfieUrl;
  bool _hasSelfie = false;

  @override
  void initState() {
    super.initState();
    // Try to find the check-in ID by querying the history
    _searchCheckIn();
  }

  Future<void> _searchCheckIn() async {
    setState(() => _loading = true);
    try {
      final history = await ApiService.getCheckInHistory(limit: 90);
      final checkIns = history['checkIns'] as List? ?? [];

      // Find check-in matching this date
      final matching = checkIns.firstWhere(
        (c) => c['checkInDate'] == widget.date,
        orElse: () => null,
      );

      if (matching != null) {
        setState(() => _checkInId = matching['id']);
        // Load full check-in with signed selfie URL
        await _loadCheckInDetail(matching['id']);
      } else {
        setState(() => _loading = false);
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Could not load check-in details.';
      });
    }
  }

  Future<void> _loadCheckInDetail(String checkInId) async {
    try {
      final result = await ApiService.getCheckIn(checkInId);
      final checkIn = result['checkIn'] as Map?;

      if (checkIn != null) {
        setState(() {
          _checkInId = checkInId;
          _selfieUrl = checkIn['selfieUrl'] as String?;
          _hasSelfie = checkIn['hasSelfie'] == true;
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Could not load selfie. It may be expired.';
      });
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'on_time':
        return 'Checked in on time';
      case 'late':
        return 'Checked in late';
      case 'missed':
        return 'Missed check-in';
      default:
        return 'Unknown status';
    }
  }

  String _formatTime(String? isoString) {
    if (isoString == null) return '—';
    try {
      final dt = DateTime.parse(isoString).toLocal();
      final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final amPm = dt.hour >= 12 ? 'PM' : 'AM';
      final min = dt.minute.toString().padLeft(2, '0');
      return '$hour:$min $amPm';
    } catch (_) {
      return '—';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Check-in Details'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Status card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: _statusColor(widget.status),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _statusIcon(widget.status),
                          color: Colors.white,
                          size: 40,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.date,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _statusLabel(widget.status),
                                style: const TextStyle(
                                  fontSize: 16,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Check-in time
                  if (widget.checkedInAt != null) ...[
                    const Text(
                      'Check-in Time',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _formatTime(widget.checkedInAt),
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Selfie section
                  const Text(
                    'Selfie',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),

                  if (_error != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.alertRed.withAlpha(26),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.alertRed),
                      ),
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          fontSize: 16,
                          color: AppTheme.alertRed,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    )
                  else if (_hasSelfie && _selfieUrl != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.network(
                        _selfieUrl!,
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          return Container(
                            height: 300,
                            color: Colors.grey[200],
                            child: const Center(child: CircularProgressIndicator()),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            height: 300,
                            color: Colors.grey[200],
                            child: const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.error_outline, size: 48, color: AppTheme.alertRed),
                                  SizedBox(height: 8),
                                  Text(
                                    'Could not load image',
                                    style: TextStyle(color: AppTheme.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    )
                  else if (_hasSelfie)
                    Container(
                      width: double.infinity,
                      height: 200,
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.timer, size: 48, color: AppTheme.textSecondary),
                            SizedBox(height: 8),
                            Text(
                              'Selfie link may have expired',
                              style: TextStyle(fontSize: 16, color: AppTheme.textSecondary),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Selfies expire after 1 hour',
                              style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    Container(
                      width: double.infinity,
                      height: 200,
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.image_not_supported_outlined, size: 48, color: AppTheme.textSecondary),
                            SizedBox(height: 8),
                            Text(
                              'No selfie taken',
                              style: TextStyle(fontSize: 16, color: AppTheme.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ),

                  const SizedBox(height: 32),

                  // Note about premium
                  if (!_hasSelfie)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.blue.withAlpha(13),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.blue, size: 24),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Premium members can view full selfie history.',
                              style: TextStyle(fontSize: 16, color: Colors.blue),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'on_time':
        return AppTheme.safeGreen;
      case 'late':
        return AppTheme.warningYellow;
      case 'missed':
        return AppTheme.alertRed;
      default:
        return Colors.grey[400]!;
    }
  }

  IconData _statusIcon(String status) {
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
}
