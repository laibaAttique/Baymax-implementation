import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import 'auth_service.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  const ApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

/// Calls the Express backend with the signed-in user's Firebase ID token.
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  static const _defaultTimeout = Duration(seconds: 15);

  Future<Map<String, String>> _headers() async {
    final token = await AuthService.instance.currentUser?.getIdToken();
    if (token == null) {
      throw const ApiException('You are not signed in.', statusCode: 401);
    }
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  /// Returns the decoded JSON body (or null for an empty body).
  /// Throws [ApiException] on network errors and non-2xx responses.
  Future<dynamic> send(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    Duration timeout = _defaultTimeout,
  }) async {
    final headers = await _headers();
    final uri = Uri.parse('${ApiConfig.baseUrl}$path').replace(queryParameters: query);

    http.Response res;
    try {
      switch (method) {
        case 'GET':
          res = await http.get(uri, headers: headers).timeout(timeout);
        case 'POST':
          res = await http.post(uri, headers: headers, body: jsonEncode(body)).timeout(timeout);
        case 'PUT':
          res = await http.put(uri, headers: headers, body: jsonEncode(body)).timeout(timeout);
        case 'DELETE':
          res = await http.delete(uri, headers: headers).timeout(timeout);
        default:
          throw ArgumentError('Unsupported method $method');
      }
    } catch (_) {
      throw const ApiException('Could not reach the server.');
    }

    dynamic decoded;
    try {
      decoded = res.body.isEmpty ? null : jsonDecode(res.body);
    } catch (_) {
      decoded = null;
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return decoded;

    final serverMessage = decoded is Map ? decoded['error'] as String? : null;
    throw ApiException(serverMessage ?? 'Server error (${res.statusCode}).', statusCode: res.statusCode);
  }
}
