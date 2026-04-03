import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

class CheckInButton extends StatefulWidget {
  final bool checkedIn;
  final bool loading;
  final VoidCallback onPressed;

  const CheckInButton({
    super.key,
    required this.checkedIn,
    required this.loading,
    required this.onPressed,
  });

  @override
  State<CheckInButton> createState() => _CheckInButtonState();
}

class _CheckInButtonState extends State<CheckInButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    if (!widget.checkedIn) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(CheckInButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.checkedIn && !oldWidget.checkedIn) {
      _pulseController.stop();
      _pulseController.reset();
    } else if (!widget.checkedIn && oldWidget.checkedIn) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (widget.loading || widget.checkedIn) return;

    // Triple feedback: haptic + visual (state change) + audio
    HapticFeedback.heavyImpact();
    widget.onPressed();
  }

  @override
  Widget build(BuildContext context) {
    final Color bgColor =
        widget.checkedIn ? AppTheme.safeGreen : AppTheme.primaryGreen;
    final Color shadowColor = widget.checkedIn
        ? AppTheme.safeGreen.withAlpha(102)
        : AppTheme.primaryGreen.withAlpha(102);

    return Semantics(
      button: true,
      enabled: !widget.checkedIn && !widget.loading,
      label: widget.checkedIn
          ? 'You are safe today. Check-in complete.'
          : 'Tap to check in. I am safe button.',
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          return Transform.scale(
            scale: widget.checkedIn ? 1.0 : _pulseAnimation.value,
            child: child,
          );
        },
        child: GestureDetector(
          onTap: _handleTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOut,
            width: AppTheme.checkInButtonSize,
            height: AppTheme.checkInButtonSize,
            decoration: BoxDecoration(
              color: bgColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: shadowColor,
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Center(
              child: widget.loading
                  ? const CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 4,
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          widget.checkedIn
                              ? Icons.check_circle
                              : Icons.touch_app,
                          size: 64,
                          color: Colors.white,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.checkedIn ? 'SAFE' : 'I AM\nSAFE',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: AppTheme.fontButtonLabel,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            height: 1.1,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
