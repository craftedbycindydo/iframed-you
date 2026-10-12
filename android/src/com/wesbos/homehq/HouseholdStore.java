package com.wesbos.homehq;

import java.util.ArrayList;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.TreeSet;

final class HouseholdStore {
  static final int MAX_PEOPLE = 12;
  static final int MAX_CHORES = 100;
  static final int MAX_ITEMS = 200;
  static final int KEPT_DAYS = 14;
  private static final int MAX_TEXT = 80;
  private static final int MAX_EMOJI = 16;
  private static final int MAX_NOTE = 200;
  private static final String KEY = "household";

  private final KeyValue storage;
  private List<Object> people = new ArrayList<>();
  private List<Object> chores = new ArrayList<>();
  private List<Object> shopping = new ArrayList<>();
  private long rev;
  private long sequence;

  HouseholdStore(KeyValue storage) {
    this.storage = storage;
    try {
      Map<String, Object> saved = Json.map(Json.parse(storage.get(KEY)));
      long savedRev = ((Number) saved.get("rev")).longValue();
      long savedSequence = ((Number) saved.get("sequence")).longValue();
      List<Object> savedPeople = rows(saved.get("people"));
      List<Object> savedChores = rows(saved.get("chores"));
      List<Object> savedShopping = rows(saved.get("shopping"));
      rev = savedRev;
      sequence = savedSequence;
      people = savedPeople;
      chores = savedChores;
      shopping = savedShopping;
    } catch (Json.Malformed | RuntimeException absentOrUnreadable) {
      rev = 0;
    }
  }

  private static List<Object> rows(Object value) {
    List<Object> rows = Json.list(value);
    for (Object row : rows) if (Json.map(row) == null) throw new IllegalArgumentException("row");
    return rows;
  }

  synchronized long rev() {
    return rev;
  }

  synchronized long touch() {
    rev++;
    save();
    return rev;
  }

  synchronized Map<String, Object> snapshot(String today) {
    prune(today);
    return Json.object("rev", rev, "people", Json.copy(people), "chores", Json.copy(chores),
        "shopping", Json.copy(shopping));
  }

  synchronized Map<String, Object> mutate(Map<String, Object> op, String today) throws ApiException {
    prune(today);
    String before = content();
    String key = null;
    Map<String, Object> changed = null;
    Object name = op.get("op");
    if (!(name instanceof String)) throw ApiException.badRequest("op is required");
    switch ((String) name) {
      case "person.add":
        key = "person";
        changed = append(people, MAX_PEOPLE, "p", person(new LinkedHashMap<String, Object>(), op, true));
        break;
      case "person.update":
        key = "person";
        changed = replace(people, op, person(found(people, op), op, false));
        break;
      case "person.remove":
        Object removed = found(people, op).get("id");
        people.remove(index(people, op));
        for (Object chore : chores) {
          if (removed.equals(Json.map(chore).get("personId"))) Json.map(chore).put("personId", null);
        }
        break;
      case "chore.add":
        key = "chore";
        changed = append(chores, MAX_CHORES, "c", chore(new LinkedHashMap<String, Object>(), op, true));
        break;
      case "chore.update":
        key = "chore";
        changed = replace(chores, op, chore(found(chores, op), op, false));
        break;
      case "chore.remove":
        chores.remove(index(chores, op));
        break;
      case "chore.done":
        key = "chore";
        changed = replace(chores, op, done(found(chores, op), op, today));
        break;
      case "item.add":
        key = "item";
        changed = append(shopping, MAX_ITEMS, "s", item(new LinkedHashMap<String, Object>(), op, true));
        break;
      case "item.update":
        key = "item";
        changed = replace(shopping, op, item(found(shopping, op), op, false));
        break;
      case "item.remove":
        shopping.remove(index(shopping, op));
        break;
      case "items.clearDone":
        for (Iterator<Object> items = shopping.iterator(); items.hasNext();) {
          if (Boolean.TRUE.equals(Json.map(items.next()).get("done"))) items.remove();
        }
        break;
      default:
        throw ApiException.badRequest("Unknown op");
    }
    if (!content().equals(before)) {
      rev++;
      save();
    }
    Map<String, Object> result = Json.object("rev", rev);
    if (changed != null) result.put(key, Json.copy(changed));
    return result;
  }

  private String content() {
    return Json.write(Json.object("people", people, "chores", chores, "shopping", shopping));
  }

  private void save() {
    Map<String, Object> saved = Json.object("rev", rev, "sequence", sequence);
    saved.put("people", people);
    saved.put("chores", chores);
    saved.put("shopping", shopping);
    storage.put(KEY, Json.write(saved));
  }

  private void prune(String today) {
    String oldestKept = FrameTime.shift(today, 1 - KEPT_DAYS);
    boolean pruned = false;
    for (Object row : chores) {
      List<Object> kept = new ArrayList<>();
      List<Object> dates = Json.list(Json.map(row).get("done"));
      for (Object date : dates) if (((String) date).compareTo(oldestKept) >= 0) kept.add(date);
      if (kept.size() != dates.size()) {
        Json.map(row).put("done", kept);
        pruned = true;
      }
    }
    if (pruned) save();
  }

  private static int index(List<Object> rows, Map<String, Object> op) throws ApiException {
    Object id = op.get("id");
    for (int i = 0; i < rows.size(); i++) if (Json.map(rows.get(i)).get("id").equals(id)) return i;
    throw ApiException.notFound("Nothing has that id");
  }

  private static Map<String, Object> found(List<Object> rows, Map<String, Object> op) throws ApiException {
    return new LinkedHashMap<>(Json.map(rows.get(index(rows, op))));
  }

  private Map<String, Object> append(List<Object> rows, int limit, String prefix, Map<String, Object> row)
      throws ApiException {
    if (rows.size() >= limit) throw ApiException.badRequest("The limit of " + limit + " has been reached");
    Map<String, Object> created = Json.object("id", prefix + (++sequence));
    created.putAll(row);
    rows.add(created);
    return created;
  }

  private static Map<String, Object> replace(List<Object> rows, Map<String, Object> op, Map<String, Object> row)
      throws ApiException {
    rows.set(index(rows, op), row);
    return row;
  }

  private static Map<String, Object> person(Map<String, Object> row, Map<String, Object> op, boolean creating)
      throws ApiException {
    if (creating || op.containsKey("name")) row.put("name", Fields.text(op, "name", 1, MAX_TEXT));
    if (creating || op.containsKey("color")) row.put("color", Fields.color(op, "color"));
    return row;
  }

  private Map<String, Object> chore(Map<String, Object> row, Map<String, Object> op, boolean creating)
      throws ApiException {
    if (creating || op.containsKey("title")) row.put("title", Fields.text(op, "title", 1, MAX_TEXT));
    if (op.containsKey("emoji")) row.put("emoji", Fields.text(op, "emoji", 0, MAX_EMOJI));
    else if (creating) row.put("emoji", "");
    if (op.containsKey("personId")) row.put("personId", personId(op.get("personId")));
    else if (creating) row.put("personId", null);
    if (op.containsKey("days")) row.put("days", days(op.get("days")));
    else if (creating) row.put("days", new ArrayList<Object>());
    if (creating) row.put("done", new ArrayList<Object>());
    return row;
  }

  private Object personId(Object value) throws ApiException {
    if (value == null) return null;
    for (Object person : people) if (Json.map(person).get("id").equals(value)) return value;
    throw ApiException.badRequest("personId does not match a person");
  }

  private static List<Object> days(Object value) throws ApiException {
    if (Json.list(value) == null) throw ApiException.badRequest("days must be a list");
    boolean[] chosen = new boolean[7];
    for (Object day : Json.list(value)) chosen[(int) Fields.whole(day, "days", 0, 6)] = true;
    List<Object> sorted = new ArrayList<>();
    for (int day = 0; day < 7; day++) if (chosen[day]) sorted.add((long) day);
    return sorted;
  }

  private static Map<String, Object> done(Map<String, Object> row, Map<String, Object> op, String today)
      throws ApiException {
    Object date = op.get("date");
    boolean kept = FrameTime.validDay(date)
        && ((String) date).compareTo(FrameTime.shift(today, 1 - KEPT_DAYS)) >= 0
        && ((String) date).compareTo(FrameTime.shift(today, 1)) <= 0;
    if (!kept) throw ApiException.badRequest("date must be a YYYY-MM-DD day within the last " + KEPT_DAYS + " days");
    TreeSet<Object> dates = new TreeSet<>(Json.list(row.get("done")));
    if (Fields.flag(op, "done")) dates.add(date);
    else dates.remove(date);
    row.put("done", new ArrayList<>(dates));
    return row;
  }

  private static Map<String, Object> item(Map<String, Object> row, Map<String, Object> op, boolean creating)
      throws ApiException {
    if (creating || op.containsKey("name")) row.put("name", Fields.text(op, "name", 1, MAX_TEXT));
    if (op.containsKey("qty")) row.put("qty", Fields.whole(op.get("qty"), "qty", 1, 99));
    else if (creating) row.put("qty", 1L);
    if (op.containsKey("note")) row.put("note", Fields.text(op, "note", 0, MAX_NOTE));
    else if (creating) row.put("note", "");
    if (!creating && op.containsKey("done")) row.put("done", Fields.flag(op, "done"));
    else if (creating) row.put("done", false);
    return row;
  }
}
