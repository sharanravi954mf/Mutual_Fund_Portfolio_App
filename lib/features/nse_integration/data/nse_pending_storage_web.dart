// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;

class NsePendingStorage {
  NsePendingStorage(this.userId);
  final String userId;
  String get _key => 'moneybowl.nse.pending.v1.$userId';
  String? read() {
    try {
      return html.window.sessionStorage[_key];
    } catch (_) {
      return null;
    }
  }

  void write(String value) {
    html.window.sessionStorage[_key] = value;
  }

  void clear() {
    try {
      html.window.sessionStorage.remove(_key);
    } catch (_) {}
  }
}
