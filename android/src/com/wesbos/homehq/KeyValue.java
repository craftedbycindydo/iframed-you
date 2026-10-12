package com.wesbos.homehq;

interface KeyValue {
  String get(String key);

  boolean put(String key, String value);
}
