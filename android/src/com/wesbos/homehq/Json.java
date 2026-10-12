package com.wesbos.homehq;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

final class Json {
  static final class Malformed extends Exception {
    Malformed(String message) {
      super(message);
    }
  }

  private static final int MAX_DEPTH = 16;
  static final int MAX_VALUES = 400000;
  private final String text;
  private int at;
  private int values;

  private Json(String text) {
    this.text = text;
  }

  static Object parse(String text) throws Malformed {
    if (text == null) throw new Malformed("No JSON");
    Json reader = new Json(text);
    Object value = reader.value(0);
    reader.skipSpace();
    if (reader.at != text.length()) throw new Malformed("Unexpected text after JSON");
    return value;
  }

  @SuppressWarnings("unchecked")
  static Map<String, Object> map(Object value) {
    return value instanceof Map ? (Map<String, Object>) value : null;
  }

  @SuppressWarnings("unchecked")
  static List<Object> list(Object value) {
    return value instanceof List ? (List<Object>) value : null;
  }

  static Map<String, Object> object(Object... pairs) {
    Map<String, Object> result = new LinkedHashMap<>();
    for (int i = 0; i < pairs.length; i += 2) result.put((String) pairs[i], pairs[i + 1]);
    return result;
  }

  static Object copy(Object value) {
    if (value instanceof Map) {
      Map<String, Object> result = new LinkedHashMap<>();
      for (Map.Entry<String, Object> entry : map(value).entrySet()) result.put(entry.getKey(), copy(entry.getValue()));
      return result;
    }
    if (value instanceof List) {
      List<Object> result = new ArrayList<>();
      for (Object item : list(value)) result.add(copy(item));
      return result;
    }
    return value;
  }

  static String scriptSafe(String script) {
    return script.replace(String.valueOf((char) 0x2028), "\\u2028").replace(String.valueOf((char) 0x2029), "\\u2029");
  }

  static String write(Object value) {
    StringBuilder out = new StringBuilder();
    write(value, out);
    return out.toString();
  }

  private static void write(Object value, StringBuilder out) {
    if (value instanceof Map) {
      out.append('{');
      boolean first = true;
      for (Map.Entry<String, Object> entry : map(value).entrySet()) {
        if (!first) out.append(',');
        first = false;
        quote(entry.getKey(), out);
        out.append(':');
        write(entry.getValue(), out);
      }
      out.append('}');
    } else if (value instanceof List) {
      out.append('[');
      boolean first = true;
      for (Object item : list(value)) {
        if (!first) out.append(',');
        first = false;
        write(item, out);
      }
      out.append(']');
    } else if (value instanceof String) {
      quote((String) value, out);
    } else if (value instanceof Double || value instanceof Float) {
      double number = ((Number) value).doubleValue();
      out.append(Double.isNaN(number) || Double.isInfinite(number) ? "null" : Double.toString(number));
    } else if (value instanceof Number || value instanceof Boolean) {
      out.append(value);
    } else {
      out.append("null");
    }
  }

  private static void quote(String value, StringBuilder out) {
    out.append('"');
    for (int i = 0; i < value.length(); i++) {
      char c = value.charAt(i);
      if (c == '"' || c == '\\') out.append('\\').append(c);
      else if (c == '\n') out.append("\\n");
      else if (c == '\r') out.append("\\r");
      else if (c == '\t') out.append("\\t");
      else if (c < 0x20 || c == 0x2028 || c == 0x2029) out.append(String.format(Locale.ROOT, "\\u%04x", (int) c));
      else out.append(c);
    }
    out.append('"');
  }

  private void skipSpace() {
    while (at < text.length() && " \t\r\n".indexOf(text.charAt(at)) >= 0) at++;
  }

  private char next() throws Malformed {
    if (at >= text.length()) throw new Malformed("Unexpected end of JSON");
    return text.charAt(at++);
  }

  private void expect(String word) throws Malformed {
    if (!text.startsWith(word, at)) throw new Malformed("Unexpected token at " + at);
    at += word.length();
  }

  private Object value(int depth) throws Malformed {
    if (depth > MAX_DEPTH) throw new Malformed("JSON is nested too deeply");
    if (++values > MAX_VALUES) throw new Malformed("JSON has too many values");
    skipSpace();
    if (at >= text.length()) throw new Malformed("Unexpected end of JSON");
    char c = text.charAt(at);
    if (c == '{') return object(depth);
    if (c == '[') return array(depth);
    if (c == '"') return string();
    if (c == 't') {
      expect("true");
      return Boolean.TRUE;
    }
    if (c == 'f') {
      expect("false");
      return Boolean.FALSE;
    }
    if (c == 'n') {
      expect("null");
      return null;
    }
    return number();
  }

  private Map<String, Object> object(int depth) throws Malformed {
    Map<String, Object> result = new LinkedHashMap<>();
    at++;
    skipSpace();
    if (at < text.length() && text.charAt(at) == '}') {
      at++;
      return result;
    }
    while (true) {
      skipSpace();
      if (at >= text.length() || text.charAt(at) != '"') throw new Malformed("Expected a key at " + at);
      String key = string();
      skipSpace();
      if (next() != ':') throw new Malformed("Expected ':' at " + (at - 1));
      result.put(key, value(depth + 1));
      skipSpace();
      char separator = next();
      if (separator == '}') return result;
      if (separator != ',') throw new Malformed("Expected ',' at " + (at - 1));
    }
  }

  private List<Object> array(int depth) throws Malformed {
    List<Object> result = new ArrayList<>();
    at++;
    skipSpace();
    if (at < text.length() && text.charAt(at) == ']') {
      at++;
      return result;
    }
    while (true) {
      result.add(value(depth + 1));
      skipSpace();
      char separator = next();
      if (separator == ']') return result;
      if (separator != ',') throw new Malformed("Expected ',' at " + (at - 1));
    }
  }

  private String string() throws Malformed {
    StringBuilder result = new StringBuilder();
    at++;
    while (true) {
      char c = next();
      if (c == '"') return result.toString();
      if (c < 0x20) throw new Malformed("Control character in text at " + (at - 1));
      if (c != '\\') {
        result.append(c);
        continue;
      }
      char escape = next();
      switch (escape) {
        case '"': case '\\': case '/': result.append(escape); break;
        case 'b': result.append('\b'); break;
        case 'f': result.append('\f'); break;
        case 'n': result.append('\n'); break;
        case 'r': result.append('\r'); break;
        case 't': result.append('\t'); break;
        case 'u':
          if (at + 4 > text.length() || !text.substring(at, at + 4).matches("[0-9a-fA-F]{4}")) {
            throw new Malformed("Bad unicode escape at " + at);
          }
          result.append((char) Integer.parseInt(text.substring(at, at + 4), 16));
          at += 4;
          break;
        default: throw new Malformed("Bad escape at " + (at - 1));
      }
    }
  }

  private Object number() throws Malformed {
    int start = at;
    while (at < text.length() && "+-.eE0123456789".indexOf(text.charAt(at)) >= 0) at++;
    String literal = text.substring(start, at);
    if (!literal.matches("-?(0|[1-9]\\d*)(\\.\\d+)?([eE][+-]?\\d+)?")) throw new Malformed("Unexpected token at " + start);
    if (literal.matches("-?\\d{1,18}")) return Long.valueOf(literal);
    double number = Double.parseDouble(literal);
    if (Double.isInfinite(number)) throw new Malformed("Number is out of range at " + start);
    return number;
  }
}
