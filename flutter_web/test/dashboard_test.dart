import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:api_health_monitor/api.dart';
import 'package:api_health_monitor/main.dart';

ApiClient fakeApi({bool signedIn = false, bool viewer = false, bool offline = false}) => ApiClient(baseUrl: 'http://localhost/api/v1', client: MockClient((request) async {
  if (offline) throw Exception('Controlled offline test');
  dynamic data;
  if (request.url.path.endsWith('/demo/session')) {
    if (!signedIn && request.method == 'GET') return http.Response(jsonEncode({'error': {'code': 'SESSION_REQUIRED', 'message': 'Select a demo persona.'}}), 401);
    data = {'persona': viewer ? 'viewer' : 'operator'};
  } else if (request.url.path.endsWith('/reports/uptime')) {
    data = {'endpoints': [], 'dataset_start': null};
  } else if (request.url.path.endsWith('/scheduler')) {
    data = {'enabled': false, 'active_count': 0};
  } else {
    data = [];
  }
  return http.Response(jsonEncode({'data': data, 'correlation_id': 'test-reference'}), 200);
}));

void main() {
  testWidgets('placeholder login never requests a real password', (tester) async {
    await tester.pumpWidget(MonitorApp(api: fakeApi()));
    await tester.pumpAndSettle();
    expect(find.text('Enter the local demo'), findsOneWidget);
    expect(find.textContaining('No real authentication'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    await tester.tap(find.text('Enter dashboard'));
    await tester.pumpAndSettle();
    expect(find.text('Endpoint overview'), findsOneWidget);
    expect(find.text('No endpoints registered'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('narrow empty dashboard remains usable without overflow', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MonitorApp(api: fakeApi(signedIn: true)));
    await tester.pumpAndSettle();
    expect(find.text('Endpoint overview'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('viewer cannot submit registration and offline state is explained', (tester) async {
    await tester.pumpWidget(MonitorApp(api: fakeApi(signedIn: true, viewer: true)));
    await tester.pumpAndSettle();
    final registerButtons = tester.widgetList<FilledButton>(find.byType(FilledButton));
    expect(registerButtons.every((button) => button.onPressed == null), isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(MonitorApp(api: fakeApi(offline: true)));
    await tester.pumpAndSettle();
    expect(find.textContaining('Cannot reach the local server'), findsOneWidget);
    expect(find.text('Retry connection'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
