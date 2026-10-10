'use strict';
(() => {
  const key = 'skylit.onboarding.done';
  const app = window.SkylitApp;
  const $ = id => document.getElementById(id);

  // A prior settings record means this is an upgrade, even if the new guide has
  // never been opened. Do not interrupt an already configured household.
  const model = {
    shouldOpen: (stored, personal, done, route) => !stored && !personal && !done && !route,
    progress: (city, album, email, calendars) => ({
      city: city ? 'City set' : 'City needed',
      photos: album || email ? 'Photo source connected' : 'Choose a photo source',
      calendar: calendars > 0 ? `${calendars} calendar${calendars === 1 ? '' : 's'} added` : 'Optional · no calendar added'
    })
  };
  window.SkylitOnboardingModel = model;

  function nativeState(method, fallback) {
    try { return JSON.parse(window.Skylit[method]()); } catch (_) { return fallback; }
  }
  function render() {
    const state = app.setupState();
    const mail = nativeState('photoStatus', {});
    const calendars = nativeState('calendarList', []);
    const labels = model.progress(state.city, state.album, !!mail.connected, Array.isArray(calendars) ? calendars.length : 0);
    $('setup-city-status').textContent = labels.city;
    $('setup-photos-status').textContent = labels.photos;
    $('setup-calendar-status').textContent = labels.calendar;
  }
  function open() { render(); app.go('setup'); }
  function finish() {
    try { localStorage.setItem(key, '1'); } catch (_) { /* Setup stays available from Settings. */ }
    app.go('overview');
  }
  $('setup-dismiss').onclick = finish;
  $('setup-finish').onclick = finish;
  $('setup-reopen').onclick = open;
  document.querySelectorAll('[data-setup-target]').forEach(button => {
    button.onclick = () => {
      const target = button.dataset.setupTarget;
      app.go(target === 'photos' ? 'photos' : 'settings');
      if (target !== 'photos') {
        const node = $(target === 'calendar' ? 'calendar-settings' : 'city-form');
        requestAnimationFrame(() => node.scrollIntoView({block: 'start'}));
      }
    };
  });
  window.addEventListener('skylit-tab', event => { if (event.detail === 'setup') render(); });
  window.addEventListener('skylit-preferences', () => { if ($('setup').classList.contains('active')) render(); });
  let stored = false, done = false;
  try { stored = localStorage.getItem('skylit.settings') !== null; done = localStorage.getItem(key) === '1'; } catch (_) {}
  const personal = !!(window.SKYLIT_LOCAL && Object.keys(window.SKYLIT_LOCAL).length);
  if (model.shouldOpen(stored, personal, done, location.hash.slice(1))) open();
})();
