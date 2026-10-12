package com.wesbos.homehq;

import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;

final class Digests {
  private static final char[] HEX = "0123456789abcdef".toCharArray();

  private Digests() {}

  static String hex(byte[] bytes) {
    char[] text = new char[bytes.length * 2];
    for (int i = 0; i < bytes.length; i++) {
      text[i * 2] = HEX[(bytes[i] >> 4) & 15];
      text[i * 2 + 1] = HEX[bytes[i] & 15];
    }
    return new String(text);
  }

  static byte[] bytes(Object hex) {
    if (!(hex instanceof String) || !((String) hex).matches("([0-9a-f]{2})*")) return null;
    String text = (String) hex;
    byte[] bytes = new byte[text.length() / 2];
    for (int i = 0; i < bytes.length; i++) bytes[i] = (byte) Integer.parseInt(text.substring(i * 2, i * 2 + 2), 16);
    return bytes;
  }

  static byte[] digest(byte[] data) {
    try {
      return MessageDigest.getInstance("SHA-256").digest(data);
    } catch (NoSuchAlgorithmException missing) {
      throw new IllegalStateException(missing);
    }
  }

  static String sha256(byte[] data) {
    return hex(digest(data));
  }

  static boolean same(String left, String right) {
    if (left.length() != right.length()) return false;
    int difference = 0;
    for (int i = 0; i < left.length(); i++) difference |= left.charAt(i) ^ right.charAt(i);
    return difference == 0;
  }
}
