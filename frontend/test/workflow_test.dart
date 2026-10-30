import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pulsewatch/api.dart';
import 'package:pulsewatch/main.dart';

DashboardData fixture({bool populated = false, String status = 'up'}) =>
    DashboardData(
      endpoints: populated
          ? [
              {
                'id': 1,
                'name': 'Controlled API',
                'url': 'http://127.0.0.1:9001/health/healthy',
                'enabled': true,
                'status': status,
                'recent_samples': [true, false, true],
                'last_run': null,
                'last_check_at': null,
                'interval_seconds': 60,
                'timeout_seconds': 3,
                'recovery_streak': 1,
              },
            ]
          : [],
      incidents: populated
          ? [
              {
                'id': 1,
                'endpoint_id': 1,
                'endpoint_name': 'Controlled API',
                'status': 'open',
                'owner_group': 'support',
                'opened_at': '2026-10-30T00:00:00Z',
                'acknowledged_by': null,
                'note': null,
                'recovered_at': null,
              },
            ]
          : [],
      notifications: [],
      report: {
        'summary': {
          'healthy': populated ? 1 : 0,
          'total_endpoints': populated ? 1 : 0,
          'unavailable': 0,
          'recovering': status == 'recovering' ? 1 : 0,
          'open_incidents': populated ? 1 : 0,
          'uptime_percent': populated ? 66.67 : null,
          'avg_response_ms': populated ? 12.5 : null,
          'completed_checks': populated ? 3 : 0,
          'transient_recoveries': 0,
        },
        'recent_runs': [],
        'endpoints': [],
        'definition': 'Controlled widget-test fixture.',
        'generated_at': '2026-10-30T00:00:00Z',
      },
      health: {'worker': 'online'},
      config: {
        'approved_origins': ['http://127.0.0.1:9001'],
        'demo_enabled': true,
        'max_attempts': 3,
        'recovery_successes': 2,
      },
    );

class FakeApi extends ApiClient {
  DashboardData result;
  Completer<DashboardData>? pending;
  bool unavailable = false;
  bool rejectKey = false;
  FakeApi(this.result);
  @override
  Future<DashboardData> load({int hours = 24}) async {
    if (unavailable) throw ApiException('Controlled API unavailable.');
    return pending == null ? result : pending!.future;
  }

  @override
  Future<void> verifyKey(String key) async {
    if (rejectKey) throw ApiException('Operator access denied.', 401);
    operatorKey = key;
  }

  @override
  Future<List<Json>> history(int id) async => [];
  @override
  Future<dynamic> request(
    String method,
    String path, {
    Json? body,
    bool protected = false,
    String? idempotencyKey,
  }) async {
    if (path.startsWith('/api/demo/')) return {'applied': true};
    throw ApiException('Unexpected controlled test operation.');
  }
}

Future<void> mount(
  WidgetTester tester,
  FakeApi api, {
  Size size = const Size(1440, 1000),
  bool autoRefresh = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(PulsewatchApp(api: api, autoRefresh: autoRefresh));
  await tester.pump();
}

void main() {
  testWidgets(
    'SA7-08 an open service dialog follows refreshed monitoring state',
    (tester) async {
      final api = FakeApi(fixture(populated: true, status: 'down'));
      await mount(tester, api, autoRefresh: true);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Controlled API'));
      await tester.pumpAndSettle();
      expect(
        find.text('Recovery verification: 1 / 2 successful cycles.'),
        findsNothing,
      );
      api.result = fixture(populated: true, status: 'recovering');
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(
        find.text('Recovery verification: 1 / 2 successful cycles.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('SA7-08 repair feedback remains inside the open service dialog', (
    tester,
  ) async {
    final sample = fixture(populated: true);
    sample.endpoints[0]['url'] = 'http://127.0.0.1:9001/health/persistent';
    final api = FakeApi(sample)..operatorKey = 'widget-test-memory-only';
    await mount(tester, api);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Controlled API'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Repair demo service'));
    await tester.pumpAndSettle();
    expect(
      find.text('Demo repaired. Run two successful checks to verify recovery.'),
      findsOneWidget,
    );
    expect(find.text('Close service details'), findsNothing);
    expect(find.byTooltip('Close service details'), findsOneWidget);
  });
  testWidgets('SA7-12 loading becomes an honest empty state', (tester) async {
    final api = FakeApi(fixture())..pending = Completer<DashboardData>();
    await mount(tester, api);
    expect(find.text('Loading monitoring workspace…'), findsOneWidget);
    api.pending!.complete(fixture());
    await tester.pumpAndSettle();
    expect(find.text('Bring your first service online'), findsOneWidget);
    expect(find.text('0 / 0'), findsOneWidget);
    expect(find.text('100.0%'), findsNothing);
  });
  testWidgets('SA7-12 unavailable state supports recovery by retry', (
    tester,
  ) async {
    final api = FakeApi(fixture())..unavailable = true;
    await mount(tester, api);
    await tester.pumpAndSettle();
    expect(find.text('Monitoring API unavailable'), findsOneWidget);
    api.unavailable = false;
    await tester.tap(find.text('Retry connection'));
    await tester.pumpAndSettle();
    expect(find.text('Bring your first service online'), findsOneWidget);
  });
  testWidgets('SA7-12 desktop navigation renders service and incident states', (
    tester,
  ) async {
    await mount(tester, FakeApi(fixture(populated: true)));
    await tester.pumpAndSettle();
    expect(find.text('Controlled API'), findsOneWidget);
    await tester.tap(find.byKey(const Key('nav-2')));
    await tester.pumpAndSettle();
    expect(find.text('Incident center'), findsOneWidget);
    expect(find.text('Acknowledge'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('SA7-12 narrow browser uses drawer without overflow', (
    tester,
  ) async {
    await mount(
      tester,
      FakeApi(fixture(populated: true)),
      size: const Size(390, 844),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Open navigation'), findsOneWidget);
    await tester.tap(find.byTooltip('Open navigation'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav-3')));
    await tester.pumpAndSettle();
    expect(find.text('Availability reports'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('SA7-02 form rejects an unapproved URL', (tester) async {
    final api = FakeApi(fixture())..operatorKey = 'widget-test-memory-only';
    await mount(tester, api);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add service'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('service-name')),
      'Controlled API',
    );
    await tester.enterText(
      find.byKey(const Key('service-url')),
      'http://unapproved.invalid/health',
    );
    await tester.tap(find.text('Register service'));
    await tester.pumpAndSettle();
    expect(find.text('Choose an approved service origin.'), findsOneWidget);
  });
  testWidgets('SA7-03 unauthorized operator shows a safe error', (
    tester,
  ) async {
    final api = FakeApi(fixture())..rejectKey = true;
    await mount(tester, api);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Connect operator'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('operator-key')),
      'invalid-key',
    );
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(find.text('Operator access denied.'), findsOneWidget);
    expect(api.operatorKey, isEmpty);
  });
  testWidgets('SA7-08 service detail displays recovery verification', (
    tester,
  ) async {
    await mount(
      tester,
      FakeApi(fixture(populated: true, status: 'recovering')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Controlled API'));
    await tester.pumpAndSettle();
    expect(
      find.text('Recovery verification: 1 / 2 successful cycles.'),
      findsOneWidget,
    );
  });
  test(
    'API client forwards idempotency and clears rejected credentials',
    () async {
      final api = ApiClient(
        client: MockClient((request) async {
          expect(request.headers['Idempotency-Key'], 'controlled-submission');
          expect(request.headers['X-Operator-Key'], 'unit-test-memory-only');
          return http.Response(
            jsonEncode({
              'error': {'message': 'Access denied.'},
            }),
            401,
          );
        }),
      )..operatorKey = 'unit-test-memory-only';
      await expectLater(
        api.check(1, 'controlled-submission'),
        throwsA(isA<ApiException>()),
      );
      expect(api.operatorKey, isEmpty);
      api.close();
    },
  );
}
