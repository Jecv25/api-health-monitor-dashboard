import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'platform_stub.dart' if (dart.library.js_interop) 'platform_web.dart' as platform;

class ApiFailure implements Exception {
  final int status;
  final String code;
  final String message;
  final String? correlation;
  final Map<String, dynamic> fields;
  const ApiFailure(this.status, this.code, this.message, {this.correlation, this.fields = const {}});
  @override
  String toString() => message;
}

String mutationKey() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

class ApiClient {
  final http.Client client;
  final String baseUrl;
  ApiClient({http.Client? client, String? baseUrl})
      : client = client ?? platform.createClient(),
        baseUrl = baseUrl ?? (const String.fromEnvironment('API_BASE_URL').isNotEmpty
            ? const String.fromEnvironment('API_BASE_URL') : platform.defaultBaseUrl());

  Future<dynamic> request(String path, {String method = 'GET', Map<String, dynamic>? body, String? key}) async {
    final request = http.Request(method, Uri.parse('$baseUrl$path'));
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    if (key != null) request.headers['Idempotency-Key'] = key;
    http.Response response;
    try {
      response = await http.Response.fromStream(await client.send(request)).timeout(const Duration(seconds: 15));
    } catch (_) {
      throw const ApiFailure(0, 'NETWORK_ERROR', 'Cannot reach the local server. Check the connection and retry.');
    }
    if (response.statusCode == 204) return null;
    Map<String, dynamic> decoded;
    try { decoded = jsonDecode(response.body) as Map<String, dynamic>; }
    catch (_) { throw ApiFailure(response.statusCode, 'INVALID_RESPONSE', 'The server returned an unreadable response.', correlation: response.headers['x-correlation-id']); }
    if (response.statusCode >= 400) {
      final error = decoded['error'] as Map<String, dynamic>? ?? {};
      throw ApiFailure(response.statusCode, error['code'] as String? ?? 'SERVER_ERROR', error['message'] as String? ?? 'The server could not complete this request.',
          correlation: decoded['correlation_id'] as String?, fields: (error['fields'] as Map?)?.cast<String, dynamic>() ?? {});
    }
    return decoded['data'];
  }
  void close() => client.close();
}
