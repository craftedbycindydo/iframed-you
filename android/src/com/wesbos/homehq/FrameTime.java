package com.wesbos.homehq;

import java.text.ParseException;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;
import java.util.TimeZone;

final class FrameTime {
  interface Clock {
    long now();
  }

  interface Uptime {
    long millis();
  }

  static final long DRIFT = 60000L;
  private static final TimeZone UTC = TimeZone.getTimeZone("UTC");

  private FrameTime() {}

  private static SimpleDateFormat format(String pattern, TimeZone zone) {
    SimpleDateFormat format = new SimpleDateFormat(pattern, Locale.ROOT);
    format.setTimeZone(zone);
    format.setLenient(false);
    return format;
  }

  static long anchored(long shown, long actual) {
    return Math.abs(shown - actual) > DRIFT ? actual : shown;
  }

  static String iso(long millis) {
    return format("yyyy-MM-dd'T'HH:mm:ss'Z'", UTC).format(new Date(millis));
  }

  static long instant(Object iso) {
    if (!(iso instanceof String)) return 0;
    try {
      return format("yyyy-MM-dd'T'HH:mm:ss'Z'", UTC).parse((String) iso).getTime();
    } catch (ParseException unreadable) {
      return 0;
    }
  }

  static String day(long millis, TimeZone zone) {
    return format("yyyy-MM-dd", zone).format(new Date(millis));
  }

  static boolean validDay(Object value) {
    if (!(value instanceof String) || !((String) value).matches("\\d{4}-\\d{2}-\\d{2}")) return false;
    try {
      format("yyyy-MM-dd", UTC).parse((String) value);
      return true;
    } catch (ParseException invalid) {
      return false;
    }
  }

  static String shift(String day, int days) {
    try {
      long start = format("yyyy-MM-dd", UTC).parse(day).getTime();
      return day(start + days * 86400000L, UTC);
    } catch (ParseException invalid) {
      throw new IllegalArgumentException(day);
    }
  }
}
