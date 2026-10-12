'use strict';
(() => {
  const $ = id => document.getElementById(id);
  const app = window.SkylitApp, model = window.SkylitHouseholdModel, native = window.Skylit;
  const limits = model.limits;
  const element = (tag, cls, text) => {
    const node = document.createElement(tag);
    if (cls) node.className = cls;
    if (text !== undefined) node.textContent = text;
    return node;
  };
  const parse = (value, fallback) => {
    try {
      const result = typeof value === 'string' ? JSON.parse(value) : value;
      return result && typeof result === 'object' ? result : fallback;
    } catch (_) { return fallback; }
  };
  const today = () => model.dateKey(new Date(), app.calendarPreferences().timezone);

  function createFake() {
    const key = 'skylit.household.preview';
    const saved = (() => { try { return parse(localStorage.getItem(key), {}); } catch (_) { return {}; } })();
    const pairing = parse(saved.pairing, {});
    const data = {
      snapshot: model.normalize(saved.snapshot),
      pairing: {devices: Array.isArray(pairing.devices) ? pairing.devices : [], port: 8765, advertised: false}
    };
    const persist = () => { try { localStorage.setItem(key, JSON.stringify(data)); } catch (_) {} };
    let counter = 0;
    const id = () => Date.now().toString(36) + '-' + (counter++).toString(36) + '-' + Math.random().toString(36).slice(2, 8);
    return {
      householdSnapshot: () => JSON.stringify(data.snapshot),
      householdMutate(json) {
        const result = model.apply(data.snapshot, parse(json, null), {id, today: today()});
        if (result.ok) { data.snapshot = result.snapshot; persist(); }
        return JSON.stringify(result);
      },
      reportSettings() {},
      pairingStatus: () => JSON.stringify(data.pairing),
      pairingRevoke(deviceId) {
        data.pairing.devices = data.pairing.devices.filter(device => !device || device.id !== deviceId);
        persist();
        return true;
      },
      pairingRevokeAll() {
        data.pairing.devices = [];
        persist();
        return true;
      }
    };
  }
  const connected = !!native && typeof native.householdSnapshot === 'function' && typeof native.householdMutate === 'function';
  const bridge = connected ? native : createFake();
  const call = (method, ...args) => { try { return bridge[method](...args); } catch (_) { return null; } };

  let state = model.normalize(parse(call('householdSnapshot'), {}));
  function mutate(op) {
    const invalid = model.check(state, op);
    if (invalid) { app.notify(invalid); return false; }
    const result = parse(call('householdMutate', JSON.stringify(op)), null);
    if (!result || result.ok !== true || !result.snapshot) {
      app.notify(result && typeof result.error === 'string' && result.error ? result.error.slice(0, 200) : 'Could not save this change.');
      render();
      return false;
    }
    state = model.normalize(result.snapshot);
    render();
    return true;
  }
  function receive(snapshot) {
    const next = model.normalize(parse(snapshot, {}));
    if (next.rev < state.rev) return;
    state = next;
    render();
  }
  const created = (before, after) => after.find(entry => !before.some(old => old.id === entry.id));

  let managing = false, editingPerson = null, editingChore = null, personColor = model.colors[0][0], renderedDate = '';
  const choreDays = new Set(), dayButtons = [], rowButtons = new Map();
  const confirmations = new Set();

  function confirmTap(button, label, action) {
    button.textContent = label;
    button.onclick = () => {
      if (!confirmations.has(button)) {
        confirmations.add(button);
        button.textContent = 'Tap again to confirm';
        setTimeout(() => { confirmations.delete(button); button.textContent = label; }, 6000);
        return;
      }
      confirmations.delete(button);
      action();
    };
  }
  function avatar(person) {
    const badge = element('span', 'chore-avatar', person ? Array.from(person.name)[0].toUpperCase() : '✦');
    badge.setAttribute('aria-hidden', 'true');
    if (person) { badge.style.background = person.color; badge.style.color = model.ink(person.color); }
    return badge;
  }
  function meter(done, total) {
    const track = element('span', 'chore-meter'), fill = element('i');
    track.setAttribute('aria-hidden', 'true');
    fill.style.width = (total ? Math.round(done / total * 100) : 0) + '%';
    track.append(fill);
    return track;
  }

  function renderToday() {
    const view = model.today(state, today()), host = $('chores-today');
    const focused = [...rowButtons].find(([, button]) => button === document.activeElement);
    renderedDate = view.date;
    rowButtons.clear();
    host.replaceChildren();
    $('chores-progress').hidden = !view.total;
    $('chores-progress').textContent = view.total ? view.done + ' of ' + view.total + ' done today' : '';
    if (!view.total) {
      const empty = element('article', 'card chores-empty');
      empty.append(element('h2', '', state.chores.length ? 'Nothing due today' : 'No chores yet'));
      empty.append(element('p', 'subtle', state.chores.length ? 'Chores planned for other days are listed under Manage.' : 'Add the people in your home and what needs doing. You can also manage chores from the phone app.'));
      if (!state.chores.length) {
        const start = element('button', 'primary', 'Add chores');
        start.type = 'button';
        start.onclick = () => setManaging(true);
        empty.append(start);
      }
      host.append(empty);
    }
    for (const group of view.groups) {
      const card = element('article', 'card chore-group'), head = element('div', 'chore-group-head'), names = element('div');
      names.append(element('h2', '', group.person ? group.person.name : 'Anyone'), element('p', 'chore-count', group.done === group.total ? 'All done' : group.done + ' of ' + group.total + ' done'));
      head.append(avatar(group.person), names);
      card.append(head, meter(group.done, group.total));
      for (const row of group.rows) {
        const button = element('button', 'chore-row'), emoji = element('span', 'chore-emoji', row.chore.emoji), mark = element('span', 'chore-mark', row.done ? '✓' : '');
        button.type = 'button';
        button.setAttribute('aria-pressed', String(row.done));
        emoji.setAttribute('aria-hidden', 'true');
        mark.setAttribute('aria-hidden', 'true');
        button.append(mark, element('span', 'chore-title', row.chore.title), emoji);
        button.onclick = () => mutate({op: 'chore.done', id: row.chore.id, date: view.date, done: !row.done});
        rowButtons.set(row.chore.id, button);
        card.append(button);
      }
      host.append(card);
    }
    if (focused && rowButtons.has(focused[0])) rowButtons.get(focused[0]).focus();
    $('overview-chores').hidden = !state.chores.length;
    $('overview-chores-count').textContent = view.total ? view.done + ' of ' + view.total + ' done today' : 'None due today';
    $('overview-chores-bar').style.width = (view.total ? Math.round(view.done / view.total * 100) : 0) + '%';
  }

  function setManaging(value) {
    managing = value;
    $('chores-today').hidden = managing;
    $('chores-editor').hidden = !managing;
    $('chores-manage').textContent = managing ? 'Done' : 'Manage';
    $('chores-manage').setAttribute('aria-pressed', String(managing));
    if (!managing) { resetPerson(); resetChore(); }
  }
  function paintSwatches() {
    const host = $('person-colors'), choices = model.colors.slice();
    if (!choices.some(([value]) => value === personColor)) choices.push([personColor, 'Current colour']);
    host.replaceChildren();
    for (const [value, name] of choices) {
      const swatch = element('button', 'chore-swatch');
      swatch.type = 'button';
      swatch.style.background = value;
      swatch.setAttribute('aria-label', name);
      swatch.setAttribute('aria-pressed', String(value === personColor));
      swatch.onclick = () => { personColor = value; paintSwatches(); };
      host.append(swatch);
    }
  }
  function paintDays() {
    dayButtons.forEach((button, day) => button.setAttribute('aria-pressed', String(choreDays.has(day))));
  }
  function resetPerson() {
    editingPerson = null;
    $('person-name').value = '';
    const used = state.people.map(person => person.color), free = model.colors.find(([value]) => !used.includes(value));
    personColor = (free || model.colors[0])[0];
    paintManage();
  }
  function resetChore() {
    editingChore = null;
    $('chore-title').value = '';
    $('chore-emoji').value = '';
    $('chore-person').value = '';
    choreDays.clear();
    paintManage();
  }
  function editRow(parts, onEdit, onRemove) {
    const row = element('div', 'chore-edit-row'), actions = element('div', 'chore-edit-actions'), edit = element('button', 'quiet', 'Edit'), remove = element('button', 'quiet');
    edit.type = remove.type = 'button';
    edit.onclick = onEdit;
    confirmTap(remove, 'Remove', onRemove);
    actions.append(edit, remove);
    row.append(...parts, actions);
    return row;
  }
  function paintManage() {
    if (editingPerson && !state.people.some(person => person.id === editingPerson)) editingPerson = null;
    if (editingChore && !state.chores.some(chore => chore.id === editingChore)) editingChore = null;
    $('people-list').replaceChildren();
    for (const person of state.people) {
      $('people-list').append(editRow([avatar(person), element('strong', 'chore-edit-name', person.name)], () => {
        editingPerson = person.id;
        $('person-name').value = person.name;
        personColor = person.color;
        paintManage();
        $('person-name').focus();
      }, () => mutate({op: 'person.remove', id: person.id})));
    }
    if (!state.people.length) $('people-list').append(element('p', 'subtle small', 'No one yet. Chores without a person belong to Anyone.'));
    $('chore-list').replaceChildren();
    for (const chore of state.chores) {
      const owner = state.people.find(person => person.id === chore.personId), copy = element('div', 'chore-edit-name'), emoji = element('span', 'chore-emoji', chore.emoji);
      emoji.setAttribute('aria-hidden', 'true');
      copy.append(element('strong', '', chore.title), element('span', 'small subtle', (owner ? owner.name : 'Anyone') + ' · ' + model.describeDays(chore.days)));
      $('chore-list').append(editRow([emoji, copy], () => {
        editingChore = chore.id;
        $('chore-title').value = chore.title;
        $('chore-emoji').value = chore.emoji;
        choreDays.clear();
        chore.days.forEach(day => choreDays.add(day));
        paintManage();
        $('chore-person').value = chore.personId || '';
        $('chore-title').focus();
      }, () => mutate({op: 'chore.remove', id: chore.id})));
    }
    if (!state.chores.length) $('chore-list').append(element('p', 'subtle small', 'No chores yet.'));
    const selected = $('chore-person').value, anyone = element('option', '', 'Anyone');
    anyone.value = '';
    $('chore-person').replaceChildren(anyone);
    for (const person of state.people) {
      const option = element('option', '', person.name);
      option.value = person.id;
      $('chore-person').append(option);
    }
    $('chore-person').value = state.people.some(person => person.id === selected) ? selected : '';
    const peopleFull = !editingPerson && state.people.length >= limits.people, choresFull = !editingChore && state.chores.length >= limits.chores;
    $('person-form-title').textContent = editingPerson ? 'Edit person' : 'Add a person';
    $('person-save').textContent = editingPerson ? 'Save person' : 'Add person';
    $('person-save').disabled = peopleFull;
    $('person-limit').hidden = !peopleFull;
    $('person-cancel').hidden = !editingPerson;
    $('chore-form-title').textContent = editingChore ? 'Edit chore' : 'Add a chore';
    $('chore-save').textContent = editingChore ? 'Save chore' : 'Add chore';
    $('chore-save').disabled = choresFull;
    $('chore-limit').hidden = !choresFull;
    $('chore-cancel').hidden = !editingChore;
    paintSwatches();
    paintDays();
  }

  model.dayNames.forEach((name, day) => {
    const button = element('button', 'chore-day', name.slice(0, 3));
    button.type = 'button';
    button.setAttribute('aria-label', name);
    button.onclick = () => { if (choreDays.has(day)) choreDays.delete(day); else choreDays.add(day); paintDays(); };
    dayButtons.push(button);
    $('chore-days').append(button);
  });
  for (const emoji of ['🛏️', '🧹', '🍽️', '🧺', '🗑️', '🪴', '🐕', '📚', '🦷', '🧸', '🚿', '🛒']) {
    const pick = element('button', 'chore-emoji-pick', emoji);
    pick.type = 'button';
    pick.onclick = () => { $('chore-emoji').value = emoji; };
    $('chore-emoji-picks').append(pick);
  }
  $('chores-manage').onclick = () => setManaging(!managing);
  $('person-cancel').onclick = resetPerson;
  $('chore-cancel').onclick = resetChore;
  $('person-form').onsubmit = event => {
    event.preventDefault();
    const fields = {name: $('person-name').value.trim(), color: personColor};
    if (mutate(editingPerson ? {op: 'person.update', id: editingPerson, ...fields} : {op: 'person.add', ...fields})) resetPerson();
  };
  $('chore-form').onsubmit = event => {
    event.preventDefault();
    const fields = {title: $('chore-title').value.trim(), emoji: $('chore-emoji').value.trim(), personId: $('chore-person').value || null, days: [...choreDays].sort()};
    if (mutate(editingChore ? {op: 'chore.update', id: editingChore, ...fields} : {op: 'chore.add', ...fields})) resetChore();
  };

  let shoppingMounted = false, undo = null;
  function setUndo(action) {
    undo = action;
    $('shopping-undo').hidden = !action;
  }
  function restoreItems(items) {
    for (const item of items) {
      const before = state.shopping;
      if (!mutate({op: 'item.add', name: item.name, qty: item.qty, note: item.note})) return;
      const added = created(before, state.shopping);
      if (added && item.done) mutate({op: 'item.update', id: added.id, done: true});
    }
  }
  function renderShopping() {
    if (!shoppingMounted) return;
    $('shopping-items').replaceChildren();
    $('shopping-completed').replaceChildren();
    for (const item of state.shopping) {
      const button = element('button', 'shopping-item'), mark = element('span', 'shopping-mark', item.done ? '✓' : '○'), copy = element('span', 'shopping-copy');
      button.type = 'button';
      button.setAttribute('aria-pressed', String(item.done));
      mark.setAttribute('aria-hidden', 'true');
      copy.append(element('span', '', item.qty > 1 ? item.name + ' × ' + item.qty : item.name));
      if (item.note) copy.append(element('span', 'small subtle', item.note));
      button.append(mark, copy);
      button.onclick = () => {
        if (mutate({op: 'item.update', id: item.id, done: !item.done})) setUndo(() => mutate({op: 'item.update', id: item.id, done: item.done}));
      };
      $(item.done ? 'shopping-completed' : 'shopping-items').append(button);
    }
    if (!state.shopping.some(item => !item.done)) $('shopping-items').append(element('p', 'subtle small', 'Your list is clear.'));
    $('shopping-completed-label').textContent = 'Completed · ' + state.shopping.filter(item => item.done).length;
  }
  function mountShopping() {
    shoppingMounted = true;
    $('shopping-add').onsubmit = event => {
      event.preventDefault();
      const name = $('shopping-input').value.trim(), before = state.shopping;
      if (!name || !mutate({op: 'item.add', name})) return;
      $('shopping-input').value = '';
      const added = created(before, state.shopping);
      setUndo(added ? () => mutate({op: 'item.remove', id: added.id}) : null);
    };
    $('shopping-undo').onclick = () => {
      const action = undo;
      setUndo(null);
      if (action) action();
    };
    $('shopping-clear').onclick = () => {
      const cleared = state.shopping.filter(item => item.done);
      if (cleared.length && mutate({op: 'items.clearDone'})) setUndo(() => restoreItems(cleared));
    };
    renderShopping();
  }
  function migrateShopping() {
    let legacy;
    try { legacy = parse(localStorage.getItem('skylit.household'), null); } catch (_) { return; }
    if (!legacy || !Array.isArray(legacy.shopping) || !legacy.shopping.length || state.shopping.length) return;
    for (const old of legacy.shopping) {
      const name = old && typeof old.text === 'string' ? old.text.trim().slice(0, limits.text) : '';
      if (!name) continue;
      const before = state.shopping;
      if (!mutate({op: 'item.add', name})) return;
      const added = created(before, state.shopping);
      if (added && old.done === true) mutate({op: 'item.update', id: added.id, done: true});
    }
    try { localStorage.setItem('skylit.household', JSON.stringify({...legacy, shopping: []})); } catch (_) {}
  }

  const overlay = element('div', 'pairing-overlay'), pairingCard = element('div', 'pairing-card'), pairingCode = element('div', 'pairing-code'), pairingCountdown = element('p', 'pairing-countdown'), pairingDismiss = element('button', 'primary', 'Dismiss');
  const pairingTitle = element('h2', '', 'Enter this code on your phone');
  let pairingTimer = null, pairingExpires = 0, pairingFocus = null;
  overlay.hidden = true;
  overlay.setAttribute('role', 'dialog');
  overlay.setAttribute('aria-modal', 'true');
  overlay.setAttribute('aria-labelledby', 'pairing-title');
  pairingTitle.id = 'pairing-title';
  pairingCountdown.setAttribute('role', 'timer');
  pairingDismiss.type = 'button';
  pairingCard.append(element('p', 'eyebrow', 'PAIR A PHONE'), pairingTitle, pairingCode, pairingCountdown, element('p', 'subtle small', 'Only enter this code in the Skylit app on a phone you trust.'), pairingDismiss);
  overlay.append(pairingCard);
  document.body.append(overlay);

  function tickPairing() {
    const seconds = Math.ceil((pairingExpires - Date.now()) / 1000);
    if (seconds <= 0) { hidePairing(); return; }
    pairingCountdown.textContent = 'Expires in ' + Math.floor(seconds / 60) + ':' + String(seconds % 60).padStart(2, '0');
  }
  function showPairing(request) {
    request = parse(request, {});
    const code = typeof request.code === 'number' ? String(request.code).padStart(6, '0') : request.code;
    if (typeof code !== 'string' || !/^\d{6}$/.test(code)) return;
    const stamp = typeof request.expiresAt === 'number' ? (request.expiresAt < 1e12 ? request.expiresAt * 1000 : request.expiresAt) : Date.parse(request.expiresAt);
    pairingExpires = Number.isFinite(stamp) ? stamp : Date.now() + 120000;
    if (pairingExpires <= Date.now()) { hidePairing(); return; }
    pairingCode.replaceChildren(element('span', '', code.slice(0, 3)), element('span', '', code.slice(3)));
    pairingCode.setAttribute('aria-label', code.split('').join(' '));
    if (overlay.hidden) pairingFocus = document.activeElement;
    overlay.hidden = false;
    clearInterval(pairingTimer);
    pairingTimer = setInterval(tickPairing, 500);
    tickPairing();
    pairingDismiss.focus();
  }
  function hidePairing() {
    if (overlay.hidden) return;
    overlay.hidden = true;
    clearInterval(pairingTimer);
    pairingCode.replaceChildren();
    if (pairingFocus && pairingFocus.isConnected && pairingFocus.focus) pairingFocus.focus();
    pairingFocus = null;
    renderPhone();
  }
  pairingDismiss.onclick = hidePairing;
  document.addEventListener('keydown', event => {
    if (overlay.hidden) return;
    if (event.key !== 'Escape' && event.key !== 'Tab') return;
    event.preventDefault();
    event.stopImmediatePropagation();
    if (event.key === 'Escape') hidePairing(); else pairingDismiss.focus();
  }, true);

  function renderPhone() {
    const status = parse(call('pairingStatus'), {}), host = $('phone-devices');
    const devices = (Array.isArray(status.devices) ? status.devices : []).filter(device => device && typeof device.id === 'string' && device.id);
    $('phone-status').textContent = !connected ? 'Preview only · pairing works on the Android frame.' : status.advertised === true ? 'Ready to pair on your home network.' : 'Not visible on the network right now. Check Wi-Fi.';
    host.replaceChildren();
    for (const device of devices) {
      const row = element('div', 'preference-row'), copy = element('span'), revoke = element('button', 'quiet', 'Revoke'), paired = Date.parse(device.pairedAt);
      copy.append(element('strong', '', typeof device.name === 'string' && device.name.trim() ? device.name.trim().slice(0, limits.text) : 'Phone'));
      if (Number.isFinite(paired)) copy.append(element('span', 'small subtle', 'Paired ' + new Intl.DateTimeFormat('en-CA', {timeZone: app.calendarPreferences().timezone, year: 'numeric', month: 'short', day: 'numeric'}).format(new Date(paired))));
      revoke.type = 'button';
      revoke.onclick = () => {
        if (call('pairingRevoke', device.id) !== true) app.notify('Could not revoke this phone. Try again.');
        renderPhone();
      };
      row.append(copy, revoke);
      host.append(row);
    }
    if (!devices.length) host.append(element('p', 'subtle small', 'No phones are paired.'));
    $('phone-revoke-all').hidden = !devices.length;
  }
  confirmTap($('phone-revoke-all'), 'Revoke all phones', () => {
    if (call('pairingRevokeAll') !== true) app.notify('Could not revoke phones. Try again.');
    renderPhone();
  });

  let reported = null;
  function report(force) {
    const json = JSON.stringify(app.sharedSettings());
    if (!force && json === reported) return;
    reported = json;
    call('reportSettings', json);
  }
  const zone = value => {
    try { if (typeof value === 'string' && value) { new Intl.DateTimeFormat('en-CA', {timeZone: value}); return value; } } catch (_) {}
    return Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC';
  };
  function applyRemote(change) {
    change = parse(change, {});
    const place = parse(change.location, null), look = parse(change.appearance, null);
    if (place && typeof place.name === 'string' && place.name.trim() && place.name.trim().length <= limits.text && Number.isFinite(place.latitude) && Math.abs(place.latitude) <= 90 && Number.isFinite(place.longitude) && Math.abs(place.longitude) <= 180) {
      app.setCity({name: place.name.trim(), admin1: '', country: '', latitude: place.latitude, longitude: place.longitude, timezone: zone(place.timezone)});
    }
    if (look) {
      const display = {};
      if (typeof look.palette === 'string' && Object.prototype.hasOwnProperty.call(window.SkylitAppearance.palettes, look.palette)) display.theme = look.palette;
      if (['light', 'dark', 'auto'].includes(look.mode)) display.mode = look.mode;
      if (Object.keys(display).length) app.setDisplayPreferences(display);
    }
    report(true);
  }

  function render() {
    renderToday();
    paintManage();
    renderShopping();
  }

  window.SkylitHousehold = {receive, snapshot: () => state, mutate, connected};
  window.SkylitShopping = {mount: mountShopping};
  window.SkylitPairing = {show: showPairing, hide: hidePairing, isOpen: () => !overlay.hidden, refresh: renderPhone};
  window.SkylitRemote = {apply: applyRemote};

  window.addEventListener('skylit-settings', () => { report(false); if (today() !== renderedDate) renderToday(); });
  window.addEventListener('skylit-tab', event => { if (event.detail === 'chores' || event.detail === 'overview') renderToday(); });
  setInterval(() => { if (today() !== renderedDate) renderToday(); }, 30000);

  migrateShopping();
  setManaging(false);
  render();
  renderPhone();
  report(true);
})();
