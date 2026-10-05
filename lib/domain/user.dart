/// A Bilibili user identifier, preserved as decimal text at protocol boundaries.
final class UserId {
  const UserId(this.value);
  final String value;
  bool get isValid => RegExp(r'^[1-9][0-9]*$').hasMatch(value);
  static UserId? tryParse(String? value) {
    if (value == null) return null;
    final id = UserId(value);
    return id.isValid ? id : null;
  }

  @override
  bool operator ==(Object other) => other is UserId && other.value == value;
  @override
  int get hashCode => value.hashCode;
  @override
  String toString() => value;
}
