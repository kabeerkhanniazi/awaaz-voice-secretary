/**
 * Integration test: what the phone tells the gateway about its owner.
 * Personal links verify a caller, blocked browsers are refused, and when Kabeer
 * is away the secretary takes a message straight after the greeting.
 *
 * Run: node test/owner_settings.test.js
 */

const WebSocket = require('ws');
const assert = require('assert');

const PORT = 3197;
const SECRET = 'test-secret-for-owner-settings';
process.env.PORT = String(PORT);
process.env.GATEWAY_AUTH_SECRET = SECRET;
process.env.TAKE_MESSAGE_AFTER_MS = '600000';
process.env.QUIET_TAKE_MESSAGE_MS = '300';
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

async function placeCall(body) {
  const res = await fetch(`${HTTP}/api/call`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  return { status: res.status, body: await res.json() };
}

async function answer(callId) {
  const caller = await connect();
  caller.send(JSON.stringify({ type: 'REGISTER_CALLER', callId }));
  return caller;
}

const MARIA = 'MARIALINK7Q2';
const MOM = 'MOMLINKK9X4P';
const PEST = 'PESTLINK3C8W';
const BLOCKED_BROWSER = 'browser-blocked-0001';
const NEW_BROWSER = 'browser-fresh-0002';

async function run() {
  const phone = await connect();
  phone.send(JSON.stringify({ type: 'REGISTER_MOBILE', authSecret: SECRET }));
  await sleep(150);
  phone.send(JSON.stringify({
    type: 'OWNER_SETTINGS',
    availability: { mode: 'available' },
    links: [
      { token: MARIA, name: 'Maria Lopez' },
      { token: MOM, name: 'Ammi', alwaysRing: true },
      { token: PEST, name: 'Old Landlord', neverRing: true },
      { token: 'bad token!', name: 'Ignored' },
    ],
    blockedDevices: [BLOCKED_BROWSER, 'x'],
  }));
  await sleep(150);

  // Only the phone may set these: a caller socket trying to unblock itself is ignored
  const sneaky = await connect();
  sneaky.send(JSON.stringify({ type: 'OWNER_SETTINGS', blockedDevices: [] }));
  await sleep(100);

  // A blocked browser is refused before anything rings
  const refused = await placeCall({ device: BLOCKED_BROWSER });
  assert.strictEqual(refused.status, 403);
  assert.strictEqual(refused.body.error, 'unavailable');
  assert.strictEqual(ofType(phone, 'INCOMING_CALL').length, 0, 'nothing rang for the blocked browser');
  console.log('PASS: a blocked browser cannot call, and callers cannot unblock themselves');

  // A personal link verifies the caller, by the name Kabeer gave that link
  const viaLink = await placeCall({ device: NEW_BROWSER, from: MARIA.toLowerCase() });
  assert.strictEqual(viaLink.body.verifiedName, 'Maria Lopez', 'the caller page learns who the link is for');
  await sleep(150);
  const ring = ofType(phone, 'INCOMING_CALL').find(m => m.callId === viaLink.body.callId);
  assert.deepStrictEqual(ring.verified, { name: 'Maria Lopez', via: 'link', token: MARIA });
  assert.strictEqual(ring.device, NEW_BROWSER, 'the phone gets the browser id to spot a new device');
  assert.strictEqual(ring.quiet, undefined, 'an ordinary verified call rings');

  // Anything else is unverified; an unknown or revoked link is flagged
  const plain = await placeCall({ device: NEW_BROWSER });
  const stale = await placeCall({ device: NEW_BROWSER, from: 'REVOKED00000' });
  await sleep(150);
  const plainRing = ofType(phone, 'INCOMING_CALL').find(m => m.callId === plain.body.callId);
  const staleRing = ofType(phone, 'INCOMING_CALL').find(m => m.callId === stale.body.callId);
  assert.strictEqual(plainRing.verified, undefined, 'no link, no verification');
  assert.strictEqual(plainRing.phoneNumber, '', 'no made-up phone number');
  assert.strictEqual(staleRing.verified, undefined);
  assert.strictEqual(staleRing.staleLink, true, 'a link that matches nobody is flagged');
  console.log('PASS: personal links verify callers; claims and stale links do not');

  // Contact details come through clean
  const caller = await answer(plain.body.callId);
  await sleep(100);
  caller.send(JSON.stringify({
    type: 'CALLER_DETAILS',
    name: 'Ali', callbackNumber: 'zero three zero zero one two three four five six seven',
    callbackEmail: 'Ali at Gmail dot com', bestTime: 'weekdays after 5 pm',
  }));
  await sleep(150);
  const details = ofType(phone, 'CALLER_DETAILS').at(-1);
  assert.strictEqual(details.callbackNumber, '03001234567');
  assert.strictEqual(details.callbackEmail, 'ali@gmail.com');
  assert.strictEqual(details.bestTime, 'weekdays after 5 pm');
  caller.send(JSON.stringify({ type: 'CALLER_DETAILS', callbackNumber: 'call me', callbackEmail: 'not an email' }));
  await sleep(150);
  const kept = ofType(phone, 'CALLER_DETAILS').at(-1) || details;
  assert.strictEqual(kept.callbackNumber, '03001234567', 'garbage does not overwrite a confirmed number');
  console.log('PASS: call-back number, email and best time are recorded cleanly');

  // Away: the secretary takes a message straight after the greeting...
  phone.send(JSON.stringify({
    type: 'OWNER_SETTINGS',
    availability: { mode: 'busy', until: new Date(Date.now() + 3600e3).toISOString(), untilLabel: '3:00 PM', note: 'in a meeting' },
    links: [{ token: MOM, name: 'Ammi', alwaysRing: true }, { token: PEST, name: 'Old Landlord', neverRing: true }],
    blockedDevices: [],
  }));
  await sleep(150);
  const awayCall = await placeCall({ device: NEW_BROWSER });
  await sleep(100);
  const awayCaller = await answer(awayCall.body.callId);
  await sleep(700);
  const awayRing = ofType(phone, 'INCOMING_CALL').find(m => m.callId === awayCall.body.callId);
  assert.strictEqual(awayRing.quiet, 'away', 'the phone is told not to ring');
  const take = ofType(awayCaller, 'TAKE_MESSAGE')[0];
  assert.ok(take, 'message-taking starts right away');
  assert.strictEqual(take.reason, 'away');
  assert.strictEqual(take.untilLabel, '3:00 PM');
  assert.strictEqual(take.note, 'in a meeting');

  // ...unless it is a verified "always ring" contact
  const mom = await placeCall({ device: NEW_BROWSER, from: MOM });
  const momCaller = await answer(mom.body.callId);
  await sleep(700);
  assert.strictEqual(ofType(phone, 'INCOMING_CALL').find(m => m.callId === mom.body.callId).quiet, undefined);
  assert.strictEqual(ofType(momCaller, 'TAKE_MESSAGE').length, 0, 'always-ring contacts still reach Kabeer');

  // A "never ring" contact always gets the secretary, even when Kabeer is free
  phone.send(JSON.stringify({ type: 'OWNER_SETTINGS', availability: { mode: 'available' }, links: [{ token: PEST, name: 'Old Landlord', neverRing: true }] }));
  await sleep(150);
  const pest = await placeCall({ device: NEW_BROWSER, from: PEST });
  const pestCaller = await answer(pest.body.callId);
  await sleep(700);
  assert.strictEqual(ofType(phone, 'INCOMING_CALL').find(m => m.callId === pest.body.callId).quiet, 'unavailable');
  assert.strictEqual(ofType(pestCaller, 'TAKE_MESSAGE')[0]?.reason, 'unavailable');

  // Once "busy until" has passed, calls ring again
  phone.send(JSON.stringify({ type: 'OWNER_SETTINGS', availability: { mode: 'busy', until: new Date(Date.now() - 1000).toISOString() } }));
  await sleep(150);
  const later = await placeCall({ device: NEW_BROWSER });
  await sleep(150);
  assert.strictEqual(ofType(phone, 'INCOMING_CALL').find(m => m.callId === later.body.callId).quiet, undefined);
  console.log('PASS: availability, always-ring and never-ring decide who gets through');

  console.log('ALL OWNER SETTINGS CHECKS PASSED');
  process.exit(0);
}

run().catch((e) => {
  console.error('Owner settings test failed:', e);
  process.exit(1);
});
