import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

/// RevenueCat subscription service.
/// Call [init] once at app start with the Firebase UID.
class SubscriptionService extends ChangeNotifier {
  static const String _apiKey = String.fromEnvironment(
    'REVENUECAT_API_KEY',
    defaultValue: '', // Set via --dart-define or .env at build time
  );

  // RevenueCat entitlement identifiers (must match RevenueCat dashboard)
  static const String _premiumEntitlement = 'premium';
  static const String _familyEntitlement = 'family';

  CustomerInfo? _customerInfo;
  Offerings? _offerings;
  bool _initialized = false;

  // --- Public getters ---

  bool get isPremium {
    if (_customerInfo == null) return false;
    return _customerInfo!.entitlements.active.containsKey(_premiumEntitlement);
  }

  bool get isFamily {
    if (_customerInfo == null) return false;
    return _customerInfo!.entitlements.active.containsKey(_familyEntitlement);
  }

  bool get isSubscribed => isPremium || isFamily;
  bool get initialized => _initialized;
  Offerings? get offerings => _offerings;
  CustomerInfo? get customerInfo => _customerInfo;

  /// Initialize RevenueCat with the Firebase UID as app user ID.
  Future<void> init(String firebaseUid) async {
    if (_apiKey.isEmpty) {
      debugPrint('SubscriptionService: No RevenueCat API key — skipping init');
      _initialized = true;
      notifyListeners();
      return;
    }

    await Purchases.configure(
      PurchasesConfiguration(_apiKey)..appUserID = firebaseUid,
    );

    // Listen for customer info changes (e.g. server-side grant, renewal)
    Purchases.addCustomerInfoUpdateListener((info) {
      _customerInfo = info;
      notifyListeners();
    });

    // Fetch initial state
    _customerInfo = await Purchases.getCustomerInfo();
    _offerings = await Purchases.getOfferings();
    _initialized = true;
    notifyListeners();
  }

  /// Purchase a package (from offerings). Returns true on success.
  Future<bool> purchase(Package package) async {
    try {
      final result = await Purchases.purchasePackage(package);
      _customerInfo = result;
      notifyListeners();
      return isPremium;
    } on PlatformException catch (e) {
      debugPrint('Purchase error: ${e.code} — ${e.message}');
      return false;
    } catch (e) {
      debugPrint('Purchase error: $e');
      return false;
    }
  }

  /// Restore purchases (e.g. reinstall, new device).
  Future<bool> restore() async {
    try {
      _customerInfo = await Purchases.restorePurchases();
      notifyListeners();
      return isPremium;
    } catch (e) {
      debugPrint('Restore error: $e');
      return false;
    }
  }

  /// Refresh offerings (e.g. after locale change).
  Future<void> refreshOfferings() async {
    _offerings = await Purchases.getOfferings();
    notifyListeners();
  }
}
