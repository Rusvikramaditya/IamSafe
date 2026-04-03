import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';
import 'services/auth_service.dart';
import 'services/api_service.dart';
import 'services/messaging_service.dart';
import 'services/subscription_service.dart';
import 'theme/app_theme.dart';
import 'screens/auth/welcome_screen.dart';
import 'screens/senior/home_screen.dart';
import 'screens/caregiver/dashboard_screen.dart';

// Background message handler
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  await MessagingService.handleBackgroundMessage(message);
}

/// Set via: flutter run --dart-define=BYPASS_FIREBASE=true
/// Defaults to false (production). Only use true for UI testing without Firebase.
const bool BYPASS_FIREBASE = bool.fromEnvironment('BYPASS_FIREBASE');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  if (!BYPASS_FIREBASE) {
    await Firebase.initializeApp();

    // Pass all uncaught "fatal" errors from the framework to Crashlytics
    FlutterError.onError = (errorDetails) {
      FirebaseCrashlytics.instance.recordFlutterFatalError(errorDetails);
    };
    
    // Pass all uncaught asynchronous errors that aren't handled by the Flutter framework to Crashlytics
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };

    // Set background message handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Initialize messaging service
    await MessagingService.initialize();
  }

  runApp(const IamSafeApp());
}

class IamSafeApp extends StatelessWidget {
  const IamSafeApp({super.key});

  @override
  Widget build(BuildContext context) {
    if (BYPASS_FIREBASE) {
      // In demo mode, bypass Providers that rely on Firebase.instance
      return MaterialApp(
        title: 'IamSafe Demo',
        theme: AppTheme.lightTheme,
        debugShowCheckedModeBanner: false,
        home: const WelcomeScreen(), // Go straight to welcome screen
      );
    }

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => SubscriptionService()),
      ],
      child: MaterialApp(
        title: 'IamSafe',
        theme: AppTheme.lightTheme,
        debugShowCheckedModeBanner: false,
        home: const AuthGate(),
      ),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);

    return StreamBuilder(
      stream: authService.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (snapshot.hasData) {
          // User is logged in — determine role and route
          return _RoleRouter(key: ValueKey(snapshot.data?.uid));
        }

        return const WelcomeScreen();
      },
    );
  }
}

class _RoleRouter extends StatefulWidget {
  const _RoleRouter({super.key});

  @override
  State<_RoleRouter> createState() => _RoleRouterState();
}

class _RoleRouterState extends State<_RoleRouter> {
  static const _storage = FlutterSecureStorage();
  static const _roleKey = 'cached_user_role';

  String? _role;
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _fetchRole();
  }

  Future<void> _fetchRole() async {
    setState(() {
      _loading = true;
      _error = false;
    });

    try {
      final profile = await ApiService.getUserProfile();
      final role = profile['role'] as String?;

      // Cache role locally so it survives backend outages
      if (role != null) {
        await _storage.write(key: _roleKey, value: role);
      }

      // Initialize RevenueCat with Firebase UID
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null && mounted) {
        final sub = Provider.of<SubscriptionService>(context, listen: false);
        if (!sub.initialized) {
          await sub.init(uid);
        }
      }

      // Send FCM token now that user is authenticated
      MessagingService.sendTokenToBackend();

      if (mounted) {
        setState(() {
          _role = role ?? 'senior';
          _loading = false;
        });
      }
    } catch (_) {
      // Try to use cached role from last successful fetch
      String? cachedRole;
      try {
        cachedRole = await _storage.read(key: _roleKey);
      } catch (_) {
        // Secure storage error — ignore
      }

      if (cachedRole != null && mounted) {
        setState(() {
          _role = cachedRole;
          _loading = false;
        });
      } else if (mounted) {
        // No cached role and backend unreachable — show error
        setState(() {
          _loading = false;
          _error = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_error) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.wifi_off, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                const Text(
                  'Could not connect to server',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Please check your internet connection and try again.',
                  style: TextStyle(fontSize: 18, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _fetchRole,
                    child: const Text('Retry', style: TextStyle(fontSize: 20)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return _role == 'caregiver'
        ? const CaregiverDashboardScreen()
        : const SeniorHomeScreen();
  }
}
