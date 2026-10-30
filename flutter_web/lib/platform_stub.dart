import 'package:http/http.dart' as http;

http.Client createClient() => http.Client();
String defaultBaseUrl() => 'http://localhost:3000/api/v1';
