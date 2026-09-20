class DirectiveSanitizer {
  /// B4: Directive Sanitization
  /// Strips control characters and newlines, caps length at 300 characters,
  /// and wraps in an unambiguous delimiter block rather than quotes.
  static String sanitize(String rawText) {
    if (rawText.isEmpty) return '';

    // Strip control characters (\x00-\x1F, \x7F) and carriage return / line feed
    var clean = rawText.replaceAll(RegExp(r'[\x00-\x1F\x7F\r\n]+'), ' ').trim();

    // Prevent prompt injection attempts from escaping delimiters
    clean = clean.replaceAll('===', '');

    // Cap length at 300 characters
    if (clean.length > 300) {
      clean = clean.substring(0, 300).trim();
    }

    return clean;
  }

  /// Builds the delimited prompt block
  static String buildDelimitedBlock(String sanitizedText) {
    return '=== BEGIN EXECUTIVE DIRECTIVE ===\n$sanitizedText\n=== END EXECUTIVE DIRECTIVE ===';
  }

  /// Wraps sanitized directive into the base prompt
  static String injectIntoPrompt(String basePrompt, String rawDirective) {
    final clean = sanitize(rawDirective);
    final block = buildDelimitedBlock(clean);
    return '$basePrompt\n\n$block\nSpeak this directive to the caller immediately.';
  }
}
