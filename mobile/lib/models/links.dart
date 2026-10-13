/// The first of [preferred] and [fallback] that is an actual link.
String? preferredUrl(String? preferred, String? fallback) {
  for (final url in [preferred, fallback]) {
    if (url != null && url.trim().isNotEmpty) return url.trim();
  }
  return null;
}
