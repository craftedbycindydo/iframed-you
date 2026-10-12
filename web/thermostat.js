'use strict';
(() => {
  const $ = id => document.getElementById(id);
  const app = window.SkylitApp, native = window.Skylit;
  const supported = !!native && ['thermostatSnapshot', 'thermostatSignIn', 'thermostatSignOut', 'thermostatStep', 'thermostatMode', 'thermostatResume', 'thermostatWatch'].every(method => typeof native[method] === 'function');
  const call = (method, ...args) => { try { return native[method](...args); } catch (_) { return null; } };
  const parse = value => {
    try {
      const result = typeof value === 'string' ? JSON.parse(value) : value;
      return result && typeof result === 'object' && !Array.isArray(result) ? result : null;
    } catch (_) { return null; }
  };
  const element = (tag, cls, text) => {
    const node = document.createElement(tag);
    if (cls) node.className = cls;
    if (text !== undefined) node.textContent = text;
    return node;
  };
  const text = (value, limit) => typeof value === 'string' ? value.trim().slice(0, limit) : '';
  const number = value => typeof value === 'number' && Number.isFinite(value) ? value : null;
  const modeWords = {heat: 'Heat', cool: 'Cool', off: 'Off', auto: 'Auto', emheat: 'Emergency heat'};
  const statusWords = {loading: 'Loading', stale: 'Not current', unavailable: 'Unreachable', locked_out: 'Paused', signed_out: 'Signed out'};

  function normalize(raw) {
    const row = parse(raw) || {}, signIn = parse(row.signIn), status = typeof row.status === 'string' ? row.status : 'unconfigured';
    return {
      configured: row.configured === true,
      status,
      controllable: row.controllable === true,
      account: text(row.account, 254),
      message: text(row.message, 200),
      polledAt: Date.parse(row.polledAt) || 0,
      retryAt: Date.parse(row.retryAt) || 0,
      signIn: signIn ? {pending: signIn.pending === true, error: text(signIn.error, 200), retryAt: Date.parse(signIn.retryAt) || 0} : null,
      thermostats: (Array.isArray(row.thermostats) ? row.thermostats : []).filter(item => item && typeof item === 'object' && typeof item.id === 'string' && /^t\d{1,3}$/.test(item.id)).slice(0, 8).map(item => {
        const range = parse(item.range), low = range ? number(range.min) : null, high = range ? number(range.max) : null;
        return {
          id: item.id,
          name: text(item.name, 40) || 'Thermostat',
          online: item.online === true,
          indoor: number(item.indoor),
          mode: typeof item.mode === 'string' && Object.prototype.hasOwnProperty.call(modeWords, item.mode) ? item.mode : '',
          heatAllowed: item.heatAllowed === true,
          coolAllowed: item.coolAllowed === true,
          setpoint: number(item.setpoint),
          min: low,
          max: high,
          changing: item.changing === true,
          failed: typeof item.error === 'string' && !!item.error,
          message: text(item.message, 200),
          hold: ['schedule', 'temporary', 'permanent'].includes(item.hold) ? item.hold : '',
          holdUntil: typeof item.holdUntil === 'string' && /^\d\d:\d\d$/.test(item.holdUntil) ? item.holdUntil : ''
        };
      })
    };
  }
  const degrees = value => value === null ? '—' : (Number.isInteger(value) ? String(value) : value.toFixed(1)) + '°';
  const clock = stamp => {
    const prefs = app.calendarPreferences();
    return new Intl.DateTimeFormat('en-CA', {timeZone: prefs.timezone, hour: 'numeric', minute: '2-digit', hour12: prefs.clock === '12'}).format(new Date(stamp));
  };
  function holdLine(thermostat) {
    if (thermostat.hold === 'permanent') return 'Permanent hold';
    if (thermostat.hold === 'schedule') return 'Following schedule';
    if (thermostat.hold !== 'temporary') return '';
    if (!thermostat.holdUntil) return 'Temporary hold';
    const hour = Number(thermostat.holdUntil.slice(0, 2)), minute = thermostat.holdUntil.slice(3);
    return 'Hold until ' + (app.calendarPreferences().clock === '12' ? (hour % 12 || 12) + ':' + minute + (hour < 12 ? ' AM' : ' PM') : thermostat.holdUntil);
  }
  function word(thermostat) {
    if (statusWords[state.status]) return statusWords[state.status];
    if (!thermostat.online) return 'Offline';
    if (thermostat.changing) return 'Updating…';
    return thermostat.failed ? 'Not saved' : '';
  }
  function describe() {
    const pending = state.signIn && state.signIn.pending, failed = state.signIn && !state.signIn.pending ? state.signIn : null;
    if (pending) return 'Signing in…';
    if (failed) return failed.retryAt ? 'Too many attempts — try again at ' + clock(failed.retryAt) : failed.error || 'Could not sign in. Try again.';
    if (state.status === 'signed_out') return 'Honeywell signed this frame out. Sign in again.';
    if (state.status === 'locked_out') return state.retryAt ? 'Too many attempts — try again at ' + clock(state.retryAt) : 'Too many attempts. Try again later.';
    if (!state.configured) return '';
    if (state.status === 'ok') return 'Connected' + (state.polledAt ? ' · Updated ' + clock(state.polledAt) : '');
    if (state.status === 'loading') return 'Connected · Loading thermostats…';
    if (state.status === 'stale') return 'Trying again' + (state.polledAt ? ' · Last updated ' + clock(state.polledAt) : '');
    return 'Honeywell unavailable. Trying again.';
  }

  let state = normalize(null), menuFor = '', armed = false, armTimer = 0, notice = '';
  const controls = new Map();

  function act(thermostat, method, ...args) {
    menuFor = '';
    if (call(method, thermostat.id, ...args) !== true) { thermostat.failed = true; thermostat.message = 'Could not reach the frame. Try again.'; }
    else thermostat.changing = true;
    renderTiles(thermostat.id + ':more');
  }
  function step(thermostat, delta) {
    const result = parse(call('thermostatStep', thermostat.id, delta));
    if (result && result.ok === true && number(result.setpoint) !== null) {
      thermostat.setpoint = result.setpoint;
      thermostat.changing = true;
      thermostat.failed = false;
      thermostat.message = '';
    } else {
      thermostat.failed = true;
      thermostat.message = result && text(result.error, 200) || 'Could not change the temperature. Try again.';
    }
    renderTiles(thermostat.id + (delta < 0 ? ':down' : ':up'));
  }
  function button(key, cls, label, glyph) {
    const control = element('button', cls), face = element('span', '', glyph);
    control.type = 'button';
    control.setAttribute('aria-label', label);
    face.setAttribute('aria-hidden', 'true');
    control.append(face);
    controls.set(key, control);
    return control;
  }
  function menu(thermostat, usable) {
    const list = element('div', 'thermostat-menu'), hold = holdLine(thermostat);
    list.setAttribute('role', 'menu');
    list.setAttribute('aria-label', thermostat.name + ' options');
    if (hold) list.append(element('p', '', hold));
    if (thermostat.message) list.append(element('p', '', thermostat.message));
    if (usable && (thermostat.hold === 'temporary' || thermostat.hold === 'permanent')) {
      const resume = element('button', '', 'Resume schedule');
      resume.type = 'button';
      resume.setAttribute('role', 'menuitem');
      resume.onclick = () => act(thermostat, 'thermostatResume');
      list.append(resume);
    }
    for (const mode of ['heat', 'cool']) {
      if (!thermostat[mode + 'Allowed']) continue;
      const current = thermostat.mode === mode, choice = element('button');
      choice.type = 'button';
      choice.setAttribute('role', 'menuitemradio');
      choice.setAttribute('aria-checked', String(current));
      choice.disabled = !usable;
      choice.append(element('span', '', 'Mode: ' + modeWords[mode]), element('span', '', current ? '✓' : ''));
      choice.onclick = () => { if (current) { menuFor = ''; renderTiles(thermostat.id + ':more'); } else act(thermostat, 'thermostatMode', mode); };
      list.append(choice);
    }
    if (!list.children.length) list.append(element('p', '', 'Nothing to change here.'));
    return list;
  }
  function renderTiles(focus) {
    const host = $('thermostat-tiles'), waiting = !state.thermostats.length && state.status !== 'unconfigured' && (state.configured || state.status === 'signed_out');
    controls.clear();
    host.replaceChildren();
    host.hidden = !state.thermostats.length && !waiting;
    if (!state.thermostats.some(thermostat => thermostat.id === menuFor)) menuFor = '';
    if (waiting) {
      const tile = element('div', 'thermostat-tile is-quiet'), open = element('button', 'quiet', 'Settings');
      open.type = 'button';
      open.onclick = () => app.openSettings && app.openSettings('thermostats', 'overview');
      tile.append(element('span', 'thermostat-note', 'Thermostats · ' + (statusWords[state.status] || 'Loading')), open);
      host.append(tile);
    }
    for (const thermostat of state.thermostats) {
      const usable = state.controllable && thermostat.online, steppable = usable && thermostat.setpoint !== null && thermostat.min !== null && thermostat.max !== null;
      const status = word(thermostat), tile = element('div', 'thermostat-tile' + (status ? ' is-quiet' : '')), name = element('div', 'thermostat-name'), line = element('span', 'thermostat-state'), dot = element('span', 'thermostat-dot');
      const down = button(thermostat.id + ':down', 'thermostat-step', 'Lower ' + thermostat.name, '−'), up = button(thermostat.id + ':up', 'thermostat-step', 'Raise ' + thermostat.name, '+'), more = button(thermostat.id + ':more', 'thermostat-more', thermostat.name + ' options', '⌄');
      dot.dataset.mode = thermostat.mode;
      dot.setAttribute('aria-hidden', 'true');
      line.append(dot, element('span', '', [modeWords[thermostat.mode] || 'Mode unknown', status].filter(Boolean).join(' · ')));
      name.append(element('strong', '', thermostat.name), line);
      down.disabled = !steppable || thermostat.setpoint <= thermostat.min;
      up.disabled = !steppable || thermostat.setpoint >= thermostat.max;
      down.onclick = () => step(thermostat, -1);
      up.onclick = () => step(thermostat, 1);
      more.setAttribute('aria-haspopup', 'menu');
      more.setAttribute('aria-expanded', String(menuFor === thermostat.id));
      more.onclick = () => { menuFor = menuFor === thermostat.id ? '' : thermostat.id; renderTiles(thermostat.id + ':more'); };
      const indoor = element('span', 'thermostat-indoor', degrees(thermostat.indoor)), setpoint = element('span', 'thermostat-setpoint', degrees(thermostat.setpoint));
      indoor.setAttribute('aria-label', 'Indoor temperature ' + degrees(thermostat.indoor));
      setpoint.setAttribute('aria-label', 'Set to ' + degrees(thermostat.setpoint));
      tile.append(name, indoor, down, setpoint, up, more);
      if (menuFor === thermostat.id) tile.append(menu(thermostat, usable));
      host.append(tile);
    }
    if (focus && controls.has(focus) && !controls.get(focus).disabled) controls.get(focus).focus();
  }
  function disarm() {
    armed = false;
    clearTimeout(armTimer);
    $('thermostat-sign-out').textContent = 'Sign out';
  }
  function renderSettings() {
    const pending = !!state.signIn && state.signIn.pending, list = $('thermostat-list');
    $('thermostat-form').hidden = state.configured;
    $('thermostat-account').hidden = !state.configured;
    $('thermostat-sign-in').disabled = !supported || pending;
    $('thermostat-sign-in').textContent = pending ? 'Signing in…' : 'Sign in';
    $('thermostat-account-email').textContent = state.account;
    list.replaceChildren();
    for (const thermostat of state.thermostats) {
      const row = element('div', 'preference-row'), copy = element('span');
      copy.append(element('strong', '', thermostat.name), element('span', 'small subtle', thermostat.online ? [modeWords[thermostat.mode], thermostat.indoor === null ? '' : degrees(thermostat.indoor) + ' indoors'].filter(Boolean).join(' · ') : 'Offline'));
      row.append(copy);
      list.append(row);
    }
    if (state.configured && !state.thermostats.length) list.append(element('p', 'subtle small', state.status === 'ok' ? 'No thermostats were found on this account.' : 'Thermostats will appear here.'));
    $('thermostat-status').textContent = !supported ? (native ? 'Update the Skylit app on this frame to use thermostats.' : 'Sign in on the frame. This browser preview does not contact Honeywell.') : notice || describe();
  }
  function receive(raw) {
    const focused = [...controls].find(([, control]) => control === document.activeElement);
    state = normalize(raw);
    if (!state.signIn || !state.signIn.pending) notice = '';
    if (!state.configured) disarm();
    renderTiles(focused && focused[0]);
    renderSettings();
  }

  $('thermostat-form').onsubmit = event => {
    event.preventDefault();
    const email = $('thermostat-email').value.trim(), password = $('thermostat-password').value;
    $('thermostat-password').value = '';
    if (!supported || !email || !password) return;
    const result = parse(call('thermostatSignIn', email, password));
    notice = result && result.ok === true ? 'Signing in…' : result && text(result.error, 200) || 'Could not start signing in. Try again.';
    if (result && result.ok === true) $('thermostat-email').value = '';
    renderSettings();
  };
  $('thermostat-sign-out').onclick = () => {
    if (!armed) {
      armed = true;
      $('thermostat-sign-out').textContent = 'Tap again to sign out';
      armTimer = setTimeout(disarm, 6000);
      return;
    }
    disarm();
    if (call('thermostatSignOut') !== true) { notice = 'Could not sign out. Try again.'; renderSettings(); }
  };
  document.addEventListener('click', event => {
    if (!menuFor || event.target && event.target.closest && event.target.closest('.thermostat-tile')) return;
    menuFor = '';
    renderTiles();
  });
  document.addEventListener('keydown', event => {
    if (!menuFor || event.key !== 'Escape') return;
    const opener = menuFor + ':more';
    menuFor = '';
    renderTiles(opener);
  });
  window.addEventListener('skylit-tab', event => { if (supported) call('thermostatWatch', event.detail === 'overview'); });
  window.addEventListener('skylit-settings', () => { renderTiles(); renderSettings(); });

  window.SkylitThermostat = {receive, status: () => state, supported};
  receive(supported ? call('thermostatSnapshot') : null);
})();
