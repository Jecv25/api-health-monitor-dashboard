String? validateName(String? value) {
  final name = (value ?? '').trim();
  if (name.runes.length < 3 || name.runes.length > 40 || RegExp(r'[\x00-\x1f\x7f-\x9f]').hasMatch(name)) {
    return 'Enter 3–40 characters without control characters.';
  }
  return null;
}

String? validateUrl(String? value) {
  final raw = (value ?? '').trim();
  final uri = Uri.tryParse(raw);
  if (uri == null || raw.length > 200 || uri.scheme != 'https' || uri.host.toLowerCase() != 'api.sandbox.example' ||
      uri.userInfo.isNotEmpty || (uri.hasPort && uri.port != 443) || uri.hasQuery || uri.hasFragment ||
      RegExp(r'[%?#\\]').hasMatch(raw) || RegExp(r'(^|/)\.{1,2}(/|$)').hasMatch(raw) ||
      !RegExp(r'^/[a-z][a-z0-9-]{0,39}/health$').hasMatch(uri.path)) {
    return 'Use https://api.sandbox.example/service/health.';
  }
  return null;
}

String? validateInterval(String? value) {
  final raw = (value ?? '').trim();
  final number = int.tryParse(raw);
  if (!RegExp(r'^\d+$').hasMatch(raw) || number == null || number < 10 || number > 3600) return 'Enter whole seconds from 10 to 3600.';
  return null;
}
