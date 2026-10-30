import 'package:flutter/material.dart';

import 'api.dart';

const ink = Color(0xFF182C2B);
const muted = Color(0xFF6C7F7B);
const teal = Color(0xFF087F6D);
const line = Color(0xFFE3EAE7);
const canvas = Color(0xFFF4F7F5);

String prettyTime(dynamic raw) {
  if (raw == null) return 'No checks yet';
  final date = DateTime.tryParse(raw.toString())?.toLocal();
  if (date == null) return '—';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(date.month)}/${two(date.day)} ${two(date.hour)}:${two(date.minute)}:${two(date.second)}';
}

String percent(dynamic value) =>
    value == null ? '—' : '${(value as num).toStringAsFixed(1)}%';
String millis(dynamic value) =>
    value == null ? '—' : '${(value as num).toStringAsFixed(0)} ms';

class StatusPill extends StatelessWidget {
  final String status;
  const StatusPill(this.status, {super.key});
  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'up' || 'success' || 'recovered' || 'online' => teal,
      'down' || 'failed' || 'open' || 'offline' => const Color(0xFFC3473A),
      'recovering' ||
      'transient_recovered' ||
      'acknowledged' => const Color(0xFFA46A13),
      _ => muted,
    };
    final label = switch (status) {
      'up' => 'Healthy',
      'down' => 'Unavailable',
      'unknown' => 'Awaiting check',
      'transient_recovered' => 'Retry recovered',
      _ => status.replaceAll('_', ' '),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class Surface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const Surface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(22),
  });
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: padding,
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: line),
      borderRadius: BorderRadius.circular(16),
    ),
    child: child,
  );
}

class MetricCard extends StatelessWidget {
  final String label, value, detail;
  final IconData icon;
  final Color color;
  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.detail,
    required this.icon,
    this.color = teal,
  });
  @override
  Widget build(BuildContext context) => Surface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(color: muted, fontSize: 12),
              ),
            ),
            Icon(icon, color: color, size: 19),
          ],
        ),
        const SizedBox(height: 17),
        Text(
          value,
          style: const TextStyle(
            fontSize: 29,
            fontWeight: FontWeight.w700,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: 7),
        Text(detail, style: const TextStyle(fontSize: 11, color: muted)),
      ],
    ),
  );
}

class StatePanel extends StatelessWidget {
  final String title, message;
  final IconData icon;
  final Widget? action;
  const StatePanel({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.sensors_outlined,
    this.action,
  });
  @override
  Widget build(BuildContext context) => Surface(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 26),
      child: Column(
        children: [
          Icon(icon, size: 40, color: teal),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: muted, height: 1.6),
          ),
          if (action != null) ...[const SizedBox(height: 20), action!],
        ],
      ),
    ),
  );
}

class SampleBars extends StatelessWidget {
  final List<dynamic> samples;
  const SampleBars(this.samples, {super.key});
  @override
  Widget build(BuildContext context) => Semantics(
    label: '${samples.length} recent check results',
    child: Row(
      children: List.generate(24, (i) {
        final offset = 24 - samples.length;
        final sample = i >= offset ? samples[i - offset] : null;
        return Expanded(
          child: Container(
            height: 21,
            margin: const EdgeInsets.only(right: 3),
            decoration: BoxDecoration(
              color: sample == null
                  ? const Color(0xFFEAF0ED)
                  : sample == true
                  ? const Color(0xFF49B69A)
                  : const Color(0xFFE07B6D),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        );
      }),
    ),
  );
}

class RunTile extends StatelessWidget {
  final Json run;
  final bool showAttempts;
  const RunTile(this.run, {super.key, this.showAttempts = false});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 13),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            StatusPill(run['status'] ?? 'unknown'),
            Text(
              run['endpoint_name'] ?? prettyTime(run['started_at']),
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
            ),
            Text(
              '${run['attempt_count']} attempt(s) · ${millis(run['duration_ms'])} · ${run['source']}',
              style: const TextStyle(color: muted, fontSize: 11),
            ),
          ],
        ),
        if (showAttempts) ...[
          const SizedBox(height: 8),
          ...((run['attempts'] as List?) ?? []).map(
            (a) => Padding(
              padding: const EdgeInsets.only(left: 6, top: 5),
              child: Text(
                'Attempt ${a['number']}  ·  ${a['http_status'] ?? a['error_code']}  ·  ${millis(a['duration_ms'])}',
                style: const TextStyle(color: muted, fontSize: 12),
              ),
            ),
          ),
          const SizedBox(height: 7),
          SelectableText(
            'Run ${run['id']}',
            style: const TextStyle(color: muted, fontSize: 10),
          ),
        ],
      ],
    ),
  );
}
