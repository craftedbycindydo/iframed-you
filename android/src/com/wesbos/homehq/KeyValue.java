package com.wesbos.homehq;

interface KeyValue {
  String get(String key);

  void put(String key, String value);
}
