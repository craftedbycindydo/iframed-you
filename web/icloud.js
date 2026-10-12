'use strict';
(() => {
  const $ = id => document.getElementById(id);
  const app = window.SkylitApp, native = window.Skylit;
  const supported = !!native && ['icloudStatus', 'icloudConnect', 'icloudDisconnect', 'icloudSync'].every(method => typeof native[method] === 'function');
  const patterns = [/^https:\/\/www\.icloud\.com\/sharedalbum\/#[A-Za-z0-9_-]{1,128}$/, /^https:\/\/share\.icloud\.com\/photos\/[A-Za-z0-9_-]{1,128}$/];
  const validLink = value => typeof value === 'string' && patterns.some(pattern => pattern.test(value.trim()));
  const parse = value => {
    try {
      const result = typeof value === 'string' ? JSON.parse(value) : value;
      return result && typeof result === 'object' ? result : null;
    } catch (_) { return null; }
  };
  function normalize(raw) {
    const row = parse(raw);
    if (!row || Array.isArray(row)) return null;
    const synced = typeof row.lastSync === 'number' ? row.lastSync : Date.parse(row.lastSync);
    return {
      name: typeof row.name === 'string' && row.name.trim() ? row.name.trim().slice(0, 80) : 'Shared album',
      count: Number.isInteger(row.count) && row.count > 0 ? row.count : 0,
      lastSync: Number.isFinite(synced) && synced > 0 ? synced : 0,
      syncing: row.syncing === true,
      error: typeof row.error === 'string' ? row.error.slice(0, 200) : ''
    };
  }
  const when = stamp => {
    const prefs = app.calendarPreferences();
    return new Intl.DateTimeFormat('en-CA', {timeZone: prefs.timezone, month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit', hour12: prefs.clock === '12'}).format(new Date(stamp));
  };
  const pictures = count => count + (count === 1 ? ' picture' : ' pictures');
  function describe(status) {
    if (!status) return 'Not set up';
    if (status.syncing) return 'Syncing album… · ' + pictures(status.count);
    if (status.error) return 'Needs attention · ' + pictures(status.count) + ' saved';
    return status.lastSync ? pictures(status.count) + ' · Synced ' + when(status.lastSync) : 'Connected · Waiting for the first sync';
  }

  let state = null, armed = false, armTimer = 0;
  const message = text => { $('icloud-status').textContent = text; };
  function disarm() {
    armed = false;
    clearTimeout(armTimer);
    $('icloud-disconnect').textContent = 'Disconnect album';
  }
  function render() {
    $('icloud-connected').hidden = !state;
    $('icloud-entry').hidden = !!state;
    $('icloud-connect').disabled = !supported;
    $('icloud-name').textContent = state ? state.name : '';
    $('icloud-detail').textContent = state ? describe(state) : '';
    $('icloud-error').textContent = state ? state.error : '';
    $('icloud-error').hidden = !state || !state.error;
    $('icloud-sync').disabled = !state || state.syncing;
    $('icloud-sync').textContent = state && state.syncing ? 'Syncing…' : 'Sync now';
    $('icloud-connected').setAttribute('aria-busy', String(!!state && state.syncing));
    if (!supported) message(native ? 'Update the Skylit app on this frame to use iCloud albums.' : 'Connect an album on the frame. This browser preview does not store private links.');
    window.dispatchEvent(new Event('skylit-service-status'));
  }
  function receive(raw) {
    state = normalize(raw);
    if (!state) disarm();
    if (supported && state && !state.syncing) message('');
    render();
  }
  function read() {
    if (!supported) return;
    try { receive(native.icloudStatus()); } catch (_) { message('Could not read the album status from this frame.'); }
  }
  function sync() {
    if (!supported || !state || state.syncing) return;
    try { native.icloudSync(); } catch (_) { message('Could not start a sync. Try again.'); return; }
    message('');
    read();
  }

  $('icloud-form').onsubmit = event => {
    event.preventDefault();
    const input = $('icloud-link'), link = input.value.trim();
    input.value = '';
    if (!supported) { render(); return; }
    if (!validLink(link)) { message('Use the public link from the album’s People tab. It starts with https://www.icloud.com/sharedalbum/ or https://share.icloud.com/photos/.'); return; }
    let result = null;
    try { result = parse(native.icloudConnect(link)); } catch (_) {}
    if (!result || result.ok !== true) {
      message(result && typeof result.error === 'string' && result.error ? result.error.slice(0, 200) : 'Could not connect this album. Check the link and Wi-Fi, then try again.');
      return;
    }
    message('Album connected. Pictures appear in Photos after the first sync.');
    read();
  };
  $('icloud-sync').onclick = sync;
  $('icloud-disconnect').onclick = () => {
    if (!armed) {
      armed = true;
      $('icloud-disconnect').textContent = 'Tap again to remove album pictures';
      armTimer = setTimeout(disarm, 8000);
      return;
    }
    disarm();
    let removed = false;
    try { removed = native.icloudDisconnect() === true; } catch (_) {}
    read();
    message(removed ? 'Album disconnected. Its pictures were removed from this frame.' : 'Could not disconnect. Wait for the current sync to finish, then try again.');
  };

  window.SkylitICloud = {
    receive, sync, validLink, describe, supported,
    status: () => state,
    health: () => ({configured: !!state, updated: state ? state.lastSync : 0, busy: !!state && state.syncing, error: !!state && !!state.error, count: state ? state.count : 0})
  };
  render();
  read();
})();
