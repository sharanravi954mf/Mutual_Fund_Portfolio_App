class NsePendingStorage {
  NsePendingStorage(this.userId);
  final String userId;
  static final Map<String, String> _values = {};
  String? read() => _values[userId];
  void write(String value) => _values[userId] = value;
  void clear() => _values.remove(userId);
}
