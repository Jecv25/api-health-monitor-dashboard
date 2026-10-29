import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'api.dart';
import 'validation.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SemanticsBinding.instance.ensureSemantics();
  runApp(const MonitorApp());
}

const ink = Color(0xFF142635);
const muted = Color(0xFF617485);
const accent = Color(0xFF087E83);
const surface = Color(0xFFF2F5F8);
const border = Color(0xFFDCE4EA);
const behaviorNames = {
  'stable': 'Always healthy · 200',
  'flaky': 'Transient · 503, 503, 200',
  'dead': 'Persistent outage · 503',
  'broken': 'Wrong path · 404',
};

class MonitorApp extends StatelessWidget {
  final ApiClient? api;
  const MonitorApp({super.key, this.api});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Pulseboard | API Health Monitor', debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, scaffoldBackgroundColor: surface,
      colorScheme: ColorScheme.fromSeed(seedColor: accent, primary: accent, surface: Colors.white),
      fontFamily: 'Roboto',
      textTheme: const TextTheme(bodyMedium: TextStyle(color: ink), bodySmall: TextStyle(color: muted)),
      inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: const Color(0xFFF8FAFC), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: border))),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)))),
      outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)))),
      cardTheme: CardThemeData(elevation: 0, color: Colors.white, margin: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: border))),
    ), home: Dashboard(api: api ?? ApiClient()));
}

class PendingMutation {
  final String path;
  final String method;
  final Map<String, dynamic> body;
  final String key;
  final String success;
  final void Function(dynamic)? after;
  PendingMutation(this.path, this.method, this.body, this.success, this.after) : key = mutationKey();
}

class Dashboard extends StatefulWidget {
  final ApiClient api;
  const Dashboard({super.key, required this.api});
  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  Map<String, dynamic>? session;
  String page = 'endpoints';
  String persona = 'operator';
  bool loading = true, busy = false, refreshing = false, activeOnly = false;
  int? selectedId;
  List<dynamic> endpoints = [], incidents = [], notices = [], logs = [], results = [];
  Map<String, dynamic> scheduler = {}, report = {}, detail = {};
  Map<int, Map<String, dynamic>> runs = {};
  ApiFailure? error;
  PendingMutation? pending;
  DateTime? refreshedAt;
  Timer? timer;
  final name = TextEditingController();
  final url = TextEditingController();
  final interval = TextEditingController(text: '60');
  final logFilter = TextEditingController();
  final nameFocus = FocusNode(), urlFocus = FocusNode(), intervalFocus = FocusNode();
  final formKey = GlobalKey<FormState>();
  String behavior = 'stable';
  Map<String, dynamic> fieldErrors = {};

  bool get operator => session?['persona'] == 'operator';
  @override
  void initState() {
    super.initState();
    unawaited(restore());
    timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (session != null && !busy && !refreshing && page != 'register' && page != 'guide') unawaited(load(background: true));
    });
  }
  @override
  void dispose() { timer?.cancel(); name.dispose(); url.dispose(); interval.dispose(); logFilter.dispose(); nameFocus.dispose(); urlFocus.dispose(); intervalFocus.dispose(); widget.api.close(); super.dispose(); }

  Future<void> restore() async {
    try { session = Map<String, dynamic>.from(await widget.api.request('/demo/session') as Map); }
    on ApiFailure catch (e) { if (e.status != 401) error = e; }
    if (!mounted) return;
    if (session != null) await load();
    if (mounted) setState(() => loading = false);
  }
  void showError(ApiFailure e) {
    if (!mounted) return;
    setState(() {
      error = e;
      if (e.status == 401) { session = null; page = 'endpoints'; }
    });
  }
  Future<void> login() async {
    setState(() { busy = true; error = null; });
    try {
      final data = await widget.api.request('/demo/session', method: 'POST', body: {'persona': persona});
      if (!mounted) return;
      setState(() => session = Map<String, dynamic>.from(data as Map));
      await load();
    } on ApiFailure catch (e) { showError(e); }
    finally { if (mounted) setState(() { busy = false; loading = false; }); }
  }
  Future<void> logout() async {
    try { await widget.api.request('/demo/session', method: 'DELETE'); if (mounted) setState(() { session = null; pending = null; error = null; }); }
    on ApiFailure catch (e) { showError(e); }
  }
  Future<void> load({bool background = false}) async {
    if (refreshing || session == null) return;
    refreshing = true;
    if (!background && mounted) setState(() => loading = true);
    try {
      final values = await Future.wait([
        widget.api.request('/endpoints'), widget.api.request('/scheduler'), widget.api.request('/incidents'),
        widget.api.request('/notifications'), widget.api.request('/reports/uptime'),
      ]);
      Map<String, dynamic>? nextDetail;
      List<dynamic>? nextResults, nextLogs;
      final nextRuns = <int, Map<String, dynamic>>{};
      if (selectedId != null && page == 'detail') {
        nextDetail = Map<String, dynamic>.from(await widget.api.request('/endpoints/$selectedId') as Map);
        nextResults = await widget.api.request('/endpoints/$selectedId/results') as List;
        final recent = nextDetail['recent_runs'] as List? ?? [];
        for (final run in recent.take(3)) {
          nextRuns[run['id'] as int] = Map<String, dynamic>.from(await widget.api.request('/checks/${run['id']}') as Map);
        }
      }
      if (page == 'logs') nextLogs = await widget.api.request('/logs?limit=100${logFilter.text.trim().isEmpty ? '' : '&correlation_id=${Uri.encodeQueryComponent(logFilter.text.trim())}'}') as List;
      if (!mounted) return;
      setState(() {
        endpoints = values[0] as List; scheduler = Map<String, dynamic>.from(values[1] as Map);
        incidents = values[2] as List; notices = values[3] as List; report = Map<String, dynamic>.from(values[4] as Map);
        if (nextDetail != null) detail = nextDetail;
        if (nextResults != null) results = nextResults;
        if (nextLogs != null) logs = nextLogs;
        if (nextRuns.isNotEmpty || page == 'detail') runs = nextRuns;
        refreshedAt = DateTime.now();
        if (pending == null) error = null;
      });
    } on ApiFailure catch (e) { showError(e); }
    finally { refreshing = false; if (mounted) setState(() => loading = false); }
  }
  void navigate(String target, {int? id}) {
    setState(() { page = target; selectedId = id; error = null; });
    if (target != 'register' && target != 'guide') unawaited(load());
  }
  Future<void> mutate(String path, String success, {String method = 'POST', Map<String, dynamic> body = const {}, void Function(dynamic)? after}) async {
    if (busy) return;
    if (pending != null) {
      showError(const ApiFailure(0, 'OUTCOME_UNCERTAIN', 'Resolve the previous request using Retry before starting another action.'));
      return;
    }
    pending = PendingMutation(path, method, body, success, after);
    await sendPending();
  }
  Future<void> sendPending() async {
    final action = pending;
    if (action == null || busy) return;
    setState(() { busy = true; error = null; fieldErrors = {}; });
    try {
      final data = await widget.api.request(action.path, method: action.method, body: action.body, key: action.key);
      pending = null;
      if (!mounted) return;
      action.after?.call(data);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(action.success)));
      await load();
    } on ApiFailure catch (e) {
      if (e.status != 0 && e.status < 500) pending = null;
      if (mounted) setState(() => fieldErrors = e.fields);
      showError(e);
    } finally { if (mounted) setState(() => busy = false); }
  }
  Future<void> runCheck(int id) => mutate('/endpoints/$id/checks', 'Check accepted. Its result will appear after verification.', after: (_) { page = 'detail'; selectedId = id; });
  Future<void> register() async {
    setState(() => fieldErrors = {});
    if (!formKey.currentState!.validate()) {
      if (validateName(name.text) != null) { nameFocus.requestFocus(); }
      else if (validateUrl(url.text) != null) { urlFocus.requestFocus(); }
      else { intervalFocus.requestFocus(); }
      return;
    }
    await mutate('/endpoints', 'Endpoint registered.', body: {'name': name.text.trim(), 'url': url.text.trim(), 'interval_seconds': int.parse(interval.text.trim()), 'demo_behavior': behavior}, after: (_) {
      name.clear(); url.clear(); interval.text = '60'; behavior = 'stable'; page = 'endpoints';
    });
  }

  @override
  Widget build(BuildContext context) {
    if (session == null) return loginScreen();
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    return Scaffold(
      drawer: wide ? null : Drawer(backgroundColor: ink, child: SafeArea(child: navigation())),
      appBar: wide ? null : AppBar(backgroundColor: ink, foregroundColor: Colors.white, title: const Text('Pulseboard'), actions: [IconButton(tooltip: 'Refresh records', onPressed: busy ? null : () => unawaited(load()), icon: const Icon(Icons.refresh))]),
      body: Row(children: [
        if (wide) SizedBox(width: 238, child: ColoredBox(color: ink, child: navigation())),
        Expanded(child: Column(children: [
          if (wide) Container(height: 70, color: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 32), child: Row(children: [
            const Icon(Icons.science_outlined, size: 18, color: muted), const SizedBox(width: 9), const Text('WORKSPACE / FICTIONAL SANDBOX', style: TextStyle(color: muted, fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w700)),
            const Spacer(), personaBadge(), const SizedBox(width: 14), IconButton(tooltip: 'Refresh records', onPressed: busy ? null : () => unawaited(load()), icon: const Icon(Icons.refresh, color: muted)),
          ])),
          if (busy || loading) const LinearProgressIndicator(minHeight: 3, semanticsLabel: 'Loading monitoring records'),
          Expanded(child: SingleChildScrollView(padding: EdgeInsets.all(wide ? 32 : 18), child: Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1400), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (error != null) ...[errorPanel(), const SizedBox(height: 18)],
            content(), const SizedBox(height: 24),
            Wrap(spacing: 12, runSpacing: 8, alignment: WrapAlignment.spaceBetween, children: [
              Text('MODULE 13 · CONTROLLED LOCAL DEMO', style: TextStyle(fontSize: 10, color: muted.withValues(alpha: .9), letterSpacing: 1)),
              Text(refreshedAt == null ? 'No verified records loaded' : 'Last refreshed ${time(refreshedAt!.toUtc().toIso8601String())}', style: const TextStyle(fontSize: 11, color: muted)),
            ]),
          ]))))),
        ])),
      ]),
    );
  }

  Widget loginScreen() => Scaffold(body: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 470), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    const Icon(Icons.monitor_heart_outlined, color: accent, size: 58), const SizedBox(height: 18),
    const Text('Pulseboard', textAlign: TextAlign.center, style: TextStyle(fontSize: 38, fontWeight: FontWeight.w800, color: ink, letterSpacing: -1.2)),
    const SizedBox(height: 6), const Text('A clearer view of API health.', textAlign: TextAlign.center, style: TextStyle(color: muted, fontSize: 16)), const SizedBox(height: 32),
    Card(child: Padding(padding: const EdgeInsets.all(28), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('Enter the local demo', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 22)), const SizedBox(height: 10),
      const Text('Placeholder login. No real authentication or password is used. Select a fictional persona to explore the workflow.', style: TextStyle(color: muted, height: 1.5)), const SizedBox(height: 24),
      DropdownButtonFormField<String>(initialValue: persona, isExpanded: true, decoration: const InputDecoration(labelText: 'Demo persona'), items: const [DropdownMenuItem(value: 'operator', child: Text('Operator · can manage the demo', overflow: TextOverflow.ellipsis)), DropdownMenuItem(value: 'viewer', child: Text('Viewer · read only', overflow: TextOverflow.ellipsis))], onChanged: busy ? null : (v) => setState(() => persona = v!)),
      const SizedBox(height: 22), FilledButton.icon(onPressed: busy ? null : () => unawaited(login()), icon: const Icon(Icons.arrow_forward, size: 18), label: Text(busy ? 'Connecting…' : 'Enter dashboard')),
      if (error != null) ...[const SizedBox(height: 18), errorPanel()],
    ]))), const SizedBox(height: 22), const Text('Fictional services. Controlled faults. Observable recovery.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: muted)),
  ])))));

  Widget navigation() {
    final entries = [('endpoints', 'Endpoints', Icons.dns_outlined), ('register', 'Register endpoint', Icons.add_circle_outline), ('incidents', 'Incidents', Icons.warning_amber_rounded), ('report', 'Uptime report', Icons.bar_chart_rounded), ('logs', 'Structured logs', Icons.terminal_rounded), ('guide', 'Evidence guide', Icons.menu_book_outlined)];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Padding(padding: EdgeInsets.fromLTRB(23, 32, 20, 8), child: Row(children: [Icon(Icons.monitor_heart_outlined, color: Color(0xFF57CFCC), size: 29), SizedBox(width: 10), Text('Pulseboard', style: TextStyle(color: Colors.white, fontSize: 23, fontWeight: FontWeight.w700, letterSpacing: -.5))])),
      const Padding(padding: EdgeInsets.fromLTRB(24, 0, 20, 36), child: Text('API HEALTH MONITOR', style: TextStyle(color: Color(0xFF91A9BB), fontSize: 10, letterSpacing: 1.6))),
      ...entries.map((entry) {
        final selected = page == entry.$1 || (page == 'detail' && entry.$1 == 'endpoints');
        final count = incidents.where((x) => x['state'] == 'OPEN').length;
        return Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3), child: Material(color: selected ? const Color(0xFF24515B) : Colors.transparent, borderRadius: BorderRadius.circular(9), child: ListTile(
          selected: selected, leading: Icon(entry.$3, size: 20, color: selected ? const Color(0xFF91E2DE) : const Color(0xFFABBDCA)),
          title: Text(entry.$2, style: TextStyle(fontSize: 13, fontWeight: selected ? FontWeight.w700 : FontWeight.w400, color: Colors.white)),
          trailing: entry.$1 == 'incidents' && count > 0 ? Tooltip(message: 'Unacknowledged incidents', child: CircleAvatar(radius: 11, backgroundColor: const Color(0xFFB33E3E), child: Text('$count', style: const TextStyle(color: Colors.white, fontSize: 11)))) : null,
          onTap: () { if (MediaQuery.sizeOf(context).width < 1000) Navigator.pop(context); navigate(entry.$1); },
        )));
      }),
      const Spacer(),
      Container(margin: const EdgeInsets.all(18), padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFF203A49), borderRadius: BorderRadius.circular(10)), child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('SANDBOX MODE', style: TextStyle(color: Color(0xFF7CDAD2), fontWeight: FontWeight.w700, fontSize: 10, letterSpacing: 1)), SizedBox(height: 8), Text('Fictional data only.\nNo production services.', style: TextStyle(color: Color(0xFFB4C6D1), fontSize: 12, height: 1.6))])),
      ListTile(leading: const Icon(Icons.logout, color: Color(0xFFABBDCA), size: 20), title: const Text('Leave demo', style: TextStyle(color: Colors.white, fontSize: 13)), onTap: () => unawaited(logout())), const SizedBox(height: 14),
    ]);
  }
  Widget personaBadge() => Row(mainAxisSize: MainAxisSize.min, children: [CircleAvatar(radius: 15, backgroundColor: const Color(0xFFE1F1F0), child: Text(operator ? 'OP' : 'VW', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: accent))), const SizedBox(width: 9), Text(operator ? 'Demo operator' : 'Demo viewer', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))]);
  Widget content() => switch (page) { 'register' => registrationScreen(), 'detail' => detailScreen(), 'incidents' => incidentScreen(), 'report' => reportScreen(), 'logs' => logsScreen(), 'guide' => guideScreen(), _ => endpointScreen() };
  Widget heading(String title, String subtitle, {List<Widget> actions = const []}) => Padding(padding: const EdgeInsets.only(bottom: 24), child: Wrap(alignment: WrapAlignment.spaceBetween, runSpacing: 18, spacing: 20, crossAxisAlignment: WrapCrossAlignment.center, children: [
    Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [Text(title, style: const TextStyle(fontSize: 29, color: ink, fontWeight: FontWeight.w800, letterSpacing: -.8)), const SizedBox(height: 8), ConstrainedBox(constraints: const BoxConstraints(maxWidth: 650), child: Text(subtitle, style: const TextStyle(color: muted, height: 1.5, fontSize: 13)))]),
    if (actions.isNotEmpty) Wrap(spacing: 9, runSpacing: 9, children: actions),
  ]));
  Widget panel(Widget child) => Card(child: Padding(padding: const EdgeInsets.all(22), child: child));
  Widget empty(String title, String description, {Widget? action}) => panel(Center(child: Padding(padding: const EdgeInsets.symmetric(vertical: 24), child: Column(children: [const Icon(Icons.inbox_outlined, size: 36, color: muted), const SizedBox(height: 12), Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)), const SizedBox(height: 8), Text(description, textAlign: TextAlign.center, style: const TextStyle(color: muted)), if (action != null) ...[const SizedBox(height: 18), action]]))));
  Widget errorPanel() {
    final e = error!;
    return Semantics(liveRegion: true, child: Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: const Color(0xFFFFF0EE), border: Border.all(color: const Color(0xFFF1C8C3)), borderRadius: BorderRadius.circular(10)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(e.status == 403 ? 'Action unavailable for this persona' : e.status == 0 ? 'Connection or request needs attention' : 'Request could not be completed', style: const TextStyle(color: Color(0xFF9C332B), fontWeight: FontWeight.w700)), const SizedBox(height: 6),
      Text(e.message, style: const TextStyle(color: Color(0xFF87382F))),
      if (e.correlation != null) ...[const SizedBox(height: 7), SelectableText('Reference: ${e.correlation}', style: const TextStyle(fontSize: 11, color: muted))],
      if (e.status == 0 || e.status >= 500) TextButton.icon(onPressed: busy ? null : () => unawaited(pending != null ? sendPending() : session == null ? restore() : load()), icon: const Icon(Icons.refresh, size: 16), label: Text(pending != null ? 'Retry original request safely' : 'Retry connection')),
    ])));
  }
  Widget pill(String status) {
    final (fg, bg) = switch (status) {
      'UP' || 'RECOVERED' || 'pass' => (const Color(0xFF146846), const Color(0xFFE3F3EB)),
      'DOWN' || 'OPEN' || 'fail' => (const Color(0xFFA12D2D), const Color(0xFFFBE8E6)),
      'CHECKING' || 'RUNNING' || 'ACKNOWLEDGED' => (const Color(0xFF8A5A13), const Color(0xFFFFF2D6)),
      _ => (muted, const Color(0xFFEDF1F5)),
    };
    return Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5), decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)), child: Text(status, style: TextStyle(color: fg, fontSize: 10, letterSpacing: .4, fontWeight: FontWeight.w800)));
  }
  String time(dynamic value) {
    if (value == null) return 'Never';
    final d = DateTime.tryParse(value.toString())?.toUtc().add(const Duration(hours: 8));
    if (d == null) return 'Unknown time';
    String p(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${p(d.month)}-${p(d.day)} ${p(d.hour)}:${p(d.minute)}:${p(d.second)} PHT';
  }

  Widget endpointScreen() {
    final up = endpoints.where((e) => e['status'] == 'UP').length;
    final active = incidents.where((i) => i['state'] != 'RECOVERED').length;
    final checked = (report['endpoints'] as List? ?? []).fold<int>(0, (sum, e) => sum + (e['total_checks'] as int));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      heading('Endpoint overview', 'Know what is responding, what needs attention, and what recovered.', actions: [FilledButton.icon(onPressed: !operator || busy ? null : () => navigate('register'), icon: const Icon(Icons.add, size: 18), label: const Text('Register endpoint'))]),
      LayoutBuilder(builder: (context, size) {
        final n = size.maxWidth > 750 ? 4 : 2;
        final width = (size.maxWidth - (n - 1) * 12) / n;
        return Wrap(spacing: 12, runSpacing: 12, children: [stat('REGISTERED', '${endpoints.length}', Icons.dns_outlined, width), stat('HEALTHY', '$up', Icons.check_circle_outline, width), stat('ACTIVE INCIDENTS', '$active', Icons.warning_amber_rounded, width), stat('COMPLETED CHECKS', '$checked', Icons.timeline, width)]);
      }), const SizedBox(height: 24),
      panel(Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: 16, runSpacing: 15, children: [
        Wrap(spacing: 9, runSpacing: 7, crossAxisAlignment: WrapCrossAlignment.center, children: [Container(width: 8, height: 8, decoration: BoxDecoration(color: scheduler['enabled'] == true ? accent : muted, shape: BoxShape.circle)), Text(scheduler['enabled'] == true ? 'Scheduler running' : 'Scheduler paused', style: const TextStyle(fontWeight: FontWeight.w700)), Text('${scheduler['active_count'] ?? 0}/2 active', style: const TextStyle(color: muted, fontSize: 12))]),
        Wrap(spacing: 8, runSpacing: 8, children: [OutlinedButton.icon(onPressed: !operator || busy ? null : () => unawaited(mutate('/scheduler/${scheduler['enabled'] == true ? 'stop' : 'start'}', 'Scheduler state updated.')), icon: Icon(scheduler['enabled'] == true ? Icons.pause : Icons.play_arrow, size: 17), label: Text(scheduler['enabled'] == true ? 'Stop scheduler' : 'Start scheduler')),
          OutlinedButton.icon(onPressed: !operator || busy || endpoints.isEmpty ? null : () => unawaited(mutate('/checks/run-all', 'Run-all admission processed.', after: (data) {
            final rows = data['outcomes'] as List;
            final accepted = rows.where((r) => r['outcome'] == 'accepted').length;
            if (mounted) unawaited(showDialog<void>(context: context, builder: (context) => AlertDialog(title: const Text('Run-all admission'), content: Text('$accepted checks accepted. ${rows.length - accepted} busy or capacity-blocked endpoints were not queued. Run them again after a slot becomes free.'), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))])));
          })), icon: const Icon(Icons.play_circle_outline, size: 17), label: const Text('Run all checks'))]),
      ])), const SizedBox(height: 20),
      if (endpoints.isEmpty && !loading) empty('No endpoints registered', 'Add a fictional service to start observing its health.', action: FilledButton(onPressed: !operator ? null : () => navigate('register'), child: const Text('Register endpoint'))),
      ...endpoints.map((e) => Padding(padding: const EdgeInsets.only(bottom: 12), child: endpointCard(Map<String, dynamic>.from(e as Map)))),
      const SizedBox(height: 8), const Text('Each run uses at most 3 attempts. Scheduled checks honor each endpoint’s interval. Status reflects the last completed observation.', style: TextStyle(color: muted, fontSize: 12, height: 1.6)),
    ]);
  }
  Widget stat(String title, String value, IconData icon, double width) => SizedBox(width: width, child: panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Icon(icon, size: 18, color: accent), const Spacer()]), const SizedBox(height: 15), Text(value, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: ink)), const SizedBox(height: 7), Text(title, style: const TextStyle(fontSize: 9, color: muted, letterSpacing: .8, fontWeight: FontWeight.w700))])));
  Widget endpointCard(Map<String, dynamic> e) => panel(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: 16, runSpacing: 15, children: [
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.public, color: accent, size: 19), const SizedBox(width: 9), Text(e['name'] as String, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17))]), const SizedBox(height: 8), SizedBox(width: MediaQuery.sizeOf(context).width < 600 ? 270 : 370, child: Text(e['url'] as String, style: const TextStyle(color: muted, fontSize: 11), overflow: TextOverflow.ellipsis))]),
      Wrap(spacing: 7, runSpacing: 6, children: [pill(e['status'] as String), if (e['checking'] == true) pill('CHECKING')]),
    ]), const SizedBox(height: 17), const Divider(height: 1, color: border), const SizedBox(height: 13),
    Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, runSpacing: 12, spacing: 16, children: [
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${behaviorNames[e['demo_behavior']]}  ·  ${e['interval_seconds']}s interval', style: const TextStyle(fontSize: 11, color: muted)), const SizedBox(height: 5), Text('Last completed: ${time(e['last_completed_at'])}', style: const TextStyle(fontSize: 11, color: muted))]),
      Wrap(spacing: 8, runSpacing: 8, children: [TextButton(onPressed: () => navigate('detail', id: e['id'] as int), child: const Text('View results')), OutlinedButton.icon(onPressed: !operator || busy || e['checking'] == true ? null : () => unawaited(runCheck(e['id'] as int)), icon: const Icon(Icons.play_arrow, size: 16), label: const Text('Run check'))]),
    ]),
  ]));

  Widget registrationScreen() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    heading('Register endpoint', 'Use a fictional HTTPS service label. Checks run against the controlled local sandbox.'),
    Align(alignment: Alignment.topLeft, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 670), child: panel(Form(key: formKey, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextFormField(controller: name, focusNode: nameFocus, decoration: InputDecoration(labelText: 'Name', hintText: 'Library Demo', errorText: fieldErrors['name']?.toString()), validator: validateName, textInputAction: TextInputAction.next), const SizedBox(height: 20),
      TextFormField(controller: url, focusNode: urlFocus, decoration: InputDecoration(labelText: 'Health URL', hintText: 'https://api.sandbox.example/service/health', errorText: fieldErrors['url']?.toString()), validator: validateUrl, keyboardType: TextInputType.url, textInputAction: TextInputAction.next), const SizedBox(height: 20),
      TextFormField(controller: interval, focusNode: intervalFocus, decoration: InputDecoration(labelText: 'Check interval (seconds)', helperText: 'Whole seconds from 10 to 3600.', errorText: fieldErrors['interval_seconds']?.toString()), validator: validateInterval, keyboardType: TextInputType.number), const SizedBox(height: 20),
      DropdownButtonFormField<String>(initialValue: behavior, isExpanded: true, decoration: const InputDecoration(labelText: 'Demo behavior'), items: behaviorNames.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis))).toList(), onChanged: busy ? null : (v) => setState(() => behavior = v!)),
      const SizedBox(height: 23), const Text('The server repeats validation and rejects duplicate URLs. A new endpoint starts UNKNOWN until a check completes.', style: TextStyle(color: muted, fontSize: 12, height: 1.6)), const SizedBox(height: 24),
      Wrap(spacing: 12, runSpacing: 10, children: [FilledButton(onPressed: !operator || busy ? null : () => unawaited(register()), child: const Text('Register endpoint')), TextButton(onPressed: busy ? null : () => navigate('endpoints'), child: const Text('Cancel'))]),
    ]))))),
  ]);

  Widget detailScreen() {
    if (detail['id'] != selectedId) return loading ? const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())) : empty('Endpoint not loaded', 'Refresh the page or return to the endpoint list.');
    final e = detail;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () => navigate('endpoints'), icon: const Icon(Icons.arrow_back, size: 16), label: const Text('All endpoints'))), const SizedBox(height: 8),
      heading(e['name'] as String, e['url'] as String, actions: [OutlinedButton(onPressed: !operator || busy || e['demo_behavior'] == 'stable' ? null : () => unawaited(mutate('/endpoints/$selectedId/demo-behavior', 'Future checks now use healthy responses. Run a check to verify recovery.', method: 'PATCH', body: {'demo_behavior': 'stable'})), child: const Text('Simulate fix')), FilledButton.icon(onPressed: !operator || busy || e['checking'] == true ? null : () => unawaited(runCheck(selectedId!)), icon: const Icon(Icons.play_arrow), label: const Text('Run check'))]),
      panel(Wrap(spacing: 22, runSpacing: 16, crossAxisAlignment: WrapCrossAlignment.center, children: [pill(e['status'] as String), if (e['checking'] == true) pill('CHECKING'), Text('${e['interval_seconds']}s interval', style: const TextStyle(color: muted)), Text(behaviorNames[e['demo_behavior']]!, style: const TextStyle(color: muted)), if (e['active_incident_id'] != null) TextButton(onPressed: () => navigate('incidents'), child: Text('Active incident #${e['active_incident_id']}'))])), const SizedBox(height: 23),
      const Text('Recent check runs', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700)), const SizedBox(height: 13),
      if (runs.isEmpty && !loading) empty('No checks yet', 'Run a check to see attempts and the verified result.'),
      ...runs.values.map((r) => Padding(padding: const EdgeInsets.only(bottom: 13), child: runCard(r))), const SizedBox(height: 12),
      const Text('Completed results', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700)), const SizedBox(height: 12),
      if (results.isEmpty) const Text('No completed results. Interrupted runs are excluded from uptime.', style: TextStyle(color: muted)),
      ...results.take(10).map((r) => Padding(padding: const EdgeInsets.only(bottom: 8), child: panel(Wrap(spacing: 18, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [pill(r['ok'] == true ? 'pass' : 'fail'), Text('Run #${r['check_id']} · ${r['attempt_count']} attempt(s)'), Text(time(r['completed_at']), style: const TextStyle(color: muted, fontSize: 11))])))),
    ]);
  }
  Widget runCard(Map<String, dynamic> r) => panel(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Wrap(alignment: WrapAlignment.spaceBetween, runSpacing: 10, children: [Text('Run #${r['id']} · ${r['trigger']}', style: const TextStyle(fontWeight: FontWeight.w700)), pill(r['state'] as String)]), const SizedBox(height: 10),
    SelectableText('Correlation: ${r['correlation_id']}', style: const TextStyle(fontSize: 10, color: muted)), const SizedBox(height: 10),
    if (r['state'] == 'INTERRUPTED') const Padding(padding: EdgeInsets.only(bottom: 12), child: Text('Interrupted — current health needs a new completed check. No result was invented.', style: TextStyle(color: Color(0xFF8A5A13)))),
    ...(r['attempts'] as List).map((a) => Padding(padding: const EdgeInsets.symmetric(vertical: 7), child: Wrap(spacing: 14, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [Icon(a['status_code'] != null && a['status_code'] >= 200 && a['status_code'] < 300 ? Icons.check_circle_outline : Icons.error_outline, color: a['status_code'] == 200 ? accent : const Color(0xFFAC4A3F), size: 18), Text('Attempt ${a['ordinal']}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)), Text(a['status_code'] == null ? '${a['error_category']}' : 'HTTP ${a['status_code']}', style: const TextStyle(fontSize: 12)), Text('${a['latency_ms']} ms', style: const TextStyle(color: muted, fontSize: 11))]))),
    if (r['state'] == 'RUNNING') const Padding(padding: EdgeInsets.only(top: 10), child: Text('Checking… temporary failures retry after 700 ms, up to 3 total attempts.', style: TextStyle(color: muted, fontSize: 12))),
    if (r['result'] != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(r['result']['ok'] == true ? 'Verified healthy · one passed completed check' : 'Check failed · human action required', style: TextStyle(fontWeight: FontWeight.w600, color: r['result']['ok'] == true ? accent : const Color(0xFFA12D2D)))),
    Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: () { logFilter.text = r['correlation_id'] as String; navigate('logs'); }, child: const Text('View correlated logs'))),
  ]));

  Widget incidentScreen() {
    final visible = incidents.where((i) => !activeOnly || i['state'] != 'RECOVERED').toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      heading('Incidents', 'Acknowledge responsibility. Repair the cause. Let a passing check verify recovery.'),
      SwitchListTile.adaptive(contentPadding: EdgeInsets.zero, title: const Text('Show active incidents only', style: TextStyle(fontSize: 13)), value: activeOnly, onChanged: (v) => setState(() => activeOnly = v)), const SizedBox(height: 12),
      if (visible.isEmpty) empty('No incidents in this view', 'Failed completed checks open incidents. A transient run that passes does not.'),
      ...visible.map((i) {
        final ep = endpoints.where((e) => e['id'] == i['endpoint_id']).firstOrNull;
        return Padding(padding: const EdgeInsets.only(bottom: 13), child: panel(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(alignment: WrapAlignment.spaceBetween, spacing: 12, runSpacing: 10, children: [Text('#${i['id']} · ${ep?['name'] ?? 'Endpoint ${i['endpoint_id']}'}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)), pill(i['state'] as String)]), const SizedBox(height: 12), Text(i['reason'] as String, style: const TextStyle(color: muted, height: 1.5)), const SizedBox(height: 12),
          Text('Opened ${time(i['opened_at'])}', style: const TextStyle(color: muted, fontSize: 11)),
          if (i['acknowledged_at'] != null) Text('Acknowledged by ${i['acknowledged_by']} · ${time(i['acknowledged_at'])}', style: const TextStyle(color: muted, fontSize: 11)),
          if (i['recovered_at'] != null) Text('Verified recovery · ${time(i['recovered_at'])} · run #${i['recovery_check_id']}', style: const TextStyle(color: accent, fontSize: 11)), const SizedBox(height: 12),
          Wrap(spacing: 10, children: [if (i['state'] == 'OPEN') OutlinedButton(onPressed: !operator || busy ? null : () => unawaited(mutate('/incidents/${i['id']}/acknowledge', 'Responsibility acknowledged. A passing check is still required for recovery.')), child: const Text('Acknowledge')), TextButton(onPressed: () => navigate('detail', id: i['endpoint_id'] as int), child: const Text('View endpoint'))]),
        ])));
      }), const SizedBox(height: 23), const Text('In-app demo notifications', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700)), const SizedBox(height: 8), const Text('Saved support notices in this dashboard. No email or SMS is sent.', style: TextStyle(color: muted, fontSize: 12)), const SizedBox(height: 13),
      if (notices.isEmpty) const Text('No support notices yet.', style: TextStyle(color: muted)),
      ...notices.take(12).map((n) => Padding(padding: const EdgeInsets.only(bottom: 8), child: panel(Wrap(spacing: 12, runSpacing: 8, children: [Icon(n['event'] == 'recovered' ? Icons.task_alt : Icons.notifications_outlined, color: accent, size: 18), Text('Incident #${n['incident_id']} ${n['event']} · support', style: const TextStyle(fontSize: 12)), Text(time(n['created_at']), style: const TextStyle(color: muted, fontSize: 11))])))),
    ]);
  }
  Widget reportScreen() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    heading('Uptime report', 'Passed completed checks ÷ all completed checks. A sample ratio across this dataset, not elapsed availability.'),
    panel(const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.info_outline, color: accent, size: 19), SizedBox(width: 12), Expanded(child: Text('Each check counts once, even when it needed retries. In-progress and interrupted runs are excluded. Earlier failures stay in the report.', style: TextStyle(color: muted, fontSize: 12, height: 1.6)))])), const SizedBox(height: 20),
    if ((report['endpoints'] as List? ?? []).isEmpty) empty('No report data', 'Register an endpoint and run a check.'),
    ...(report['endpoints'] as List? ?? []).map((r) => Padding(padding: const EdgeInsets.only(bottom: 14), child: panel(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(alignment: WrapAlignment.spaceBetween, spacing: 15, runSpacing: 10, children: [Text(r['name'] as String, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)), Text(r['uptime_percent'] == null ? 'No data' : '${(r['uptime_percent'] as num).toStringAsFixed(2)}%', style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800, color: accent))]), const SizedBox(height: 18),
      LinearProgressIndicator(value: r['uptime_percent'] == null ? 0 : (r['uptime_percent'] as num) / 100, minHeight: 8, borderRadius: BorderRadius.circular(4), backgroundColor: const Color(0xFFE7EDF1), semanticsLabel: r['uptime_percent'] == null ? 'No data' : '${r['uptime_percent']} percent check success'), const SizedBox(height: 15),
      Wrap(spacing: 24, runSpacing: 8, children: [Text('${r['total_checks']} completed', style: const TextStyle(color: muted, fontSize: 12)), Text('${r['passed_checks']} passed', style: const TextStyle(color: accent, fontSize: 12)), Text('${r['failed_checks']} failed', style: const TextStyle(color: Color(0xFFA12D2D), fontSize: 12))]),
    ])))),
    const SizedBox(height: 10), Text('Dataset since ${time(report['dataset_start'])}', style: const TextStyle(fontSize: 11, color: muted)),
  ]);
  Widget logsScreen() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    heading('Structured logs', 'One JSON line per event. Correlation IDs connect the request, attempts, and outcome.', actions: [OutlinedButton.icon(onPressed: logs.isEmpty ? null : () => unawaited(Clipboard.setData(ClipboardData(text: logs.map(jsonEncode).join('\n')))), icon: const Icon(Icons.copy, size: 16), label: const Text('Copy logs'))]),
    Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [SizedBox(width: MediaQuery.sizeOf(context).width < 600 ? 280 : 400, child: TextField(controller: logFilter, decoration: const InputDecoration(labelText: 'Correlation ID (optional)'), onSubmitted: (_) => unawaited(load()))), OutlinedButton(onPressed: () => unawaited(load()), child: const Text('Apply filter')), TextButton(onPressed: () { logFilter.clear(); unawaited(load()); }, child: const Text('Show all'))]), const SizedBox(height: 18),
    if (logs.isEmpty) empty('No log events in this view', 'Run a check or remove the correlation filter.'),
    if (logs.isNotEmpty) panel(SelectableText(logs.map(jsonEncode).join('\n\n'), style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: ink, height: 1.65))),
  ]);
  Widget guideScreen() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    heading('Evidence guide', 'Three controlled demonstrations for Module 13. Record actual results and keep every failure.'),
    ...[
      ('01', 'Successful execution', 'Run Library API. Expect one HTTP 200 attempt, one passed check, UP, and no new incident.'),
      ('02', 'Transient failure recovered', 'Run Enrollment API. Expect 503, 503, then 200; two bounded retry waits and one passed completed check.'),
      ('03', 'Persistent failure and human recovery', 'Run Payments sandbox. Expect three failed attempts and one incident. Acknowledge, simulate a fix, then run a new check to verify recovery.'),
    ].map((g) => Padding(padding: const EdgeInsets.only(bottom: 14), child: panel(Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(g.$1, style: const TextStyle(color: accent, fontSize: 24, fontWeight: FontWeight.w800)), const SizedBox(width: 22), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(g.$2, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)), const SizedBox(height: 9), Text(g.$3, style: const TextStyle(color: muted, height: 1.6, fontSize: 13))]))])))),
    const SizedBox(height: 9), panel(const Text('Preserve the request, expected result, actual result, timestamp, correlated logs, and saved state. Invalid input, unauthorized action, transient failure, and persistent failure provide the four minimum adverse cases. A repair selection alone does not verify recovery.', style: TextStyle(color: muted, height: 1.7, fontSize: 13))),
  ]);
}
