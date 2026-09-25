/**
 * Integration test: the judges' demo deployment (DEMO_MODE=1).
 * Every phone has its own line; a call placed through one line's link must
 * never reach, or be steerable by, a phone on another line.
 *
 * Run: node test/demo_lines.test.js
 */

const WebSocket = require('ws');
const assert = require('assert');

const PORT = 3198;
process.env.PORT = String(PORT);
process.env.DEMO_MODE = '1';
process.env.GATEWAY_AUTH_SECRET = '';
process.env.TAKE_MESSAGE_AFTER_MS = '600000';
// Placeholder so the run needs no .env; nothing here reaches AssemblyAI
process.env.ASSEMBLYAI_API_KEY = process.env.ASSEMBLYAI_API_KEY || 'test-key-never-used';
require('../server.js');

const HTTP = `http://127.0.0.1:${PORT}`;
const WS_URL = `ws://127.0.0.1:${PORT}`;
const sleep = (ms) => new Promise(r => setTimeout(r, ms));

function connect() {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(WS_URL);
    ws.received = [];
    ws.on('message', (d, isBinary) => { if (!isBinary) ws.received.push(JSON.parse(d)); });
    ws.on('open', () => resolve(ws));
    ws.on('error', reject);
  });
}
const ofType = (ws, type) => ws.received.filter(m => m.type === type);

async function phone(line) {
  const ws = await connect();
  ws.send(JSON.stringify({ type: 'REGISTER_MOBILE', ...(line !== undefined ? { line } : {}) }));
  return ws;
}

async function placeCall(line) {
  const res = await fetch(`${HTTP}/api/call`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(line !== undefined ? { line } : {}),
  });
  return { status: res.status, body: await res.json() };
}

async function run() {
  const health = await (await fetch(`${HTTP}/health`)).json();
  assert.strictEqual(health.demoMode, true, 'health reports demo mode');

  // Registration: a line code instead of the secret
  const phoneA = await phone('aaaaaa');       // lower case is accepted and normalised
  const phoneB = await phone('BBBBBB');
  const noLine = await phone();
  const badLine = await phone('abc');
  await sleep(200);
  assert.strictEqual(ofType(phoneA, 'REGISTERED_SUCCESS')[0]?.line, 'AAAAAA', 'phone A registered on its line');
  assert.strictEqual(ofType(phoneB, 'REGISTERED_SUCCESS')[0]?.demo, true, 'phone B told it is on the demo');
  assert.strictEqual(ofType(noLine, 'AUTH_FAILED').length, 1, 'no line code, no registration');
  assert.strictEqual(ofType(badLine, 'AUTH_FAILED').length, 1, 'malformed line code rejected');
  console.log('PASS: demo phones register with their own line code, no secret');

  // A call needs a line
  const orphan = await placeCall();
  assert.strictEqual(orphan.status, 400);
  assert.strictEqual(orphan.body.error, 'line_required');
  console.log('PASS: a demo call without a line is refused');

  // A call on line A rings only phone A
  const { body: { callId } } = await placeCall('AAAAAA');
  const caller = await connect();
  caller.send(JSON.stringify({ type: 'REGISTER_CALLER', callId }));
  await sleep(200);
  assert.ok(ofType(phoneA, 'INCOMING_CALL').some(m => m.callId === callId), 'phone A rings');
  assert.strictEqual(ofType(phoneB, 'INCOMING_CALL').length, 0, 'phone B does not');

  caller.send(JSON.stringify({ type: 'CALLER_DETAILS', name: 'Maria Lopez', reason: 'Design review' }));
  caller.send(JSON.stringify({ type: 'TRANSCRIPT_UPDATE', speaker: 'Caller', text: 'Hi, it is Maria.' }));
  await sleep(200);
  assert.strictEqual(ofType(phoneA, 'CALLER_DETAILS').length, 1, 'details reach phone A');
  assert.strictEqual(ofType(phoneA, 'TRANSCRIPT_UPDATE').length, 1, 'transcript reaches phone A');
  assert.strictEqual(ofType(phoneB, 'CALLER_DETAILS').length + ofType(phoneB, 'TRANSCRIPT_UPDATE').length, 0,
    'phone B sees nothing of it');
  console.log('PASS: a call reaches only the phone on its own line');

  // Phone B cannot steer, or start a secretary session for, phone A's call
  phoneB.send(JSON.stringify({ type: 'MASTER_DIRECTIVE', data: { callId, action: 'holding', directiveVersion: 1 } }));
  phoneB.send(JSON.stringify({ type: 'MASTER_SESSION_START', callId }));
  phoneB.send(JSON.stringify({ type: 'CALLER_CONTEXT', callId, relationship: 'Stranger' }));
  await sleep(200);
  assert.ok(ofType(phoneB, 'DIRECTIVE_FAILED').some(m => m.reason === 'unknown_call'), 'foreign directive refused');
  assert.ok(ofType(phoneB, 'MASTER_SESSION_STATE').some(m => m.error === 'call_not_active'), 'foreign session refused');
  assert.strictEqual(ofType(caller, 'DIRECTIVE_UPDATED').length, 0, 'the caller heard nothing from phone B');

  phoneA.send(JSON.stringify({ type: 'MASTER_DIRECTIVE', data: { callId, action: 'holding', directiveVersion: 2 } }));
  await sleep(200);
  assert.strictEqual(ofType(caller, 'DIRECTIVE_UPDATED').length, 1, 'phone A steers its own call');
  console.log('PASS: another line cannot steer, brief or annotate the call');

  // Post-call analysis: only for a line that is registered right now
  const analyze = await fetch(`${HTTP}/api/analyze-call`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'X-Awaaz-Line': 'ZZZZZZ' },
    body: JSON.stringify({ transcript: [] }),
  });
  assert.strictEqual(analyze.status, 401, 'an unregistered line cannot use the analysis endpoint');
  console.log('PASS: analysis needs a registered line');

  // Hang-up and missed calls stay on their line
  caller.close();
  await sleep(250);
  assert.ok(ofType(phoneA, 'CALLER_HUNG_UP').some(m => m.callId === callId), 'hang-up reaches phone A');
  assert.strictEqual(ofType(phoneB, 'CALLER_HUNG_UP').length, 0, 'not phone B');

  phoneB.send(JSON.stringify({ type: 'CALL_LOGGED', callId }));   // must not mark A's call
  phoneB.send(JSON.stringify({ type: 'SYNC_MISSED_CALLS' }));
  await sleep(150);
  const bMissed = ofType(phoneB, 'MISSED_CALLS').flatMap(m => m.calls);
  assert.ok(!bMissed.some(c => c.callId === callId), 'phone B never sees A\'s missed call');

  const phoneA2 = await phone('AAAAAA');   // A reconnects, e.g. after the app restarts
  await sleep(200);
  const aMissed = ofType(phoneA2, 'MISSED_CALLS').flatMap(m => m.calls);
  const record = aMissed.find(c => c.callId === callId);
  assert.ok(record, 'the missed call is waiting for line A');
  assert.strictEqual(record.line, undefined, 'internal line field is not sent');
  console.log('PASS: hang-ups and missed calls stay on their line');

  // The owner page: any browser can take the calls for its own line
  const owner = await fetch(`${HTTP}/owner`);
  const ownerHtml = await owner.text();
  assert.strictEqual(owner.status, 200, 'the owner page is served');
  assert.match(owner.headers.get('content-type') || '', /text\/html/);
  assert.ok(ownerHtml.includes('Take your calls') && ownerHtml.includes("type: 'REGISTER_MOBILE', line: S.line"),
    'the owner page registers with a line code on a demo deployment');
  assert.ok(!/OWNER_SETTINGS[^\n]*S\.mode !== 'demo'/.test(ownerHtml) && ownerHtml.includes("if (S.mode !== 'demo' || !S.registered) return;"),
    'the owner page sends settings only on a demo line, so it never overwrites the phone app\'s');
  console.log('PASS: the owner page is served and keeps to its own line');

  console.log('ALL DEMO LINE CHECKS PASSED');
  process.exit(0);
}

run().catch((e) => {
  console.error('Demo line test failed:', e);
  process.exit(1);
});
