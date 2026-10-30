import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'api.dart';
import 'forms.dart';
import 'widgets.dart';

class MonitorHome extends StatefulWidget {
  final ApiClient? api;
  final bool autoRefresh;
  const MonitorHome({super.key, this.api, required this.autoRefresh});
  @override
  State<MonitorHome> createState() => _MonitorHomeState();
}

class _MonitorHomeState extends State<MonitorHome> {
  late final ApiClient api;
  DashboardData? data;
  Timer? timer;
  String? error;
  DateTime? synced;
  bool refreshing = false, actionBusy = false;
  int page = 0, hours = 24;
  String search = '';
  final checking = <int>{};
  final dataVersion = ValueNotifier<int>(0);
  final scaffold = GlobalKey<ScaffoldState>();
  static const labels = ['Overview', 'Services', 'Incidents', 'Reports'];
  static const icons = [
    Icons.grid_view_rounded,
    Icons.dns_outlined,
    Icons.bolt_outlined,
    Icons.bar_chart_rounded,
  ];

  @override
  void initState() {
    super.initState();
    api = widget.api ?? ApiClient();
    load();
    if (widget.autoRefresh)
      timer = Timer.periodic(const Duration(seconds: 5), (_) => load());
  }

  @override
  void dispose() {
    timer?.cancel();
    dataVersion.dispose();
    if (widget.api == null) api.close();
    super.dispose();
  }

  Future<void> load() async {
    if (refreshing) return;
    setState(() => refreshing = true);
    try {
      final result = await api.load(hours: hours);
      if (mounted) {
        setState(() {
          data = result;
          error = null;
          synced = DateTime.now();
        });
        dataVersion.value++;
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => refreshing = false);
    }
  }

  void toast(String message, {bool failed = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: failed ? const Color(0xFF8B4235) : ink,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  Future<bool> connect() async {
    final result = await connectOperator(context, api);
    if (mounted) setState(() {});
    return result;
  }

  Future<void> action(
    Future<dynamic> Function() operation,
    String message,
  ) async {
    if (!await connect() || !mounted) return;
    setState(() => actionBusy = true);
    try {
      await operation();
      await load();
      toast(message);
    } catch (e) {
      toast(e.toString(), failed: true);
    } finally {
      if (mounted) setState(() => actionBusy = false);
    }
  }

  Future<Json?> check(Json endpoint) async {
    if (!await connect() || !mounted) return null;
    final id = endpoint['id'] as int;
    if (checking.contains(id)) return null;
    setState(() => checking.add(id));
    final key =
        'web-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 30)}';
    try {
      final run = await api.check(id, key);
      await load();
      toast(
        run['success'] == true
            ? '${endpoint['name']}: completed with ${run['attempt_count']} attempt(s).'
            : '${endpoint['name']}: unavailable. Review the incident for human action.',
        failed: run['success'] != true,
      );
      return run;
    } catch (e) {
      toast(e.toString(), failed: true);
      return null;
    } finally {
      if (mounted) setState(() => checking.remove(id));
    }
  }

  Future<void> register() async {
    if (!await connect() || !mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => RegisterDialog(
        api: api,
        origins: List<String>.from(data?.config['approved_origins'] ?? []),
      ),
    );
    if (saved == true) {
      await load();
      toast('Service registered. The worker will pick up its first check.');
    }
  }

  void toggleConnection() {
    if (api.operatorKey.isEmpty) {
      connect();
    } else {
      setState(() => api.operatorKey = '');
      toast('Disconnected. Reports remain available in read-only mode.');
    }
  }

  Widget sidebar({bool drawer = false}) => Container(
    width: 228,
    color: const Color(0xFF112E2A),
    child: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(25, 30, 20, 35),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: const Color(0xFFBCE6A3),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(
                    Icons.monitor_heart_outlined,
                    color: Color(0xFF153C32),
                    size: 23,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'pulsewatch',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 21,
                        letterSpacing: -.6,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(left: 26, bottom: 13),
            child: Text(
              'WORKSPACE',
              style: TextStyle(
                color: Color(0xFF8BAAA0),
                fontSize: 9,
                letterSpacing: 2,
              ),
            ),
          ),
          ...List.generate(
            4,
            (i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 3),
              child: Semantics(
                button: true,
                child: Material(
                  color: i == page
                      ? const Color(0xFF285044)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                  child: InkWell(
                    key: Key('nav-$i'),
                    borderRadius: BorderRadius.circular(9),
                    onTap: () {
                      setState(() => page = i);
                      if (drawer) Navigator.pop(context);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            icons[i],
                            size: 19,
                            color: i == page
                                ? const Color(0xFFC2E6A8)
                                : const Color(0xFFAAC1B8),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              labels[i],
                              style: TextStyle(
                                color: i == page
                                    ? Colors.white
                                    : const Color(0xFFAAC1B8),
                                fontSize: 13,
                                fontWeight: i == page
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                          if (i == 2 &&
                              (data?.report['summary']['open_incidents'] ?? 0) >
                                  0)
                            Text(
                              '${data!.report['summary']['open_incidents']}',
                              style: const TextStyle(
                                color: Color(0xFFC2E6A8),
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const Spacer(),
          Container(
            margin: const EdgeInsets.all(17),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF36544B)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.science_outlined,
                      color: Color(0xFFBCE6A3),
                      size: 17,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Classroom lab',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Text(
                  'Controlled services.\nClear, reproducible signals.',
                  style: TextStyle(
                    color: Color(0xFFAAC1B8),
                    fontSize: 11,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(28, 0, 20, 23),
            child: Text(
              'API HEALTH MONITOR',
              style: TextStyle(
                color: Color(0xFF789B8E),
                fontSize: 9,
                letterSpacing: 1.5,
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget header(bool narrow) {
    final unread =
        data?.notifications.where((n) => n['read_at'] == null).length ?? 0;
    return Container(
      height: 76,
      padding: EdgeInsets.symmetric(horizontal: narrow ? 12 : 32),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: line)),
      ),
      child: Row(
        children: [
          if (narrow)
            IconButton(
              tooltip: 'Open navigation',
              onPressed: () => scaffold.currentState?.openDrawer(),
              icon: const Icon(Icons.menu_rounded),
            ),
          Expanded(
            child: Text(
              narrow
                  ? 'pulsewatch'
                  : 'Monitoring workspace  /  ${labels[page]}',
              style: TextStyle(
                color: narrow ? ink : muted,
                fontSize: narrow ? 19 : 12,
                fontWeight: narrow ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
          if (!narrow && data != null) ...[
            StatusPill(
              error != null ? 'offline' : data!.health['worker'] ?? 'offline',
            ),
            const SizedBox(width: 19),
          ],
          IconButton(
            tooltip: 'Notifications',
            onPressed: notifications,
            icon: Badge(
              isLabelVisible: unread > 0,
              label: Text('$unread'),
              child: const Icon(Icons.notifications_none_rounded, size: 22),
            ),
          ),
          const SizedBox(width: 7),
          if (narrow)
            IconButton(
              tooltip: api.operatorKey.isEmpty
                  ? 'Connect operator'
                  : 'Disconnect operator',
              onPressed: toggleConnection,
              icon: Icon(
                api.operatorKey.isEmpty
                    ? Icons.lock_outline
                    : Icons.verified_user_outlined,
                color: teal,
              ),
            )
          else
            OutlinedButton.icon(
              onPressed: toggleConnection,
              icon: Icon(
                api.operatorKey.isEmpty
                    ? Icons.lock_outline
                    : Icons.verified_user_outlined,
                size: 16,
              ),
              label: Text(
                api.operatorKey.isEmpty
                    ? 'Connect operator'
                    : 'Operator connected',
                style: const TextStyle(fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final narrow = c.maxWidth < 1000;
      return Scaffold(
        key: scaffold,
        drawer: narrow ? Drawer(child: sidebar(drawer: true)) : null,
        body: Row(
          children: [
            if (!narrow) sidebar(),
            Expanded(
              child: Column(
                children: [
                  header(narrow),
                  if (refreshing && data == null)
                    const LinearProgressIndicator(minHeight: 2),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1500),
                          child: Padding(
                            padding: EdgeInsets.all(c.maxWidth < 600 ? 17 : 32),
                            child: content(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );

  Widget content() {
    if (data == null) {
      if (error != null)
        return StatePanel(
          title: 'Monitoring API unavailable',
          message: error!,
          icon: Icons.cloud_off_outlined,
          action: FilledButton(
            onPressed: load,
            child: const Text('Retry connection'),
          ),
        );
      return const Padding(
        padding: EdgeInsets.only(top: 100),
        child: Center(
          child: Column(
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 20),
              Text(
                'Loading monitoring workspace…',
                style: TextStyle(color: muted),
              ),
            ],
          ),
        ),
      );
    }
    final titles = [
      'Service overview',
      'Your services',
      'Incident center',
      'Availability reports',
    ];
    final subtitles = [
      'A clear signal for every service.',
      'Keep an eye on every approved endpoint.',
      'Track the issue. Own the response. Verify recovery.',
      'Availability through recorded check results.',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (error != null) ...[
          Surface(
            padding: const EdgeInsets.all(15),
            child: Text(
              'Connection interrupted. Showing the last saved view. $error',
              style: const TextStyle(color: Color(0xFF8C5C16)),
            ),
          ),
          const SizedBox(height: 22),
        ],
        LayoutBuilder(
          builder: (context, c) {
            final title = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MONITORING  /  ${labels[page].toUpperCase()}',
                  style: const TextStyle(
                    color: teal,
                    letterSpacing: 1.8,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  titles[page],
                  style: const TextStyle(
                    fontSize: 29,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -1.1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitles[page],
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
              ],
            );
            final controls = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Refresh results',
                  onPressed: refreshing ? null : load,
                  icon: const Icon(
                    Icons.refresh_rounded,
                    size: 21,
                    color: muted,
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: register,
                  icon: const Icon(Icons.add, size: 17),
                  label: const Text(
                    'Add service',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            );
            if (c.maxWidth < 680)
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [title, const SizedBox(height: 18), controls],
              );
            return Row(
              children: [
                Expanded(child: title),
                controls,
              ],
            );
          },
        ),
        const SizedBox(height: 14),
        Text(
          '${error == null ? 'Auto-refresh every 5 seconds' : 'View is stale'}  ·  Last synced ${synced == null ? '—' : prettyTime(synced!.toUtc().toIso8601String())}',
          style: const TextStyle(fontSize: 10, color: muted),
        ),
        const SizedBox(height: 27),
        if (page == 0) ...overview(),
        if (page == 1) ...[
          TextField(
            decoration: const InputDecoration(
              hintText: 'Search services',
              prefixIcon: Icon(Icons.search, size: 19),
            ),
            onChanged: (v) => setState(() => search = v.toLowerCase()),
          ),
          const SizedBox(height: 18),
          services(),
        ],
        if (page == 2) incidents(),
        if (page == 3) ...reports(),
        const SizedBox(height: 28),
        const Text(
          'Availability is based on recorded checks. Controlled demo services contain fictional data.',
          style: TextStyle(color: muted, fontSize: 10, height: 1.6),
        ),
      ],
    );
  }

  Widget metrics() {
    final s = data!.report['summary'];
    final cards = [
      MetricCard(
        label: 'Healthy services',
        value: '${s['healthy']} / ${s['total_endpoints']}',
        detail:
            '${s['unavailable']} unavailable · ${s['recovering']} recovering',
        icon: Icons.sensors_rounded,
      ),
      MetricCard(
        label: 'Observed uptime',
        value: percent(s['uptime_percent']),
        detail: 'Successful checks · last $hours hours',
        icon: Icons.trending_up_rounded,
      ),
      MetricCard(
        label: 'Open incidents',
        value: '${s['open_incidents']}',
        detail: 'Awaiting action or verified recovery',
        icon: Icons.bolt_outlined,
        color: const Color(0xFFC66B3A),
      ),
      MetricCard(
        label: 'Avg. response',
        value: millis(s['avg_response_ms']),
        detail: 'Per-attempt elapsed time',
        icon: Icons.timer_outlined,
      ),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final columns = c.maxWidth >= 950
            ? 4
            : c.maxWidth >= 480
            ? 2
            : 1;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: cards
              .map(
                (card) => SizedBox(
                  width: (c.maxWidth - 16 * (columns - 1)) / columns,
                  child: card,
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget section(String title, String subtitle, {Widget? action}) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17),
            ),
            const SizedBox(height: 5),
            Text(subtitle, style: const TextStyle(color: muted, fontSize: 11)),
          ],
        ),
      ),
      if (action != null) action,
    ],
  );
  Widget policyLine(String label, String value) => Row(
    children: [
      Expanded(
        child: Text(label, style: const TextStyle(color: muted, fontSize: 11)),
      ),
      Text(
        value,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
      ),
    ],
  );
  List<Widget> overview() => [
    metrics(),
    const SizedBox(height: 28),
    if (data!.health['worker'] != 'online') ...[
      const Surface(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.schedule, color: Color(0xFFA46A13)),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Scheduled monitoring is offline. Start the worker to keep checks running independently of this browser.',
                style: TextStyle(color: muted, fontSize: 12, height: 1.5),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
    ],
    section(
      'Service health',
      '${data!.endpoints.length} registered services',
      action: TextButton(
        onPressed: () => setState(() => page = 1),
        child: const Text(
          'View all services →',
          style: TextStyle(fontSize: 11),
        ),
      ),
    ),
    const SizedBox(height: 15),
    services(limit: 5),
    const SizedBox(height: 27),
    LayoutBuilder(
      builder: (context, c) {
        final activity = Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              section('Recent activity', 'Latest check cycles'),
              const SizedBox(height: 10),
              if ((data!.report['recent_runs'] as List).isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 25),
                  child: Text(
                    'Your check results will appear here.',
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                ),
              ...(data!.report['recent_runs'] as List)
                  .take(5)
                  .map(
                    (r) => Column(
                      children: [
                        RunTile(Json.from(r)),
                        const Divider(height: 1),
                      ],
                    ),
                  ),
            ],
          ),
        );
        final policy = Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.verified_outlined, color: teal, size: 26),
              const SizedBox(height: 17),
              const Text(
                'Recovery, with evidence.',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              const Text(
                'A successful retry clears a transient failure. An outage stays open until consecutive checks confirm the service is back.',
                style: TextStyle(color: muted, fontSize: 12, height: 1.8),
              ),
              const SizedBox(height: 20),
              policyLine(
                'Maximum attempts',
                '${data!.config['max_attempts']} per cycle',
              ),
              const Divider(height: 24),
              policyLine(
                'Recovery verification',
                '${data!.config['recovery_successes']} successful cycles',
              ),
              const Divider(height: 24),
              policyLine('Human ownership', 'Support personnel'),
            ],
          ),
        );
        if (c.maxWidth < 800)
          return Column(
            children: [activity, const SizedBox(height: 18), policy],
          );
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 3, child: activity),
            const SizedBox(width: 20),
            Expanded(flex: 2, child: policy),
          ],
        );
      },
    ),
  ];

  Widget services({int? limit}) {
    final list = data!.endpoints
        .where((e) => '${e['name']} ${e['url']}'.toLowerCase().contains(search))
        .toList();
    if (data!.endpoints.isEmpty)
      return StatePanel(
        title: 'Bring your first service online',
        message: 'Register an approved endpoint, or start with controlled services\nto explore healthy, retry, and outage scenarios.',
        action: Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.center,
          children: [
            FilledButton.icon(
              onPressed: register,
              icon: const Icon(Icons.add, size: 17),
              label: const Text('Register a service'),
            ),
            if (data!.config['demo_enabled'] == true)
              OutlinedButton(
                onPressed: actionBusy
                    ? null
                    : () => action(
                        () => api.request(
                          'POST',
                          '/api/demo/seed',
                          protected: true,
                        ),
                        'Three controlled services are ready.',
                      ),
                child: Text(actionBusy ? 'Preparing…' : 'Add demo services'),
              ),
          ],
        ),
      );
    if (list.isEmpty)
      return const StatePanel(
        title: 'No matching services',
        message: 'Try another service name or URL.',
        icon: Icons.search_off,
      );
    return Surface(
      padding: EdgeInsets.zero,
      child: Column(children: list.take(limit ?? 50).map(serviceRow).toList()),
    );
  }

  Widget serviceRow(Json e) => LayoutBuilder(
    builder: (context, c) {
      final last = e['last_run'];
      final latency = last != null && (last['attempts'] as List).isNotEmpty
          ? (last['attempts'] as List).last['duration_ms']
          : null;
      final identity = Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: canvas,
              border: Border.all(color: line),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.dns_outlined, size: 19, color: teal),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e['name'],
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  e['url'],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: muted, fontSize: 10),
                ),
              ],
            ),
          ),
        ],
      );
      final runButton = IconButton(
        tooltip: 'Check ${e['name']} now',
        onPressed: checking.contains(e['id']) || !e['enabled']
            ? null
            : () => check(e),
        icon: checking.contains(e['id'])
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.play_arrow_rounded, color: teal, size: 23),
      );
      return InkWell(
        onTap: () => details(e),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: line)),
          ),
          child: c.maxWidth < 650
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    identity,
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        StatusPill(e['enabled'] ? e['status'] : 'paused'),
                        const Spacer(),
                        Text(
                          millis(latency),
                          style: const TextStyle(color: muted, fontSize: 11),
                        ),
                        runButton,
                      ],
                    ),
                    const SizedBox(height: 15),
                    SampleBars(e['recent_samples']),
                  ],
                )
              : Row(
                  children: [
                    Expanded(flex: 4, child: identity),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 110,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: StatusPill(
                          e['enabled'] ? e['status'] : 'paused',
                        ),
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SampleBars(e['recent_samples']),
                          const SizedBox(height: 5),
                          const Text(
                            'Last 24 check results',
                            style: TextStyle(color: muted, fontSize: 9),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 23),
                    SizedBox(
                      width: 66,
                      child: Text(
                        millis(latency),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    runButton,
                    const Icon(Icons.chevron_right, color: muted, size: 19),
                  ],
                ),
        ),
      );
    },
  );

  Future<void> details(Json endpoint) async {
    var history = api.history(endpoint['id']);
    bool busy = false;
    String? demoFeedback;
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (context) => ValueListenableBuilder<int>(
        valueListenable: dataVersion,
        builder: (context, version, child) => StatefulBuilder(
          builder: (context, update) {
            final e = data!.endpoints.firstWhere(
              (e) => e['id'] == endpoint['id'],
              orElse: () => endpoint,
            );
            final demo =
                data!.config['demo_enabled'] == true &&
                e['url'].toString().endsWith('/health/persistent');
            return Dialog(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 740,
                  maxHeight: MediaQuery.sizeOf(context).height * .85,
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(25),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              e['name'],
                              style: const TextStyle(
                                fontSize: 23,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Close service details',
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      SelectableText(
                        e['url'],
                        style: const TextStyle(color: muted, fontSize: 12),
                      ),
                      const SizedBox(height: 17),
                      Wrap(
                        spacing: 12,
                        runSpacing: 9,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          StatusPill(e['enabled'] ? e['status'] : 'paused'),
                          Text(
                            'Every ${e['interval_seconds']}s · Timeout ${e['timeout_seconds']}s',
                            style: const TextStyle(color: muted, fontSize: 11),
                          ),
                          Text(
                            'Last check ${prettyTime(e['last_check_at'])}',
                            style: const TextStyle(color: muted, fontSize: 11),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      SampleBars(e['recent_samples']),
                      const SizedBox(height: 22),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          FilledButton.icon(
                            onPressed: busy || !e['enabled']
                                ? null
                                : () async {
                                    update(() => busy = true);
                                    await check(e);
                                    if (context.mounted)
                                      update(() {
                                        history = api.history(e['id']);
                                        busy = false;
                                      });
                                  },
                            icon: const Icon(Icons.play_arrow, size: 17),
                            label: Text(busy ? 'Checking…' : 'Check now'),
                          ),
                          OutlinedButton(
                            onPressed: busy
                                ? null
                                : () async {
                                    await action(
                                      () => api.request(
                                        'PATCH',
                                        '/api/endpoints/${e['id']}',
                                        protected: true,
                                        body: {'enabled': !e['enabled']},
                                      ),
                                      e['enabled']
                                          ? 'Scheduled checks paused.'
                                          : 'Scheduled checks resumed.',
                                    );
                                    if (context.mounted) update(() {});
                                  },
                            child: Text(
                              e['enabled'] ? 'Pause service' : 'Resume service',
                            ),
                          ),
                        ],
                      ),
                      if (e['status'] == 'recovering')
                        Padding(
                          padding: const EdgeInsets.only(top: 17),
                          child: Text(
                            'Recovery verification: ${e['recovery_streak']} / ${data!.config['recovery_successes']} successful cycles.',
                            style: const TextStyle(color: teal),
                          ),
                        ),
                      if (demo) ...[
                        const SizedBox(height: 22),
                        const Divider(),
                        const SizedBox(height: 10),
                        const Text(
                          'Controlled outage scenario',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Repair the fictional dependency, then run checks to verify recovery.',
                          style: TextStyle(color: muted, fontSize: 11),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            OutlinedButton(
                              onPressed: busy
                                  ? null
                                  : () async {
                                      if (!await connect() || !context.mounted)
                                        return;
                                      update(() {
                                        busy = true;
                                        demoFeedback = null;
                                      });
                                      try {
                                        await api.request(
                                          'POST',
                                          '/api/demo/recover',
                                          protected: true,
                                        );
                                        if (context.mounted)
                                          update(
                                            () => demoFeedback = 'Demo repaired. Run two successful checks to verify recovery.',
                                          );
                                      } catch (error) {
                                        if (context.mounted)
                                          update(
                                            () =>
                                                demoFeedback = error.toString(),
                                          );
                                      } finally {
                                        if (context.mounted)
                                          update(() => busy = false);
                                      }
                                    },
                              child: const Text('Repair demo service'),
                            ),
                            TextButton(
                              onPressed: busy
                                  ? null
                                  : () async {
                                      if (!await connect() || !context.mounted)
                                        return;
                                      update(() {
                                        busy = true;
                                        demoFeedback = null;
                                      });
                                      try {
                                        await api.request(
                                          'POST',
                                          '/api/demo/reset',
                                          protected: true,
                                        );
                                        if (context.mounted)
                                          update(
                                            () => demoFeedback = 'Controlled outage restored. Run a check to capture the failure.',
                                          );
                                      } catch (error) {
                                        if (context.mounted)
                                          update(
                                            () =>
                                                demoFeedback = error.toString(),
                                          );
                                      } finally {
                                        if (context.mounted)
                                          update(() => busy = false);
                                      }
                                    },
                              child: const Text('Reset demo outage'),
                            ),
                          ],
                        ),
                        if (demoFeedback != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 14),
                            child: Semantics(
                              liveRegion: true,
                              child: Text(
                                demoFeedback!,
                                style: const TextStyle(
                                  color: teal,
                                  fontSize: 12,
                                  height: 1.6,
                                ),
                              ),
                            ),
                          ),
                      ],
                      const SizedBox(height: 25),
                      const Text(
                        'Check history & attempts',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      FutureBuilder<List<Json>>(
                        future: history,
                        builder: (context, snapshot) {
                          if (snapshot.hasError)
                            return Padding(
                              padding: const EdgeInsets.all(15),
                              child: Text(
                                snapshot.error.toString(),
                                style: const TextStyle(color: Colors.red),
                              ),
                            );
                          if (!snapshot.hasData)
                            return const Padding(
                              padding: EdgeInsets.all(24),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          if (snapshot.data!.isEmpty)
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 24),
                              child: Text(
                                'No check results yet.',
                                style: TextStyle(color: muted),
                              ),
                            );
                          return Column(
                            children: snapshot.data!
                                .map(
                                  (r) => Column(
                                    children: [
                                      RunTile(r, showAttempts: true),
                                      const Divider(height: 1),
                                    ],
                                  ),
                                )
                                .toList(),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget incidents() {
    if (data!.incidents.isEmpty)
      return const StatePanel(
        title: 'No incidents recorded',
        message: 'When a service exhausts its retries, its incident and support action will appear here.',
        icon: Icons.check_circle_outline,
      );
    return Column(
      children: data!.incidents
          .map(
            (i) => Padding(
              padding: const EdgeInsets.only(bottom: 15),
              child: Surface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 14,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          i['endpoint_name'],
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        StatusPill(i['status']),
                        Text(
                          'INC-${i['id'].toString().padLeft(3, '0')}',
                          style: const TextStyle(color: muted, fontSize: 11),
                        ),
                      ],
                    ),
                    const SizedBox(height: 15),
                    Text(
                      'Owner: ${i['owner_group']}  ·  Opened ${prettyTime(i['opened_at'])}',
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                    const SizedBox(height: 9),
                    if (i['acknowledged_by'] != null)
                      Text(
                        'Acknowledged by ${i['acknowledged_by']} · ${prettyTime(i['acknowledged_at'])}',
                        style: const TextStyle(color: muted, fontSize: 12),
                      ),
                    if (i['note'] != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          i['note'],
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    if (i['status'] == 'recovered')
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          'Verified recovery ${prettyTime(i['recovered_at'])}',
                          style: const TextStyle(color: teal, fontSize: 12),
                        ),
                      ),
                    if (i['status'] != 'recovered') ...[
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 12,
                        runSpacing: 10,
                        children: [
                          if (i['status'] == 'open')
                            FilledButton.icon(
                              onPressed: () => acknowledge(i),
                              icon: const Icon(Icons.done, size: 16),
                              label: const Text('Acknowledge'),
                            ),
                          OutlinedButton(
                            onPressed: () => details(
                              data!.endpoints.firstWhere(
                                (e) => e['id'] == i['endpoint_id'],
                              ),
                            ),
                            child: const Text('Inspect service'),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Future<void> acknowledge(Json incident) async {
    if (!await connect() || !mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => AcknowledgeDialog(api: api, incidentId: incident['id']),
    );
    if (saved == true) {
      await load();
      toast(
        'Incident acknowledged. Recovery still requires successful checks.',
      );
    }
  }

  List<Widget> reports() => [
    Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: 220,
        child: DropdownButtonFormField<int>(
          isExpanded: true,
          initialValue: hours,
          decoration: const InputDecoration(labelText: 'Reporting window'),
          items: const [
            DropdownMenuItem(value: 1, child: Text('Last hour')),
            DropdownMenuItem(value: 24, child: Text('Last 24 hours')),
            DropdownMenuItem(value: 168, child: Text('Last 7 days')),
            DropdownMenuItem(value: 720, child: Text('Last 30 days')),
          ],
          onChanged: (v) {
            if (v != null) {
              setState(() => hours = v);
              load();
            }
          },
        ),
      ),
    ),
    const SizedBox(height: 22),
    metrics(),
    const SizedBox(height: 25),
    Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          section(
            'Check-based availability',
            '${data!.report['summary']['completed_checks']} completed cycles in this window',
          ),
          const SizedBox(height: 20),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingTextStyle: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 11,
                color: muted,
              ),
              dataTextStyle: const TextStyle(fontSize: 12, color: ink),
              columnSpacing: 27,
              columns: const [
                DataColumn(label: Text('SERVICE')),
                DataColumn(label: Text('CHECKS')),
                DataColumn(label: Text('SUCCESS')),
                DataColumn(label: Text('FAILED')),
                DataColumn(label: Text('RETRIES')),
                DataColumn(label: Text('UPTIME')),
              ],
              rows: (data!.report['endpoints'] as List)
                  .map(
                    (e) => DataRow(
                      cells: [
                        DataCell(Text(e['name'])),
                        DataCell(Text('${e['completed_checks']}')),
                        DataCell(Text('${e['successful_checks']}')),
                        DataCell(Text('${e['failed_checks']}')),
                        DataCell(Text('${e['retry_attempts']}')),
                        DataCell(Text(percent(e['uptime_percent']))),
                      ],
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 19),
          Text(
            data!.report['definition'],
            style: const TextStyle(color: muted, fontSize: 11, height: 1.7),
          ),
          const SizedBox(height: 8),
          Text(
            '${data!.report['summary']['transient_recoveries']} transient recoveries · Generated ${prettyTime(data!.report['generated_at'])}',
            style: const TextStyle(fontSize: 11, color: muted),
          ),
        ],
      ),
    ),
  ];
  Future<void> notifications() async {
    if (data == null) return;
    await showDialog(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 520,
            maxHeight: MediaQuery.sizeOf(context).height * .8,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(25),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Notifications',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close notifications',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                if (data!.notifications.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 25),
                    child: Text(
                      'No outage or recovery notifications yet.',
                      style: TextStyle(color: muted),
                    ),
                  ),
                ...data!.notifications.map(
                  (n) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              n['kind'] == 'recovery'
                                  ? Icons.check_circle_outline
                                  : Icons.bolt_outlined,
                              color: n['kind'] == 'recovery'
                                  ? teal
                                  : const Color(0xFFC3473A),
                              size: 19,
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                n['kind'] == 'recovery'
                                    ? 'Recovery verified'
                                    : 'Human action required',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 9),
                        Text(
                          n['message'],
                          style: const TextStyle(
                            color: muted,
                            fontSize: 12,
                            height: 1.6,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          prettyTime(n['created_at']),
                          style: const TextStyle(color: muted, fontSize: 10),
                        ),
                        if (n['read_at'] == null)
                          TextButton(
                            onPressed: () async {
                              await action(
                                () => api.request(
                                  'POST',
                                  '/api/notifications/${n['id']}/read',
                                  protected: true,
                                ),
                                'Notification marked as read.',
                              );
                              if (context.mounted) Navigator.pop(context);
                            },
                            child: const Text(
                              'Mark as read',
                              style: TextStyle(fontSize: 11),
                            ),
                          ),
                        const Divider(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
