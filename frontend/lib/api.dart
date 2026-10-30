import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

typedef Json = Map<String, dynamic>;

class ApiException implements Exception {
  final String message;
  final int status;
  ApiException(this.message, [this.status = 0]);
  @override
  String toString() => message;
}

class DashboardData {
  final List<Json> endpoints, incidents, notifications;
  final Json report, health, config;
  DashboardData({
    required this.endpoints,
    required this.incidents,
    required this.notifications,
    required this.report,
    required this.health,
    required this.config,
  });
}

class ApiClient {
  final http.Client client;
  final String baseUrl;
  String operatorKey = '';
  ApiClient({
    http.Client? client,
    this.baseUrl = const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://127.0.0.1:8000',
    ),
  }) : client = client ?? http.Client();

  Future<dynamic> request(
    String method,
    String path, {
    Json? body,
    bool protected = false,
    String? idempotencyKey,
  }) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (protected) headers['X-Operator-Key'] = operatorKey;
    if (idempotencyKey != null) headers['Idempotency-Key'] = idempotencyKey;
    try {
      final request = http.Request(method, Uri.parse('$baseUrl$path'))
        ..headers.addAll(headers);
      if (body != null) request.body = jsonEncode(body);
      final response = await http.Response.fromStream(
        await client.send(request),
      ).timeout(const Duration(seconds: 40));
      final dynamic decoded = jsonDecode(response.body);
      if (response.statusCode >= 400) {
        if (response.statusCode == 401) operatorKey = '';
        final detail = decoded is Map ? decoded['error'] : null;
        final message = detail is Map ? detail['message']?.toString() : null;
        throw ApiException(
          message ?? 'The request could not be completed.',
          response.statusCode,
        );
      }
      return decoded;
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw ApiException(
        'The request timed out. Refresh to check whether it finished.',
      );
    } catch (_) {
      throw ApiException(
        'Cannot reach the monitoring API. Start the local services, then retry.',
      );
    }
  }

  Future<DashboardData> load({int hours = 24}) async {
    final values = await Future.wait([
      request('GET', '/api/endpoints'),
      request('GET', '/api/incidents'),
      request('GET', '/api/notifications'),
      request('GET', '/api/reports?hours=$hours'),
      request('GET', '/healthz'),
      request('GET', '/api/config'),
    ]);
    List<Json> rows(dynamic value) =>
        (value as List).map((e) => Json.from(e as Map)).toList();
    return DashboardData(
      endpoints: rows(values[0]),
      incidents: rows(values[1]),
      notifications: rows(values[2]),
      report: Json.from(values[3]),
      health: Json.from(values[4]),
      config: Json.from(values[5]),
    );
  }

  Future<void> verifyKey(String key) async {
    operatorKey = key;
    try {
      await request('POST', '/api/operator/verify', protected: true);
    } catch (_) {
      operatorKey = '';
      rethrow;
    }
  }

  Future<Json> check(int id, String key) async => Json.from(
    await request(
      'POST',
      '/api/endpoints/$id/checks',
      protected: true,
      idempotencyKey: key,
    ),
  );
  Future<List<Json>> history(int id) async =>
      (await request('GET', '/api/endpoints/$id/checks') as List)
          .map((e) => Json.from(e))
          .toList();
  void close() => client.close();
}
