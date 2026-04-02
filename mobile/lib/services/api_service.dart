import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

class ApiService {
  // Update to Cloud Run URL in production
  static const String _baseUrl = 'http://10.0.2.2:8080/api/v1';

  static Future<String?> _getToken() async {
    final user = FirebaseAuth.instance.currentUser;
    return user?.getIdToken();
  }

  static Future<Map<String, String>> _headers() async {
    final token = await _getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // Auth
  static Future<Map<String, dynamic>> register({
    required String fullName,
    required String email,
    String? phone,
    required String role,
    String timezone = 'America/New_York',
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/auth/register'),
      headers: await _headers(),
      body: jsonEncode({
        'fullName': fullName,
        'email': email,
        'phone': phone,
        'role': role,
        'timezone': timezone,
      }),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> generateInviteCode() async {
    final response = await http.post(
      Uri.parse('$_baseUrl/auth/generate-invite'),
      headers: await _headers(),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> linkSenior(String inviteCode) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/auth/link-senior'),
      headers: await _headers(),
      body: jsonEncode({'inviteCode': inviteCode}),
    );
    return jsonDecode(response.body);
  }

  // Check-ins
  static Future<Map<String, dynamic>> submitCheckIn() async {
    final response = await http.post(
      Uri.parse('$_baseUrl/check-ins'),
      headers: await _headers(),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> getTodayCheckIn() async {
    final response = await http.get(
      Uri.parse('$_baseUrl/check-ins/today'),
      headers: await _headers(),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> getCheckInHistory({int limit = 30}) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/check-ins/history?limit=$limit'),
      headers: await _headers(),
    );
    return jsonDecode(response.body);
  }

  // Contacts
  static Future<Map<String, dynamic>> getContacts() async {
    final response = await http.get(
      Uri.parse('$_baseUrl/contacts'),
      headers: await _headers(),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> addContact({
    required String fullName,
    required String email,
    String? phone,
    String? relationship,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/contacts'),
      headers: await _headers(),
      body: jsonEncode({
        'fullName': fullName,
        'email': email,
        'phone': phone,
        'relationship': relationship,
      }),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> deleteContact(String contactId) async {
    final response = await http.delete(
      Uri.parse('$_baseUrl/contacts/$contactId'),
      headers: await _headers(),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> sendTestAlert(String contactId) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/contacts/$contactId/test-alert'),
      headers: await _headers(),
    );
    return jsonDecode(response.body);
  }

  // Check-in detail
  static Future<Map<String, dynamic>> getCheckIn(String checkInId) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/check-ins/$checkInId'),
      headers: await _headers(),
    );
    return jsonDecode(response.body);
  }

  // Selfie upload
  static Future<Map<String, dynamic>> getSelfieUploadUrl(String checkInId) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/check-ins/selfie-url'),
      headers: await _headers(),
      body: jsonEncode({'checkInId': checkInId}),
    );
    return jsonDecode(response.body);
  }

  static Future<void> uploadSelfie(String uploadUrl, Uint8List imageBytes) async {
    await http.put(
      Uri.parse(uploadUrl),
      headers: {'Content-Type': 'image/jpeg'},
      body: imageBytes,
    );
  }

  // Dashboard (caregiver)
  static Future<Map<String, dynamic>> getDashboardSummary(String seniorId) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/dashboard/$seniorId/summary'),
      headers: await _headers(),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> getStreak(String seniorId) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/dashboard/$seniorId/streak'),
      headers: await _headers(),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> getAlertHistory(String seniorId) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/dashboard/$seniorId/alerts'),
      headers: await _headers(),
    );
    return jsonDecode(response.body);
  }

  // Get user profile
  static Future<Map<String, dynamic>> getUserProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return {};
    // We can get user role from the register endpoint response,
    // but for role-based routing we need a profile endpoint.
    // For now, use Firestore via the settings endpoint as a proxy:
    // If settings exist, user is a senior. Otherwise, check via a dedicated call.
    // Using a lightweight approach: try getSettings - if it works, user is senior.
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/settings'),
        headers: await _headers(),
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['settings'] != null) {
        return {'role': 'senior'};
      }
      return {'role': 'caregiver'};
    } catch (_) {
      return {'role': 'senior'};
    }
  }

  // FCM token
  static Future<void> updateFcmToken(String token) async {
    await http.put(
      Uri.parse('$_baseUrl/settings'),
      headers: await _headers(),
      body: jsonEncode({'fcmToken': token}),
    );
  }

  // Settings
  static Future<Map<String, dynamic>> getSettings() async {
    final response = await http.get(
      Uri.parse('$_baseUrl/settings'),
      headers: await _headers(),
    );
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> updateSettings(Map<String, dynamic> updates) async {
    final response = await http.put(
      Uri.parse('$_baseUrl/settings'),
      headers: await _headers(),
      body: jsonEncode(updates),
    );
    return jsonDecode(response.body);
  }
}
