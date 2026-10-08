/// Helpers for the JSON-shaped values that cross the platform channel.
library;

/// Copies [value] into plain JSON collections.
///
/// The standard codec hands back `Map<Object?, Object?>`. This converts every
/// map to `Map<String, Object?>` and every list to `List<Object?>`, so the
/// result is safe to compare, hash, and cast.
Object? normalizeJson(Object? value) {
  if (value is Map<Object?, Object?>) {
    return <String, Object?>{
      for (final entry in value.entries)
        entry.key.toString(): normalizeJson(entry.value),
    };
  }
  if (value is List<Object?>) {
    return <Object?>[for (final item in value) normalizeJson(item)];
  }
  return value;
}

/// Structural equality for values produced by [normalizeJson].
bool jsonEquals(Object? a, Object? b) {
  if (a is Map<String, Object?> && b is Map<String, Object?>) {
    if (a.length != b.length) {
      return false;
    }
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key) || !jsonEquals(entry.value, b[entry.key])) {
        return false;
      }
    }
    return true;
  }
  if (a is List<Object?> && b is List<Object?>) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (!jsonEquals(a[i], b[i])) {
        return false;
      }
    }
    return true;
  }
  return a == b;
}

/// Hash code that agrees with [jsonEquals].
int jsonHash(Object? value) {
  if (value is Map<String, Object?>) {
    var hash = 0;
    for (final entry in value.entries) {
      hash += Object.hash(entry.key, jsonHash(entry.value));
    }
    return hash;
  }
  if (value is List<Object?>) {
    return Object.hashAll(value.map(jsonHash));
  }
  return value.hashCode;
}
