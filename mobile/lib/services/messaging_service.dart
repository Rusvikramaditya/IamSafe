import 'package:firebase_messaging/firebase_messaging.dart';
import 'api_service.dart';

class MessagingService {
  static final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  static bool _initialized = false;

  /// Initialize FCM and request permissions
  static Future<void> initialize() async {
    if (_initialized) return;

    try {
      // Request notification permissions (iOS)
      final settings = await _firebaseMessaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        // Get FCM token
        final token = await _firebaseMessaging.getToken();
        if (token != null) {
          // Send token to backend
          await _updateTokenOnBackend(token);
        }

        // Listen for token refresh
        _firebaseMessaging.onTokenRefresh.listen(_updateTokenOnBackend);

        // Handle foreground messages
        FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

        // Handle background message tap
        FirebaseMessaging.onMessageOpenedApp.listen(_handleBackgroundMessageTap);

        _initialized = true;
      }
    } catch (e) {
      print('FCM initialization failed: $e');
    }
  }

  static Future<void> _updateTokenOnBackend(String token) async {
    try {
      await ApiService.updateFcmToken(token);
    } catch (e) {
      print('Failed to update FCM token on backend: $e');
    }
  }

  static void _handleForegroundMessage(RemoteMessage message) {
    print('Foreground message: ${message.notification?.title}');
    // In a real app, you'd show a local notification or in-app banner
    // For now, we just log it. The system notification will appear automatically.
  }

  static void _handleBackgroundMessageTap(RemoteMessage message) {
    print('Background message tap: ${message.notification?.title}');
    // Handle navigation or actions based on message data
  }

  /// Handle background message (called by Firebase when app is in background)
  static Future<void> handleBackgroundMessage(RemoteMessage message) async {
    print('Handling a background message: ${message.messageId}');
  }
}
