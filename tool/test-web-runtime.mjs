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
  ws.addEventListener('message', event => {
    const message = JSON.parse(event.data);
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
  await send('Runtime.enable');
  await send('Page.navigate', {url: `http://127.0.0.1:${server.address().port}/haqor/?test-service-worker`});
  for (let i = 0; i < 60; i++) {
    if (await evaluate('window.haqorBoot?.isDone() === true')) break;
    await pause(1000);
  }
  assert.equal(await evaluate('window.haqorBoot?.isDone() === true'), true, 'App did not paint');
  assert.equal(await evaluate('crossOriginIsolated'), true);
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
  assert.deepEqual(exceptions, [], 'Uncaught WASM/browser exceptions');
  console.log('Release web startup, references, passages and tutor passed.');
} finally {
  clearTimeout(deadline);
  ws?.close();
  chrome.kill();
  await new Promise(resolve => server.close(resolve));
  await rm(profile, {recursive: true, force: true, maxRetries: 5, retryDelay: 100});
}
