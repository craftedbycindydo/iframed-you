const {test} = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');

const source = fs.readFileSync('web/onboarding.js', 'utf8');

function launch({settings = null, personal = {}, done = null, hash = '', mail = false, calendars = []} = {}) {
  const values = new Map();
  if (settings !== null) values.set('skylit.settings', settings);
  if (done !== null) values.set('skylit.onboarding.done', done);
  const nodes = new Map();
  const element = id => {
    if (!nodes.has(id)) nodes.set(id, {textContent: '', classList: {contains: () => id === 'setup'}, scrollIntoView() {this.scrolled = true;}});
    return nodes.get(id);
  };
  const buttons = ['city-search', 'photos', 'calendar'].map(target => ({dataset: {setupTarget: target}}));
  const routes = [];
  const listeners = {};
  const window = {
    SKYLIT_LOCAL: personal,
    SkylitApp: {go: route => routes.push(route), setupState: () => ({city: false, album: false})},
    Skylit: {photoStatus: () => JSON.stringify({connected: mail}), calendarList: () => JSON.stringify(calendars)},
    addEventListener: (name, callback) => { listeners[name] = callback; }
  };
  vm.runInNewContext(source, {
    window,
    document: {getElementById: element, querySelectorAll: () => buttons},
    localStorage: {getItem: key => values.has(key) ? values.get(key) : null, setItem: (key, value) => values.set(key, value)},
    location: {hash},
    requestAnimationFrame: callback => callback()
  });
  return {window, routes, element, values, buttons};
}

test('fresh installation opens setup; dismissal persists and opens Overview', () => {
  const run = launch();
  assert.deepEqual(run.routes, ['setup']);
  assert.equal(run.element('setup-city-status').textContent, 'City needed');
  assert.equal(run.element('setup-photos-status').textContent, 'Choose a photo source');
  run.element('setup-finish').onclick();
  assert.deepEqual(run.routes, ['setup', 'overview']);
  assert.equal(run.values.get('skylit.onboarding.done'), '1');
  assert.deepEqual(launch({done: '1'}).routes, []);
});

test('upgrades, personal builds and explicit routes do not interrupt launch', () => {
  assert.deepEqual(launch({settings: '{}'}).routes, []);
  assert.deepEqual(launch({personal: {city: 'example'}}).routes, []);
  assert.deepEqual(launch({hash: '#photos'}).routes, []);
});

test('guide can be reopened and links to the real setup controls', () => {
  const run = launch({settings: '{}', mail: true, calendars: [{id: 'one'}]});
  run.element('setup-reopen').onclick();
  assert.deepEqual(run.routes, ['setup']);
  assert.equal(run.element('setup-photos-status').textContent, 'Photo source connected');
  assert.equal(run.element('setup-calendar-status').textContent, '1 calendar added');
  run.buttons[0].onclick();
  assert.equal(run.routes.at(-1), 'settings');
  assert.equal(run.element('city-form').scrolled, true);
  run.buttons[1].onclick();
  assert.equal(run.routes.at(-1), 'photos');
  run.buttons[2].onclick();
  assert.equal(run.element('calendar-settings').scrolled, true);
});
