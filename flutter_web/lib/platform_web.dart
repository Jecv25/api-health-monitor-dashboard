import 'package:http/browser_client.dart';
import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

http.Client createClient() => BrowserClient()..withCredentials = true;
String defaultBaseUrl() => '${web.window.location.origin}/api/v1';
