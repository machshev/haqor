// Exercise the index page's loader without Flutter or browser storage.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {runInNewContext} from 'node:vm';
import {test} from 'node:test';
const html = readFileSync(new URL('../web/index.html', import.meta.url), 'utf8');
test('loading screen shows the version declared in pubspec.yaml', () => {
  const manifest = readFileSync(new URL('../pubspec.yaml', import.meta.url), 'utf8');
  const version = manifest.match(/^version: (\S+)$/m)[1];
  assert.ok(html.includes(`<div id="haqor-boot-version">Haqor ${version}</div>`));
});

const loader = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].at(-1)[1];

async function start({isolated = false, controller = null, installing = null,
  registrationError = null, search = '', serviceWorkers = true} = {}) {
  const events = new Map();
  const timers = new Map();
  const failures = [];
  const scripts = [];
  const navigations = [];
  const history = [];
  let painted = false;
  const registration = {installing, addEventListener() {}};
  const serviceWorker = {
    controller,
    addEventListener(name, handler) { events.set(name, handler); },
    async register() {
      if (registrationError) throw registrationError;
      return registration;
    },
  };
  const boot = {status() {}, fail(...args) { failures.push(args); }, isDone() {return painted;}};
  const location = {hostname: 'machshev.github.io', search,
    href: `https://machshev.github.io/haqor/${search}`,
    replace(url) {navigations.push(String(url));}, reload() {navigations.push('reload');}};
  runInNewContext(loader, {
    URL, URLSearchParams, console: {error() {}}, crossOriginIsolated: isolated,
    navigator: serviceWorkers ? {serviceWorker} : {},
    window: {haqorBoot: boot, location, history: {replaceState(_s, _t, url) {history.push(String(url));}}},
    document: {createElement() {return {addEventListener() {}};}, body: {appendChild(s) {scripts.push(s.src);}}},
    setTimeout(handler) { const id = timers.size + 1; timers.set(id, handler); return id; },
    clearTimeout(id) {timers.delete(id);},
  });
  await new Promise(resolve => setImmediate(resolve));
  return {events, timers, failures, scripts, navigations, history, paint() {painted = true;}};
}
const controller = {scriptURL: 'https://machshev.github.io/haqor/flutter_service_worker.js'};

test('failed installation leaves a visible error instead of waiting for control', async () => {
  let change;
  const installing = {state: 'installing', addEventListener(_name, handler) {change = handler;}};
  const app = await start({installing});
  installing.state = 'redundant'; change();
  assert.match(app.failures[0][1], /downloaded or stored/);
  assert.equal(app.timers.size, 0);
  assert.equal(app.scripts.length, 0);
});
test('registration rejection and a stalled installation report setup failures', async () => {
  const rejected = await start({registrationError: new Error('storage blocked')});
  assert.match(rejected.failures[0][1], /storage blocked/);
  assert.equal(rejected.timers.size, 0);
  const stalled = await start();
  [...stalled.timers.values()][0]();
  assert.match(stalled.failures[0][1], /taking too long/);
});
test('taking control reloads once and cancels the setup timeout', async () => {
  const app = await start();
  app.events.get('controllerchange')(); app.events.get('controllerchange')();
  assert.equal(app.navigations.length, 1);
  assert.match(app.navigations[0], /_haqor_coi_retry=1/);
  assert.equal(app.timers.size, 0);
});
test('isolated startup removes only its retry parameter and loads Flutter', async () => {
  const app = await start({isolated: true, controller, search: '?_haqor_coi_retry=1&reading=2'});
  assert.equal(app.history[0], 'https://machshev.github.io/haqor/?reading=2');
  assert.deepEqual(app.scripts, ['flutter_bootstrap.js']);
});
test('unsuccessful isolation retry stops without a reload loop or engine launch', async () => {
  const app = await start({controller, search: '?_haqor_coi_retry=1'});
  assert.equal(app.failures.length, 1);
  assert.equal(app.scripts.length, 0);
  assert.equal(app.navigations.length, 0);
});
test('browser without service workers reports the engine requirement', async () => {
  const app = await start({serviceWorkers: false});
  assert.match(app.failures[0][1], /service workers/);
  assert.equal(app.scripts.length, 0);
});
test('an update never reloads after the reader paints', async () => {
  const app = await start({isolated: true, controller});
  app.paint(); app.events.get('controllerchange')();
  assert.equal(app.navigations.length, 0);
});
