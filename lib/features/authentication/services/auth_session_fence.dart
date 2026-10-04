import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Reject obsolete auth responses before GoTrue can install their sessions.
/// Owns no token store; the snapshot is only an in-flight SDK Session reference.
class AuthSessionFence extends http.BaseClient {
  AuthSessionFence({required String supabaseUrl, http.Client? inner})
      : _origin = Uri.parse(supabaseUrl),
        _inner = inner ?? http.Client();

  final Uri _origin;
  final http.Client _inner;
  Session? Function()? currentSession;
  int _intent = 0;
  bool _closed = false;
  DateTime? retryNotBefore;

  static final _clients = Expando<AuthSessionFence>();
  static AuthSessionFence? forClient(SupabaseClient client) => _clients[client];

  void attach(SupabaseClient client) {
    currentSession = () => client.auth.currentSession;
    _clients[client] = this;
  }

  /// Called synchronously at explicit login/logout intent, before any await.
  void invalidate() => _intent++;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final uri = request.url;
    final auth = uri.origin == _origin.origin &&
        uri.path.startsWith('${_origin.path}/auth/v1/'.replaceAll('//', '/'));
    if (!auth) return _inner.send(request);
    final path = uri.path.split('/auth/v1/').last;
    final refresh =
        path == 'token' && uri.queryParameters['grant_type'] == 'refresh_token';
    final changesIdentity = request.method == 'POST' &&
        ((path == 'token' && !refresh) ||
            path == 'signup' ||
            path == 'verify' ||
            path == 'logout');
    if (changesIdentity) invalidate();
    final intent = _intent;
    final owner = currentSession?.call();
    // Buffer only Auth responses, never storage/business streams. Do not pass
    // the old session body to GoTrue, including on error responses.
    final response = await http.Response.fromStream(await _inner.send(request));
    if (_closed ||
        intent != _intent ||
        (path != 'logout' && !identical(owner, currentSession?.call()))) {
      return http.StreamedResponse(
          Stream.value(utf8.encode(
              '{"code":"mfa_session_changed","message":"Authentication context changed"}')),
          409,
          headers: {
            'content-type': 'application/json',
            'x-supabase-api-version': '2024-01-01'
          });
    }
    if (response.statusCode == 429) {
      retryNotBefore =
          mfaRetryDeadline(response.headers['retry-after'], DateTime.now());
    }
    return http.StreamedResponse(
        Stream.value(response.bodyBytes), response.statusCode,
        headers: response.headers,
        request: request,
        reasonPhrase: response.reasonPhrase);
  }

  @override
  void close() {
    _closed = true;
    invalidate();
    currentSession = null;
    _inner.close();
  }
}

/// HTTP Retry-After allows either delta-seconds or an RFC 7231 HTTP date.
DateTime? mfaRetryDeadline(String? header, DateTime now) {
  if (header == null) return null;
  final seconds = int.tryParse(header);
  if (seconds != null && seconds >= 0) {
    return now.add(Duration(seconds: seconds));
  }
  try {
    return DateFormat("EEE, dd MMM yyyy HH:mm:ss 'GMT'", 'en_US')
        .parseStrict(header, true);
  } catch (_) {
    return null;
  }
}
