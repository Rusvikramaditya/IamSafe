import 'dart:convert';
import 'dart:typed_data';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../main.dart';

/// Centralized API service for all backend communication.
///
/// Note: Using static methods for quick iteration. For production testability,
/// consider converting to an instance-based service with dependency injection.
class ApiService {
  static const String _baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8080/api/v1',
  );

  /// Get the current user's Firebase ID token, with automatic refresh.
  static Future<String> _getToken() async {
    if (BYPASS_FIREBASE) return 'demo_token';
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not authenticated');
    // forceRefresh: true ensures we never send an expired token
    return await user.getIdToken(true) ?? '';
  }

  static Map<String, String> _headers(String token) => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

  // ─── Auth ──────────────────────────────────────────────────────────

  /// Register user profile after Firebase Auth signup.
  static Future<Map<String, dynamic>> register({
    required String fullName,
    required String email,
    String? phone,
    required String role,
    String? timezone,
  }) async {
    final token = await _getToken();
    final res = await http.post(
      Uri.parse('$_baseUrl/auth/register'),
      headers: _headers(token),
      body: jsonEncode({
        'fullName': fullName,
        'email': email,
        'phone': phone,
        'role': role,
        'timezone': timezone,
      }),
    );
    if (res.statusCode != 201) throw Exception(res.body);
    return jsonDecode(res.body);
  }

  /// Get authenticated user's profile (role, name, entitlements).
  static Future<Map<String, dynamic>> getUserProfile() async {
    final token = await _getToken();
    final res = await http.get(
      Uri.parse('$_baseUrl/auth/profile'),
      headers: _headers(token),
    );
    if (res.statusCode != 200) throw Exception(res.body);
    return jsonDecode(res.body);
  }

  /// Get linked seniors (for caregiver users).
  static Future<Map<String, dynamic>> getLinkedSeniors() async {
    final token = await _getToken();
    final res = await http.get(
      Uri.parse('$_baseUrl/auth/linked-seniors'),
      headers: _headers(token),
    );
    if (res.statusCode != 200) throw Exception(res.body);
    return jsonDecode(res.body);
  }

  /// Link caregiver to senior via invite code.
  static Future<Map<String, dynamic>> linkSenior(String inviteCode) async {
    final token = await _getToken();
    final res = await http.post(
      Uri.parse('$_baseUrl/auth/link-senior'),
      headers: _headers(token),
      body: jsonEncode({'inviteCode': inviteCode}),
    );
    if (res.statusCode != 200) throw Exception(res.body);
    return jsonDecode(res.body);
  }

  /// Generate invite code (senior only).
  static Future<Map<String, dynamic>> generateInviteCode() async {
    final token = await _getToken();
    final res = await http.post(
      Uri.parse('$_baseUrl/auth/generate-invite'),
      headers: _headers(token),
    );
    if (res.statusCode != 201) throw Exception(res.body);
    return jsonDecode(res.body);
  }

  // ─── Check-ins ────────────────────────────────────────────────────

  /// Submit daily check-in.
  static Future<Map<String, dynamic>> submitCheckIn() async {
    final token = await _getToken();
    final res = await http.post(
      Uri.parse('$_baseUrl/check-ins'),
      headers: _headers(token),
    );
    if (res.statusCode != 201) throw Exception(res.body);
    return jsonDecode(res.body);
  }

  /// Get today's check-in status.
  static Future<Map<String, dynamic>> getTodayCheckIn() async {
    final token = await _getToken();
    final res = await http.get(
      Uri.parse('$_baseUrl/check-ins/today'),
      headers: _headers(token),
    );
    if (res.statusCode != 200) throw Exception(res.body);
    return jsonDecode(res.body);
  }

  /// Get check-in history.
  static Future<Map<String, dynamic>> getCheckInHistory({int limit = 30}) async {
    final token = await _getToken();
    final res = await http.get(
      Uri.parse('$_baseUrl/check-ins/history?limit=$limit'),
      headers: _headers(token),
    );
    if (res.statusCode != 200) throw Exception(res.body);
    return jsonDecode(res.body);
  }

  /// Get single check-in by ID (includes signed selfie URL).
  static Future<Map<String, dynamic>> getCheckIn(String checkInId) async {
    final token = await _getToken();
    final res = await http.get(
      Uri.parse('$_baseUrl/check-ins/$checkInId'),
      headers: _headers(token),
    );
    if (res.statusCode != 200) throw Exception(res.body);
    return jsonDecode(res.body);
  }

  /// Get selfie upload URL (does not set selfiePath on the record).
  static Future<Map<String, dynamic>> getSelfieUploadUrl(String checkInId) async {
    final token = await _getToken();
    final res = await http.post(
      Uri.parse('$_baseUrl/check-ins/$checkInId/selfie-url'),
      headers: _headers(token),
    );
    if (res.statusCode != 200) throw Exception(res.body);
    return jsonDecode(res.body);
  }

  /// Upload selfie binary to signed URL.
  static Future<void> uploadSelfie(String uploadUrl, Uint8List bytes) async {
    final res = await http.put(
      Uri.parse(uploadUrl),
      headers: {'Content-Type': 'image/jpeg'},
      body: bytes,
    );
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception('Selfie upload failed: ${res.statusCode}');
    }
  }

  /// Confirm selfie upload (sets hasSelfie on the check-in record).
  static Future<void> confirmSelfie(String checkInId, String selfiePath) async {
    final token = await _getToken();
    final res = await http.post(
      Uri.parse('$_baseUrl/check-ins/$checkInId/selfie-confirm'),
      headers: _headers(token),
      body: jsonEncode({'selfiePath': selfiePath}),
    );
    if (res.statusCode != 200) throw Exception(res.body);
  }

  // ─── Settings ─────────────────────────────────────────────────────

  /// Get senior settings.
  static Future<Map<String, dynamic>> getSettings() async {
    final token = await _getToken();
    final res = await http.get(
      Uri.parse('$_baseUrl/settings'),
      headers: _headers(token),
    );
    if (res.statusCode != 200) throw Exception(res.body);
    return jsonDecode(res.body);
  }

  /// Update senior settings.
  static Future<void> updateSettings(Map<String, dynamic> updates) async {
    final token = await _getToken();
    final res = await http.put(
      Uri.parse('$_baseUrl/settings'),
      headers: _headers(token),
      body: jsonEncode(updates),
    );
    if (res.statusCode != 200) throw Exception(res.body);
  }

  /// Update FCM token (routed through settings endpoint).
  static Future<void> updateFcmToken(String token) async {
    await updateSettings({'fcmToken': token});
  }

  // ─── Contacts ─────────────────────────────────────────────────────

  /// Get emergency contacts.
  static Future<Map<String, dynamic>> getContacts() async {
    final token = await _getToken();
    final res = await http.get(
      Uri.parse('$_baseUrl/contacts'),
      headers: _headers(token),
    );
    if (res.statusCode != 200) throw Exception(res.body);
    return jsonDecode(res.body);
  }

  /// Add a new emergency contact.
  static Future<Map<String, dynamic>> addContact({
    required String fullName,
    required String email,
    String? phone,
    required String relationship,
  }) async {
    final token = await _getToken();
    final res = await http.post(
      Uri.parse('$_baseUrl/contacts'),
      headers: _headers(token),
      body: jsonEncode({
        'fullName': fullName,
        'email': email,
        'phone': phone,
        'relationship': relationship,
      }),
    );
    if (res.statusCode != 201) throw Exception(res.body);
    return jsonDecode(res.body);
  }

  /// Delete an emergency contact.
  static Future<void> deleteContact(String contactId) async {
    final token = await _getToken();
    final res = await http.delete(
      Uri.parse('$_baseUrl/contacts/$contactId'),
      headers: _headers(token),
    );
    if (res.statusCode != 200) throw Exception(res.body);
  }

  // ─── Dashboard ────────────────────────────────────────────────────

  /// Get 30-day check-in summary for a senior.
  static Future<Map<String, dynamic>> getDashboardSummary(String seniorId) async {
    final token = await _getToken();
    final res = await http.get(
      Uri.parse('$_baseUrl/dashboard/$seniorId/summary'),
      headers: _headers(token),
    );
    if (res.statusCode != 200) throw Exception(res.body);
    return jsonDecode(res.body);
  }

  /// Get streak for a senior.
  static Future<Map<String, dynamic>> getStreak(String seniorId) async {
    final token = await _getToken();
    final res = await http.get(
      Uri.parse('$_baseUrl/dashboard/$seniorId/streak'),
      headers: _headers(token),
    );
    if (res.statusCode != 200) throw Exception(res.body);
    return jsonDecode(res.body);
  }

  /// Get alert history for a senior.
  static Future<Map<String, dynamic>> getAlerts(String seniorId) async {
    final token = await _getToken();
    final res = await http.get(
      Uri.parse('$_baseUrl/dashboard/$seniorId/alerts'),
      headers: _headers(token),
    );
    if (res.statusCode != 200) throw Exception(res.body);
    return jsonDecode(res.body);
  }
}
