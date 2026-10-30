import 'package:flutter/material.dart';

import 'api.dart';
import 'widgets.dart';

Future<bool> connectOperator(BuildContext context, ApiClient api) async {
  if (api.operatorKey.isNotEmpty) return true;
  return await showDialog<bool>(
        context: context,
        builder: (_) => _OperatorDialog(api: api),
      ) ==
      true;
}

class _OperatorDialog extends StatefulWidget {
  final ApiClient api;
  const _OperatorDialog({required this.api});
  @override
  State<_OperatorDialog> createState() => _OperatorDialogState();
}

class _OperatorDialogState extends State<_OperatorDialog> {
  final keyInput = TextEditingController();
  String? error;
  bool busy = false;
  @override
  void dispose() {
    keyInput.dispose();
    super.dispose();
  }

  Future<void> connect() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.api.verifyKey(keyInput.text.trim());
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted)
        setState(() {
          busy = false;
          error = e.toString();
        });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Connect operator'),
    content: SizedBox(
      width: 400,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Enter the local operator key to register services, run checks, and acknowledge incidents.',
            style: TextStyle(color: muted, height: 1.6),
          ),
          const SizedBox(height: 20),
          TextField(
            key: const Key('operator-key'),
            controller: keyInput,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Operator key'),
            onSubmitted: (_) => busy ? null : connect(),
          ),
          const SizedBox(height: 12),
          const Text(
            'The key stays in memory for this session.',
            style: TextStyle(fontSize: 11, color: muted),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(error!, style: const TextStyle(color: Colors.red)),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: busy ? null : connect,
        child: Text(busy ? 'Connecting…' : 'Connect'),
      ),
    ],
  );
}

class RegisterDialog extends StatefulWidget {
  final ApiClient api;
  final List<String> origins;
  const RegisterDialog({super.key, required this.api, required this.origins});
  @override
  State<RegisterDialog> createState() => _RegisterDialogState();
}

class _RegisterDialogState extends State<RegisterDialog> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController(), url = TextEditingController();
  int interval = 60, timeout = 3;
  bool saving = false;
  String? error;
  @override
  void dispose() {
    name.dispose();
    url.dispose();
    super.dispose();
  }

  String? urlError(String? raw) {
    final value = raw?.trim() ?? '';
    final parsed = Uri.tryParse(value);
    if (value.length > 512 ||
        parsed == null ||
        !parsed.hasAuthority ||
        !['http', 'https'].contains(parsed.scheme) ||
        parsed.userInfo.isNotEmpty ||
        parsed.hasQuery ||
        parsed.hasFragment ||
        RegExp(r'\s|\\').hasMatch(value)) {
      return 'Use HTTP(S) without credentials, query strings or fragments.';
    }
    if (!widget.origins.contains(
      '${parsed.scheme}://${parsed.authority.toLowerCase()}',
    )) {
      return 'Choose an approved service origin.';
    }
    return null;
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.api.request(
        'POST',
        '/api/endpoints',
        protected: true,
        body: {
          'name': name.text.trim(),
          'url': url.text.trim(),
          'interval_seconds': interval,
          'timeout_seconds': timeout,
        },
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted)
        setState(() {
          saving = false;
          error = e.toString();
        });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Register a service'),
    content: SizedBox(
      width: 470,
      child: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Give an approved endpoint a name and a monitoring schedule.',
                style: TextStyle(color: muted, fontSize: 12, height: 1.5),
              ),
              const SizedBox(height: 23),
              TextFormField(
                key: const Key('service-name'),
                controller: name,
                decoration: const InputDecoration(
                  labelText: 'Service name',
                  hintText: 'Example API',
                ),
                maxLength: 80,
                validator: (v) =>
                    RegExp(r'^[A-Za-z0-9][A-Za-z0-9 ._-]{1,79}$')
                        .hasMatch(v?.trim() ?? '')
                    ? null
                    : 'Use 2–80 letters, numbers, spaces, dots, underscores or hyphens.',
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('service-url'),
                controller: url,
                decoration: const InputDecoration(
                  labelText: 'Health endpoint URL',
                  hintText: 'http://127.0.0.1:9001/health/healthy',
                ),
                validator: urlError,
              ),
              const SizedBox(height: 12),
              Text(
                'Approved origins: ${widget.origins.join(', ')}',
                style: const TextStyle(color: muted, fontSize: 10),
              ),
              const SizedBox(height: 22),
              Wrap(
                spacing: 14,
                runSpacing: 15,
                children: [
                  SizedBox(
                    width: 205,
                    child: DropdownButtonFormField<int>(
                      isExpanded: true,
                      initialValue: interval,
                      decoration: const InputDecoration(
                        labelText: 'Check interval',
                      ),
                      items: [15, 30, 60, 120, 300, 900, 3600]
                          .map(
                            (n) => DropdownMenuItem(
                              value: n,
                              child: Text(
                                n < 60 ? '$n seconds' : '${n ~/ 60} minute(s)',
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => interval = v ?? 60,
                    ),
                  ),
                  SizedBox(
                    width: 170,
                    child: DropdownButtonFormField<int>(
                      isExpanded: true,
                      initialValue: timeout,
                      decoration: const InputDecoration(
                        labelText: 'Attempt timeout',
                      ),
                      items: [1, 3, 5, 10]
                          .map(
                            (n) => DropdownMenuItem(
                              value: n,
                              child: Text('$n seconds'),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => timeout = v ?? 3,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Text(
                'Up to 3 attempts per check. Persistent failures are assigned to support.',
                style: TextStyle(fontSize: 11, color: muted, height: 1.6),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 15),
                  child: Text(
                    error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: saving ? null : save,
        child: Text(saving ? 'Registering…' : 'Register service'),
      ),
    ],
  );
}

class AcknowledgeDialog extends StatefulWidget {
  final ApiClient api;
  final int incidentId;
  const AcknowledgeDialog({
    super.key,
    required this.api,
    required this.incidentId,
  });
  @override
  State<AcknowledgeDialog> createState() => _AcknowledgeDialogState();
}

class _AcknowledgeDialogState extends State<AcknowledgeDialog> {
  final form = GlobalKey<FormState>();
  final alias = TextEditingController(text: 'support-demo');
  final note = TextEditingController(
    text: 'Investigating the controlled service.',
  );
  String? error;
  bool busy = false;
  @override
  void dispose() {
    alias.dispose();
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Acknowledge INC-${widget.incidentId}'),
    content: SizedBox(
      width: 400,
      child: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: alias,
                decoration: const InputDecoration(labelText: 'Support alias'),
                validator: (v) =>
                    RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.-]{1,39}$')
                        .hasMatch(v ?? '')
                    ? null
                    : 'Use a 2–40 character alias: letters, numbers, dots, underscores or hyphens.',
              ),
              const SizedBox(height: 15),
              TextFormField(
                controller: note,
                maxLength: 240,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Action note',
                  helperText:
                      'Use fictional aliases; keep secrets out of notes.',
                ),
              ),
              if (error != null)
                Text(error!, style: const TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: busy
            ? null
            : () async {
                if (!form.currentState!.validate()) return;
                setState(() => busy = true);
                try {
                  await widget.api.request(
                    'POST',
                    '/api/incidents/${widget.incidentId}/acknowledge',
                    protected: true,
                    body: {
                      'operator_alias': alias.text.trim(),
                      'note': note.text.trim(),
                    },
                  );
                  if (context.mounted) Navigator.pop(context, true);
                } catch (e) {
                  if (mounted)
                    setState(() {
                      busy = false;
                      error = e.toString();
                    });
                }
              },
        child: Text(busy ? 'Saving…' : 'Confirm acknowledgement'),
      ),
    ],
  );
}
