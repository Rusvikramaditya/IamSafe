import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Shared status helpers for check-in status display.
/// Used by both dashboard and check-in detail screens.
class StatusHelpers {
  static Color statusColor(String? status) {
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

  static IconData statusIcon(String? status) {
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

  static String statusLabel(String? status) {
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
}
