'use strict';
(function(root, factory) {
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  else root.SkylitHouseholdModel = api;
})(typeof window !== 'undefined' ? window : globalThis, function() {
  const limits = {people: 12, chores: 100, shopping: 200, text: 80, qty: 99, note: 200, emoji: 8, id: 64, history: 14};
  const colors = [['#9A513B', 'Terracotta'], ['#687354', 'Olive'], ['#547D91', 'Blue'], ['#916980', 'Plum'], ['#AD7937', 'Honey'], ['#3F7F7A', 'Teal'], ['#B5606E', 'Rose'], ['#5C6680', 'Slate']];
  const dayNames = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

  const trimmed = value => typeof value === 'string' ? value.trim() : '';
  const validText = value => { const text = trimmed(value); return text.length >= 1 && text.length <= limits.text; };
  const validColor = value => typeof value === 'string' && /^#[0-9a-fA-F]{6}$/.test(value);
  const validId = value => typeof value === 'string' && value.length > 0 && value.length <= limits.id;
  const validQty = value => Number.isInteger(value) && value >= 1 && value <= limits.qty;
  const validEmoji = value => typeof value === 'string' && Array.from(value.trim()).length <= limits.emoji;
  const validNote = value => typeof value === 'string' && value.length <= limits.note;
  const validDays = value => Array.isArray(value) && value.every(day => Number.isInteger(day) && day >= 0 && day <= 6) && new Set(value).size === value.length;

  function isDate(value) {
    if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
    const parsed = new Date(value + 'T12:00:00Z');
    return Number.isFinite(parsed.getTime()) && parsed.toISOString().slice(0, 10) === value;
  }
  function shiftDate(date, days) {
    return new Date(Date.parse(date + 'T12:00:00Z') + days * 86400000).toISOString().slice(0, 10);
  }
  function weekday(date) {
    return new Date(date + 'T12:00:00Z').getUTCDay();
  }
  function dateKey(now, zone) {
    const read = timeZone => {
      const parts = new Intl.DateTimeFormat('en-CA', {timeZone, year: 'numeric', month: '2-digit', day: '2-digit'}).formatToParts(now);
      const get = type => parts.find(part => part.type === type).value;
      return get('year') + '-' + get('month') + '-' + get('day');
    };
    try { return read(zone); } catch (_) { return read(undefined); }
  }

  function collect(list, limit, map) {
    const seen = new Set(), result = [];
    for (const raw of Array.isArray(list) ? list : []) {
      if (result.length >= limit) break;
      if (!raw || typeof raw !== 'object' || !validId(raw.id) || seen.has(raw.id)) continue;
      const item = map(raw);
      if (!item) continue;
      seen.add(raw.id);
      result.push(item);
    }
    return result;
  }
  const clip = value => trimmed(value).slice(0, limits.text);
  const cleanDays = value => Array.isArray(value) ? [...new Set(value.filter(day => Number.isInteger(day) && day >= 0 && day <= 6))].sort() : [];
  const cleanEmoji = value => Array.from(trimmed(value)).slice(0, limits.emoji).join('');

  function normalize(raw) {
    if (!raw || typeof raw !== 'object') raw = {};
    const people = collect(raw.people, limits.people, person => clip(person.name) ? {id: person.id, name: clip(person.name), color: validColor(person.color) ? person.color.toUpperCase() : colors[0][0]} : null);
    const known = new Set(people.map(person => person.id));
    const chores = collect(raw.chores, limits.chores, chore => clip(chore.title) ? {
      id: chore.id,
      title: clip(chore.title),
      emoji: cleanEmoji(chore.emoji),
      personId: known.has(chore.personId) ? chore.personId : null,
      days: cleanDays(chore.days),
      done: Array.isArray(chore.done) ? [...new Set(chore.done.filter(isDate))].sort() : []
    } : null);
    const shopping = collect(raw.shopping, limits.shopping, item => clip(item.name) ? {
      id: item.id,
      name: clip(item.name),
      qty: validQty(item.qty) ? item.qty : 1,
      note: typeof item.note === 'string' ? item.note.slice(0, limits.note) : '',
      done: item.done === true
    } : null);
    return {rev: Number.isInteger(raw.rev) && raw.rev >= 0 ? raw.rev : 0, people, chores, shopping};
  }

  const dueOn = (chore, date) => chore.days.length === 0 || chore.days.includes(weekday(date));
  const isDone = (chore, date) => chore.done.includes(date);

  function today(snapshot, date) {
    const due = snapshot.chores.filter(chore => dueOn(chore, date));
    const group = (person, chores) => {
      const rows = chores.map(chore => ({chore, done: isDone(chore, date)}));
      return {person, rows, done: rows.filter(row => row.done).length, total: rows.length};
    };
    const groups = snapshot.people.map(person => group(person, due.filter(chore => chore.personId === person.id)));
    groups.push(group(null, due.filter(chore => chore.personId === null)));
    const shown = groups.filter(entry => entry.total > 0);
    return {date, groups: shown, done: shown.reduce((sum, entry) => sum + entry.done, 0), total: due.length};
  }

  function describeDays(days) {
    if (days.length === 0 || days.length === 7) return 'Every day';
    const key = days.join('');
    if (key === '12345') return 'Weekdays';
    if (key === '06') return 'Weekends';
    return days.map(day => dayNames[day].slice(0, 3)).join(', ');
  }

  function ink(color) {
    if (!validColor(color)) return '#ffffff';
    const channel = offset => {
      const value = parseInt(color.slice(offset, offset + 2), 16) / 255;
      return value <= 0.03928 ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4);
    };
    const luminance = 0.2126 * channel(1) + 0.7152 * channel(3) + 0.0722 * channel(5);
    return luminance > 0.179 ? '#1c1814' : '#ffffff';
  }

  function check(snapshot, op) {
    if (!op || typeof op !== 'object') return 'Unknown change.';
    const has = key => op[key] !== undefined;
    const person = id => snapshot.people.some(entry => entry.id === id);
    const chore = id => snapshot.chores.some(entry => entry.id === id);
    const item = id => snapshot.shopping.some(entry => entry.id === id);
    const text = 'Use 1 to ' + limits.text + ' characters.';
    const choreFields = () => has('emoji') && !validEmoji(op.emoji) ? 'Use a shorter emoji.'
      : has('personId') && op.personId !== null && !person(op.personId) ? 'That person is no longer on the list.'
      : has('days') && !validDays(op.days) ? 'Choose days of the week.' : '';
    const itemFields = () => has('qty') && !validQty(op.qty) ? 'Use a quantity from 1 to ' + limits.qty + '.'
      : has('note') && !validNote(op.note) ? 'Use a shorter note.' : '';
    switch (op.op) {
      case 'person.add':
        if (snapshot.people.length >= limits.people) return 'Up to ' + limits.people + ' people.';
        return !validText(op.name) ? text : !validColor(op.color) ? 'Choose a colour.' : '';
      case 'person.update':
        if (!person(op.id)) return 'That person is no longer on the list.';
        return has('name') && !validText(op.name) ? text : has('color') && !validColor(op.color) ? 'Choose a colour.' : '';
      case 'person.remove':
        return person(op.id) ? '' : 'That person is no longer on the list.';
      case 'chore.add':
        if (snapshot.chores.length >= limits.chores) return 'Up to ' + limits.chores + ' chores.';
        return !validText(op.title) ? text : choreFields();
      case 'chore.update':
        if (!chore(op.id)) return 'That chore is no longer on the list.';
        return has('title') && !validText(op.title) ? text : choreFields();
      case 'chore.remove':
        return chore(op.id) ? '' : 'That chore is no longer on the list.';
      case 'chore.done':
        if (!chore(op.id)) return 'That chore is no longer on the list.';
        return !isDate(op.date) || typeof op.done !== 'boolean' ? 'Unknown change.' : '';
      case 'item.add':
        if (snapshot.shopping.length >= limits.shopping) return 'The list is full. Clear completed items first.';
        return !validText(op.name) ? text : itemFields();
      case 'item.update':
        if (!item(op.id)) return 'That item is no longer on the list.';
        return has('name') && !validText(op.name) ? text : has('done') && typeof op.done !== 'boolean' ? 'Unknown change.' : itemFields();
      case 'item.remove':
        return item(op.id) ? '' : 'That item is no longer on the list.';
      case 'items.clearDone':
        return '';
      default:
        return 'Unknown change.';
    }
  }

  function apply(snapshot, op, context) {
    const error = check(snapshot, op);
    if (error) return {ok: false, error};
    const next = JSON.parse(JSON.stringify(snapshot));
    const has = key => op[key] !== undefined;
    const find = (list, id) => list.find(entry => entry.id === id);
    const choreFields = target => {
      if (has('title')) target.title = op.title.trim();
      if (has('emoji')) target.emoji = op.emoji.trim();
      if (has('personId')) target.personId = op.personId;
      if (has('days')) target.days = op.days.slice().sort();
    };
    const itemFields = target => {
      if (has('name')) target.name = op.name.trim();
      if (has('qty')) target.qty = op.qty;
      if (has('note')) target.note = op.note;
      if (has('done')) target.done = op.done;
    };
    switch (op.op) {
      case 'person.add':
        next.people.push({id: context.id(), name: op.name.trim(), color: op.color.toUpperCase()});
        break;
      case 'person.update': {
        const target = find(next.people, op.id);
        if (has('name')) target.name = op.name.trim();
        if (has('color')) target.color = op.color.toUpperCase();
        break;
      }
      case 'person.remove':
        next.people = next.people.filter(entry => entry.id !== op.id);
        for (const entry of next.chores) if (entry.personId === op.id) entry.personId = null;
        break;
      case 'chore.add': {
        const target = {id: context.id(), title: '', emoji: '', personId: null, days: [], done: []};
        choreFields(target);
        next.chores.push(target);
        break;
      }
      case 'chore.update':
        choreFields(find(next.chores, op.id));
        break;
      case 'chore.remove':
        next.chores = next.chores.filter(entry => entry.id !== op.id);
        break;
      case 'chore.done': {
        const target = find(next.chores, op.id), oldest = shiftDate(context.today, 1 - limits.history);
        const dates = new Set(target.done);
        if (op.done) dates.add(op.date); else dates.delete(op.date);
        target.done = [...dates].filter(date => date >= oldest).sort();
        break;
      }
      case 'item.add': {
        const target = {id: context.id(), name: '', qty: 1, note: '', done: false};
        itemFields(target);
        next.shopping.push(target);
        break;
      }
      case 'item.update':
        itemFields(find(next.shopping, op.id));
        break;
      case 'item.remove':
        next.shopping = next.shopping.filter(entry => entry.id !== op.id);
        break;
      case 'items.clearDone':
        next.shopping = next.shopping.filter(entry => !entry.done);
        break;
    }
    next.rev = snapshot.rev + 1;
    return {ok: true, snapshot: next};
  }

  return {limits, colors, dayNames, normalize, isDate, shiftDate, weekday, dateKey, dueOn, isDone, today, describeDays, ink, check, apply};
});
