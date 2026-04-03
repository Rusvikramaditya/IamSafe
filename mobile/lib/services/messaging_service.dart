import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'api_service.dart';

class MessagingService {
  static final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  static bool _initialized = false;
  static String? _pendingToken;

  /// Initialize FCM and request permissions.
  /// Call early (in main). Token is stored but NOT sent to backend until
  /// [sendTokenToBackend] is called after user authentication.
  static Future<void> initialize() async {
    if (_initialized) return;

    try {
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
        _pendingToken = await _firebaseMessaging.getToken();

        // Listen for token refresh — store but only push if authenticated
        _firebaseMessaging.onTokenRefresh.listen((token) {
          _pendingToken = token;
          _trySendToken(token);
        });

        // Handle foreground messages
        FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

        // Handle background message tap
        FirebaseMessaging.onMessageOpenedApp.listen(_handleBackgroundMessageTap);

        _initialized = true;
      }
    } catch (e) {
      debugPrint('FCM initialization failed: $e');
    }
  }

  /// Send the stored FCM token to backend. Call after user signs in.
  static Future<void> sendTokenToBackend() async {
    if (_pendingToken != null) {
      await _trySendToken(_pendingToken!);
    }
  }

  static Future<void> _trySendToken(String token) async {
    try {
      await ApiService.updateFcmToken(token);
    } catch (e) {
      debugPrint('Failed to update FCM token on backend: $e');
    }
  }

  static void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('Foreground message: ${message.notification?.title}');
  }

  static void _handleBackgroundMessageTap(RemoteMessage message) {
    debugPrint('Background message tap: ${message.notification?.title}');
  }

  /// Handle background message (called by Firebase when app is in background)
  static Future<void> handleBackgroundMessage(RemoteMessage message) async {
    debugPrint('Handling a background message: ${message.messageId}');
  }
}
