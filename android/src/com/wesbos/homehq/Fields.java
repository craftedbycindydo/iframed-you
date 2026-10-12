package com.wesbos.homehq;

import java.util.Map;

final class Fields {
  private Fields() {}

  static String text(Map<String, Object> fields, String key, int minimum, int maximum) throws ApiException {
    Object value = fields.get(key);
    if (!(value instanceof String)) throw ApiException.badRequest(key + " must be text");
    String trimmed = ((String) value).trim();
    int length = trimmed.codePointCount(0, trimmed.length());
    if (length < minimum || length > maximum) {
      throw ApiException.badRequest(key + " must be " + minimum + " to " + maximum + " characters");
    }
    for (int i = 0; i < trimmed.length(); i++) {
      if (Character.isISOControl(trimmed.charAt(i))) throw ApiException.badRequest(key + " has control characters");
    }
    return trimmed;
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
