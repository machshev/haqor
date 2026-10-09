// Run after tool/build-web.sh. Node 22+ and Chrome/Chromium are required.
// A disposable profile exercises the service worker at the deployed /haqor/ path.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdtemp, readFile, rm} from 'node:fs/promises';
import {createServer} from 'node:http';
import {tmpdir} from 'node:os';
import {extname, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root = fileURLToPath(new URL('../build/web/', import.meta.url));
const manifest = await readFile(new URL('../pubspec.yaml', import.meta.url), 'utf8');
const version = manifest.match(/^version: (\S+)$/m)[1];
const types = {'.html': 'text/html', '.js': 'text/javascript',
  '.mjs': 'text/javascript', '.wasm': 'application/wasm', '.json': 'application/json'};
const server = createServer(async (request, response) => {
  const pathname = new URL(request.url, 'http://localhost').pathname;
  const path = resolve(root, `.${pathname.replace(/^\/haqor/, '')}`, pathname.endsWith('/') ? 'index.html' : '');
  if (!path.startsWith(root)) {response.writeHead(404).end(); return;}
  try {
    const bytes = await readFile(path);
    response.writeHead(200, {'Content-Type': types[extname(path)] ?? 'application/octet-stream'});
    response.end(bytes);
  } catch {response.writeHead(404).end();}
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const dart2js = process.argv.includes('--dart2js');
const profile = await mkdtemp(join(tmpdir(), 'haqor-web-test-'));
const chrome = spawn(process.env.CHROME_EXECUTABLE ?? 'google-chrome', [
  '--headless=new', '--disable-gpu', '--no-sandbox', '--remote-debugging-port=0',
  `--user-data-dir=${profile}`, 'about:blank',
], {stdio: ['ignore', 'ignore', 'pipe']});
let ws;
const deadline = setTimeout(() => {console.error('Web runtime test timed out'); chrome.kill();}, 90000);
try {
  let log = '';
  const endpoint = await new Promise((resolve, reject) => {
    chrome.stderr.on('data', bytes => {
      log += bytes;
      const match = log.match(/DevTools listening on (ws:\/\/\S+)/);
      if (match) resolve(match[1]);
    });
    chrome.on('error', reject);
    chrome.on('exit', code => reject(new Error(`Chrome exited ${code}: ${log}`)));
  });
  ws = new WebSocket(endpoint);
  await new Promise(resolve => ws.addEventListener('open', resolve, {once: true}));
  let next = 0;
  const pending = new Map();
  const exceptions = [];
  const consoleMessages = [];
  ws.addEventListener('message', event => {
    const message = JSON.parse(event.data);
    if (message.method === 'Runtime.consoleAPICalled') consoleMessages.push(message.params.args.map(arg => arg.value ?? arg.description ?? '').join(' '));
    if (message.method === 'Runtime.exceptionThrown') exceptions.push(message.params.exceptionDetails);
    if (!message.id) return;
    const promise = pending.get(message.id);
    pending.delete(message.id);
    message.error ? promise.reject(message.error) : promise.resolve(message.result);
  });
  ws.addEventListener('close', () => {
    for (const promise of pending.values()) promise.reject(new Error('Browser disconnected'));
  });
  const call = (method, params = {}, sessionId) => new Promise((resolve, reject) => {
    const id = ++next;
    pending.set(id, {resolve, reject});
    ws.send(JSON.stringify({id, method, params, sessionId}));
  });
  const {targetId} = await call('Target.createTarget', {url: 'about:blank'});
  const {sessionId} = await call('Target.attachToTarget', {targetId, flatten: true});
  const send = (method, params) => call(method, params, sessionId);
  const evaluate = async expression => {
    const result = await send('Runtime.evaluate', {expression, returnByValue: true, awaitPromise: true});
    assert.equal(result.exceptionDetails, undefined, JSON.stringify(result.exceptionDetails));
    return result.result.value;
  };
  const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
  await send('Page.enable');
  await send('Emulation.setDeviceMetricsOverride', {width: 1280, height: 1000, deviceScaleFactor: 1, mobile: false});
  await send('Runtime.enable');
  await send('Page.addScriptToEvaluateOnNewDocument', {source: `
    document.addEventListener('DOMContentLoaded', () => {
      window.haqorLoadingVersion = document.getElementById('haqor-boot-version')?.innerText;
    });
  `});
  await send('Page.navigate', {url: `http://127.0.0.1:${server.address().port}/haqor/?test-service-worker${dart2js ? '&test-dart2js' : ''}`});
  for (let i = 0; i < 60; i++) {
    if (await evaluate('window.haqorBoot?.isDone() === true')) break;
    await pause(1000);
  }
  assert.equal(await evaluate('window.haqorBoot?.isDone() === true'), true, 'App did not paint');
  assert.equal(await evaluate('crossOriginIsolated'), true);
  assert.equal(await evaluate('haqorLoadingVersion'), `Haqor ${version}`);
  assert.equal(await evaluate('new URL(location.href).searchParams.has("_haqor_coi_retry")'), false);
  await evaluate(`(() => {
    window.haqorReplies = [];
    const original = rinfBindings.rinf_send_rust_signal_extern;
    rinfBindings.rinf_send_rust_signal_extern = (endpoint, message, binary) => {
      haqorReplies.push({endpoint, bytes: Array.from(message)});
      original(endpoint, message, binary);
    };
  })()`);
  for (const [request, message, expected] of [
    ['get_verse_text', [1, 1, 1, 0], 'VerseText'],
    ['get_cross_references', [1, 1, 1, 0, 0, 0, 0], 'CrossReferences'],
    ['get_memory_passages', [], 'MemoryPassages'],
    ['get_memory_stats', [0, 0, 0, 0, 0, 0, 0, 0], 'MemoryStats'],
    ['get_next_study_item', [], 'StudyItem'],
    ['get_tutor_stats', [], 'TutorStats'],
    ['get_verse_text', [1, 1, 2, 0], 'VerseText'],
  ]) {
    await evaluate(`window.haqorReplies = []; import('./pkg/hub.js').then(module =>
      module.rinf_send_dart_signal_${request}(new Uint8Array(${JSON.stringify(message)}), new Uint8Array(0)))`);
    let replies;
    for (let i = 0; i < 300; i++) {
      replies = await evaluate('haqorReplies');
      if (replies.some(reply => reply.endpoint === expected || reply.endpoint === 'RequestFailed')) break;
      await pause(100);
    }
    assert.ok(replies.some(reply => reply.endpoint === expected), `${request}: ${JSON.stringify(replies)}`);
    console.log(`${request}: ${expected}`);
  }
  if (dart2js) {
    assert.equal(await evaluate("performance.getEntriesByType('resource').some(entry => entry.name.endsWith('/main.dart.js'))"), true, 'JavaScript fallback was not loaded');
  }
  await evaluate("document.querySelector('flt-semantics-placeholder')?.click()");
  // A button by its label, or with `prefix`, by how its label starts: a card
  // reads its title and description as one.
  const click = async (label, {prefix = false} = {}) => {
    for (let i = 0; i < 100; i++) {
      if (await evaluate(`(() => {
        const matches = text => text != null && (${prefix} ? text.startsWith(${JSON.stringify(label)}) : text === ${JSON.stringify(label)});
        const button = [...document.querySelectorAll('[role="button"]')].find(element =>
          matches(element.getAttribute('aria-label')) || matches(element.textContent));
        if (!button) return false;
        button.click(); return true;
      })()`)) return;
      await pause(100);
    }
    throw new Error(`Button not found: ${label}`);
  };
  const waitForText = async text => {
    for (let i = 0; i < 300; i++) {
      if (await evaluate(`document.querySelector('flt-semantics-host')?.textContent.includes(${JSON.stringify(text)}) === true`)) return;
      await pause(100);
    }
    throw new Error(`Screen text not found: ${text}: ${await evaluate("document.querySelector(\'flt-semantics-host\')?.textContent")}`);
  };
  // A fresh install opens on the welcome question; keep the defaults.
  await waitForText('How familiar are you with Hebrew?');
  await click('Reading Hebrew', {prefix: true});
  await click('Memorise');
  await waitForText('Choose a passage');
  await click('Back');
  await click('Tutor');
  await waitForText('Before you start');
  await click("No, I'm starting from scratch");
  await waitForText('Learn to read');
  await waitForText('Continue');
  await waitForText('Before we start');
  console.log('Memorise and Tutor screens rendered.');
  assert.deepEqual(exceptions, [], 'Uncaught WASM/browser exceptions');
  assert.ok(!consoleMessages.some(message => /Unsupported operation|Another exception was thrown|EXCEPTION CAUGHT/.test(message)), consoleMessages.join('\n'));
  console.log('Release web startup, references, passages and tutor passed.');
} finally {
  clearTimeout(deadline);
  ws?.close();
  chrome.kill();
  await new Promise(resolve => server.close(resolve));
  await rm(profile, {recursive: true, force: true, maxRetries: 5, retryDelay: 100});
}
