'use strict';
(() => {
  const key = 'skylit.onboarding.done';
  const app = window.SkylitApp;
  const $ = id => document.getElementById(id);

  // A prior settings record means this is an upgrade, even if the new guide has
  // never been opened. Do not interrupt an already configured household.
  const model = {
    shouldOpen: (stored, personal, done, route) => !stored && !personal && !done && !route,
    progress: (city, album, email, calendars, received=0, refreshed=0, icloud=false) => ({
      city: city ? 'City set' : 'City needed',
      photos: received>0?'Picture received · Check playback on frame':email?'Configured · Send a test picture':icloud?'iCloud album connected · Pictures appear after the first sync':album?'Album configured · Open to verify playback':'Choose a photo source',
      calendar: refreshed>0?'Calendar refreshed · Check your events':calendars > 0 ? `${calendars} calendar${calendars === 1 ? '' : 's'} added` : 'Optional · no calendar added'
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
    const labels = model.progress(state.city, state.album, !!mail.connected, Array.isArray(calendars) ? calendars.length : 0,Array.isArray(mail.photos)?mail.photos.length:0,Array.isArray(calendars)&&calendars.length&&calendars.every(c=>c.fetchedAt>0)?Math.min(...calendars.map(c=>c.fetchedAt)):0,!!(window.SkylitICloud&&window.SkylitICloud.status()));
    let step='';try{step=localStorage.getItem('skylit.onboarding.step')||'';}catch(_){}
    document.querySelectorAll('[data-setup-target]').forEach(button=>{if(button.closest){const card=button.closest('.setup-step');if(card)card.setAttribute('aria-current',button.dataset.setupTarget===step?'step':'false');}});
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
      try{localStorage.setItem('skylit.onboarding.step',target);}catch(_){}
      if(app.openSettings){app.openSettings(target==='photos'?'photos':target==='calendar'?'calendars':'weather','setup');return;}
      app.go(target === 'photos' ? 'photos' : 'settings');
      if (target !== 'photos') {
        const node = $(target === 'calendar' ? 'calendar-settings' : 'city-form');
        requestAnimationFrame(() => node.scrollIntoView({block: 'start'}));
      }
    };
  });
  window.addEventListener('skylit-tab', event => { if (event.detail === 'setup') render(); });
  window.addEventListener('skylit-preferences', () => { if ($('setup').classList.contains('active')) render(); });
  window.addEventListener('skylit-service-status', () => { if ($('setup').classList.contains('active')) render(); });
  let stored = false, done = false;
  try { stored = localStorage.getItem('skylit.settings') !== null; done = localStorage.getItem(key) === '1'; } catch (_) {}
  const personal = !!(window.SKYLIT_LOCAL && Object.keys(window.SKYLIT_LOCAL).length);
  if (model.shouldOpen(stored, personal, done, location.hash.slice(1))) open();
})();
