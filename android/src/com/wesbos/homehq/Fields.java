package com.wesbos.homehq;

import java.util.Map;

final class Fields {
  private Fields() {}

  static String text(Map<String, Object> fields, String key, int minimum, int maximum) throws ApiException {
    Object value = fields.get(key);
    if (!(value instanceof String)) throw ApiException.badRequest(key + " must be text");
    String trimmed = trim((String) value);
    int length = trimmed.codePointCount(0, trimmed.length());
    if (length < minimum || length > maximum) {
      throw ApiException.badRequest(key + " must be " + minimum + " to " + maximum + " characters");
    }
    for (int i = 0; i < trimmed.length(); i++) {
      if (forbidden(trimmed, i)) throw ApiException.badRequest(key + " has characters that cannot be shown");
    }
    return trimmed;
  }

  private static boolean blank(char c) {
    return Character.isWhitespace(c) || Character.isSpaceChar(c) || c == 0xFEFF;
  }

  static String trim(String text) {
    int start = 0;
    int end = text.length();
    while (start < end && blank(text.charAt(start))) start++;
    while (end > start && blank(text.charAt(end - 1))) end--;
    return text.substring(start, end);
  }

  static boolean forbidden(String text, int index) {
    char c = text.charAt(index);
    boolean lonelyHigh = Character.isHighSurrogate(c) && (index + 1 >= text.length() || !Character.isLowSurrogate(text.charAt(index + 1)));
    boolean lonelyLow = Character.isLowSurrogate(c) && (index == 0 || !Character.isHighSurrogate(text.charAt(index - 1)));
    boolean directional = c >= 0x202A && c <= 0x202E || c >= 0x2066 && c <= 0x2069;
    return Character.isISOControl(c) || c == 0xFFFE || c == 0xFFFF || directional || lonelyHigh || lonelyLow;
  }

  static String tidy(String text, int maximum) {
    StringBuilder kept = new StringBuilder();
    for (int i = 0; i < text.length(); i++) if (!forbidden(text, i)) kept.append(text.charAt(i));
    String clean = kept.toString().trim();
    int length = clean.codePointCount(0, clean.length());
    return length <= maximum ? clean : clean.substring(0, clean.offsetByCodePoints(0, maximum));
  }

  static String color(Map<String, Object> fields, String key) throws ApiException {
    Object value = fields.get(key);
    if (!(value instanceof String) || !((String) value).matches("#[0-9a-fA-F]{6}")) {
      throw ApiException.badRequest(key + " must look like #RRGGBB");
    }
    return (String) value;
  }

  static long whole(Object value, String key, long minimum, long maximum) throws ApiException {
    boolean integral = value instanceof Long
        || value instanceof Double && (Double) value == Math.rint((Double) value);
    if (!integral) throw ApiException.badRequest(key + " must be a whole number");
    long number = ((Number) value).longValue();
    if (number < minimum || number > maximum) {
      throw ApiException.badRequest(key + " must be " + minimum + " to " + maximum);
    }
    return number;
  }

  static double decimal(Map<String, Object> fields, String key, double minimum, double maximum) throws ApiException {
    Object value = fields.get(key);
    if (!(value instanceof Number)) throw ApiException.badRequest(key + " must be a number");
    double number = ((Number) value).doubleValue();
    if (!(number >= minimum && number <= maximum)) {
      throw ApiException.badRequest(key + " is out of range");
    }
    return number;
  }

  static boolean flag(Map<String, Object> fields, String key) throws ApiException {
    Object value = fields.get(key);
    if (!(value instanceof Boolean)) throw ApiException.badRequest(key + " must be true or false");
    return (Boolean) value;
  }

  static String choice(Map<String, Object> fields, String key, String... allowed) throws ApiException {
    Object value = fields.get(key);
    for (String option : allowed) if (option.equals(value)) return option;
    throw ApiException.badRequest(key + " is not a supported value");
  }
}
