/**
 * Integration Test: gateway call routing, directive isolation and socket roles.
 * Starts sidekick_server/server.js on a test port with its own secret.
 *
 * Run: node test/concurrent_routing.test.js
 */

const WebSocket = require('ws');
const assert = require('assert');

const PORT = 3199;
const SECRET = 'test-secret-for-routing-test';
process.env.PORT = String(PORT);
process.env.GATEWAY_AUTH_SECRET = SECRET;
process.env.TAKE_MESSAGE_AFTER_MS = '1000';
// A placeholder key, so the run does not depend on a local .env. No test here
// reaches AssemblyAI: sessions are only started for calls the server refuses.
process.env.ASSEMBLYAI_API_KEY = process.env.ASSEMBLYAI_API_KEY || 'test-key-never-used';
const { spokenDigits } = require('../server.js');

// Spoken phone numbers become digits; ordinary text is left alone
assert.strictEqual(spokenDigits('zero three zero zero one two three four five six seven'), '03001234567');
assert.strictEqual(spokenDigits('oh three double one, four five'), '031145');
assert.strictEqual(spokenDigits('call me tomorrow after five'), 'call me tomorrow after five');
console.log('PASS: spoken call-back numbers become digits');

const HTTP = `http://127.0.0.1:${PORT}`;
const WS_URL = `ws://127.0.0.1:${PORT}`;

const sleep = (ms) => new Promise(r => setTimeout(r, ms));

// Opens a socket that records every message it receives
function connect() {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(WS_URL);
    ws.received = [];
    ws.audio = [];
    ws.on('message', (d, isBinary) => {
      if (isBinary) ws.audio.push(Buffer.from(d));
      else ws.received.push(JSON.parse(d));
    });
    ws.on('open', () => resolve(ws));
    ws.on('error', reject);
  });
}

const ofType = (ws, type) => ws.received.filter(m => m.type === type);

async function registerCall(name) {
  const res = await fetch(`${HTTP}/api/call`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ callerName: name, topic: `Topic ${name}` }),
  });
  assert.strictEqual(res.status, 200);
  return (await res.json()).callId;
}

function directive(ws, callId, version) {
  ws.send(JSON.stringify({
    type: 'MASTER_DIRECTIVE',
    data: { callId, action: 'holding', spokenDirective: 'hold please', directiveVersion: version },
  }));
}

async function runTest() {
  // Phones: one with the right secret, one with none, one with a wrong one
  const mobile = await connect();
  mobile.send(JSON.stringify({ type: 'REGISTER_MOBILE', authSecret: SECRET }));
  const noSecret = await connect();
  noSecret.send(JSON.stringify({ type: 'REGISTER_MOBILE' }));
  const wrongSecret = await connect();
  wrongSecret.send(JSON.stringify({ type: 'REGISTER_MOBILE', authSecret: 'guess' }));
  await sleep(200);

  assert.strictEqual(ofType(mobile, 'REGISTERED_SUCCESS').length, 1, 'correct secret registers');
  assert.strictEqual(ofType(noSecret, 'AUTH_FAILED').length, 1, 'missing secret is rejected');
  assert.strictEqual(ofType(wrongSecret, 'AUTH_FAILED').length, 1, 'wrong secret is rejected');
  console.log('PASS: mobile registration requires the gateway secret');

  // Two concurrent calls
  const callIdA = await registerCall('Caller A');
  const callIdB = await registerCall('Caller B');
  assert.notStrictEqual(callIdA, callIdB);
  assert.match(callIdA, /^call_[0-9a-f-]{36}$/, 'callIds are random UUIDs');

  const callerA = await connect();
  callerA.send(JSON.stringify({ type: 'REGISTER_CALLER', callId: callIdA }));
  const callerB = await connect();
  callerB.send(JSON.stringify({ type: 'REGISTER_CALLER', callId: callIdB }));
  const hijacker = await connect();
  hijacker.send(JSON.stringify({ type: 'REGISTER_CALLER', callId: callIdA }));
  const bogus = await connect();
  bogus.send(JSON.stringify({ type: 'REGISTER_CALLER', callId: 'call_made_up' }));
  await sleep(200);

  assert.strictEqual(ofType(hijacker, 'CALLER_REGISTER_FAILED').length, 1, 'a live call cannot be claimed twice');
  assert.strictEqual(ofType(bogus, 'CALLER_REGISTER_FAILED').length, 1, 'unknown callIds are rejected');
  console.log('PASS: caller sockets cannot hijack or invent calls');

  // Directive to A reaches only A
  directive(mobile, callIdA, 1);
  await sleep(200);
  assert.strictEqual(ofType(callerA, 'DIRECTIVE_UPDATED').length, 1, 'caller A receives its directive');
  assert.strictEqual(ofType(callerA, 'DIRECTIVE_UPDATED')[0].data.callId, callIdA);
  assert.strictEqual(ofType(callerB, 'DIRECTIVE_UPDATED').length, 0, 'caller B does not');
  console.log('PASS: directives are routed only to the owning caller');

  // Directives from non-phone sockets are ignored
  directive(callerB, callIdA, 2);
  directive(hijacker, callIdA, 3);
  await sleep(200);
  assert.strictEqual(ofType(callerA, 'DIRECTIVE_UPDATED').length, 1, 'no extra directives reached caller A');
  console.log('PASS: only an authenticated phone can send directives');

  // Caller B's transcript reaches the phone tagged with B's callId, even if it lies
  callerB.send(JSON.stringify({ type: 'TRANSCRIPT_UPDATE', callId: callIdA, speaker: 'Caller', text: 'from B' }));
  hijacker.send(JSON.stringify({ type: 'TRANSCRIPT_UPDATE', callId: callIdA, speaker: 'Caller', text: 'fake' }));
  await sleep(200);
  const transcripts = ofType(mobile, 'TRANSCRIPT_UPDATE');
  assert.strictEqual(transcripts.length, 1, 'only the registered caller can send transcripts');
  assert.strictEqual(transcripts[0].callId, callIdB, 'transcript is tagged with the sender\'s own call');
  assert.strictEqual(transcripts[0].text, 'from B');
  assert.strictEqual(ofType(noSecret, 'TRANSCRIPT_UPDATE').length, 0, 'unauthenticated phones get nothing');
  console.log('PASS: transcripts are attributed to the sending caller only');

  // Caller details: only the call's own caller page can set them; phones get them
  callerA.send(JSON.stringify({ type: 'CALLER_DETAILS', name: 'Maria Lopez', company: 'Brightline', reason: 'Design review', urgent: false }));
  hijacker.send(JSON.stringify({ type: 'CALLER_DETAILS', callId: callIdA, name: 'Mallory' }));
  mobile.send(JSON.stringify({ type: 'CALLER_DETAILS', callId: callIdA, name: 'Mallory' }));
  await sleep(200);
  const detailMsgs = ofType(mobile, 'CALLER_DETAILS');
  assert.strictEqual(detailMsgs.length, 1, 'only the caller page can record details');
  assert.strictEqual(detailMsgs[0].callId, callIdA);
  assert.strictEqual(detailMsgs[0].name, 'Maria Lopez');
  callerA.send(JSON.stringify({ type: 'CALLER_DETAILS', name: '', reason: 'Design review on Friday', urgent: true }));
  await sleep(200);
  const merged = ofType(mobile, 'CALLER_DETAILS').at(-1);
  assert.strictEqual(merged.name, 'Maria Lopez', 'an empty field does not erase what was recorded');
  assert.strictEqual(merged.reason, 'Design review on Friday');
  assert.strictEqual(merged.urgent, true);
  console.log('PASS: caller details are recorded only by the caller page and merged');

  // A reconnecting phone is told about calls still in progress
  const lateMobile = await connect();
  lateMobile.send(JSON.stringify({ type: 'REGISTER_MOBILE', authSecret: SECRET }));
  await sleep(200);
  const replayed = ofType(lateMobile, 'INCOMING_CALL').map(m => m.callId).sort();
  assert.deepStrictEqual(replayed, [callIdA, callIdB].sort(), 'active calls are replayed on registration');
  const replayA = ofType(lateMobile, 'INCOMING_CALL').find(m => m.callId === callIdA);
  assert.strictEqual(replayA.details.name, 'Maria Lopez', 'the replay carries the recorded details');
  console.log('PASS: active calls are replayed to a reconnecting phone');

  // Kabeer's secretary session: only an authenticated phone, only for a live call
  callerB.send(JSON.stringify({ type: 'MASTER_SESSION_START', callId: callIdB }));
  hijacker.send(JSON.stringify({ type: 'MASTER_SESSION_START', callId: callIdB }));
  mobile.send(JSON.stringify({ type: 'MASTER_SESSION_START', callId: 'call_made_up' }));
  await sleep(200);
  assert.strictEqual(ofType(callerB, 'MASTER_SESSION_STATE').length + ofType(hijacker, 'MASTER_SESSION_STATE').length, 0,
    'non-phone sockets cannot start a secretary session');
  assert.ok(ofType(mobile, 'MASTER_SESSION_STATE').some(m => m.state === 'error' && m.error === 'call_not_active'),
    'a session for an unknown call is refused');
  console.log('PASS: secretary sessions are limited to authenticated phones and live calls');

  // Patch In on call B: audio flows both ways only after the caller page is ready
  mobile.send(JSON.stringify({
    type: 'MASTER_DIRECTIVE',
    data: { callId: callIdB, action: 'patchedToMaster', directiveVersion: 5 },
  }));
  await sleep(100);
  callerB.send(Buffer.from([1, 2, 3, 4]));          // before BRIDGE_READY: dropped
  await sleep(100);
  assert.strictEqual(lateMobile.audio.length + mobile.audio.length, 0, 'no audio before the bridge is ready');

  callerB.send(JSON.stringify({ type: 'BRIDGE_READY', callId: callIdB }));
  await sleep(150);
  assert.strictEqual(ofType(mobile, 'BRIDGE_CONNECTED').length, 1, 'patching phone is told the bridge is live');
  assert.strictEqual(ofType(lateMobile, 'BRIDGE_CONNECTED').length, 0, 'other phones are not');

  callerB.send(Buffer.from([10, 20, 30, 40]));
  mobile.send(Buffer.from([50, 60, 70, 80]));
  callerA.send(Buffer.from([99, 99]));               // A is not bridged
  hijacker.send(Buffer.from([66, 66]));              // not a caller at all
  await sleep(200);
  assert.deepStrictEqual(mobile.audio.map(b => [...b]), [[10, 20, 30, 40]], 'phone hears only caller B');
  assert.deepStrictEqual(callerB.audio.map(b => [...b]), [[50, 60, 70, 80]], 'caller B hears the phone');
  assert.strictEqual(callerA.audio.length + lateMobile.audio.length, 0, 'audio reaches no one else');
  console.log('PASS: Patch In relays audio only between the caller and the patching phone');

  // Kabeer hangs up from the phone
  mobile.send(JSON.stringify({
    type: 'MASTER_DIRECTIVE',
    data: { callId: callIdB, action: 'hangup', directiveVersion: 6 },
  }));
  await sleep(150);
  assert.ok(ofType(callerB, 'DIRECTIVE_UPDATED').some(m => m.data.action === 'hangup'), 'caller page is told to hang up');

  // If the phone drops mid-bridge, the caller is told instead of hearing silence
  mobile.close();
  await sleep(200);
  assert.strictEqual(ofType(callerB, 'BRIDGE_ENDED').length, 1, 'caller learns the phone left');
  console.log('PASS: hang-up and phone disconnect end the bridge for the caller');

  // Hang-up is reported and the call is forgotten
  callerA.close();
  await sleep(200);
  assert.ok(ofType(lateMobile, 'CALLER_HUNG_UP').some(m => m.callId === callIdA), 'hang-up reaches the phone');
  directive(lateMobile, callIdA, 4);
  await sleep(200);
  assert.ok(ofType(lateMobile, 'DIRECTIVE_FAILED').some(m => m.callId === callIdA && m.reason === 'unknown_call'),
    'directives to an ended call fail');
  console.log('PASS: ended calls are cleaned up');

  // Nobody acts on call C: the secretary is told to take a message
  const callIdC = await registerCall('Caller C');
  const callerC = await connect();
  callerC.send(JSON.stringify({ type: 'REGISTER_CALLER', callId: callIdC }));
  await sleep(1400);
  assert.strictEqual(ofType(callerC, 'TAKE_MESSAGE').length, 1, 'an unattended call triggers message-taking');
  assert.strictEqual(ofType(callerC, 'TAKE_MESSAGE')[0].reason, 'unavailable', 'Kabeer is not on another call');
  assert.ok(ofType(lateMobile, 'TAKING_MESSAGE').some(m => m.callId === callIdC), 'the phone is told');
  assert.strictEqual(ofType(callerA, 'TAKE_MESSAGE').length, 0, 'a call Kabeer acted on is left alone');
  callerC.send(JSON.stringify({
    type: 'CALLER_DETAILS', name: 'Sam Reed', message: 'Please call about the lease', callback: '0300 1234567', urgent: false,
  }));
  await sleep(100);
  callerC.close();
  await sleep(200);
  console.log('PASS: unattended calls get a message taken');

  // A phone connecting later learns about the calls nobody logged
  const nextMobile = await connect();
  nextMobile.send(JSON.stringify({ type: 'REGISTER_MOBILE', authSecret: SECRET }));
  await sleep(200);
  const missed = ofType(nextMobile, 'MISSED_CALLS')[0];
  assert.ok(missed, 'missed calls are sent on registration');
  const missedC = missed.calls.find(c => c.callId === callIdC);
  assert.ok(missedC, 'the unlogged call is included');
  assert.strictEqual(missedC.details.message, 'Please call about the lease');
  assert.strictEqual(missedC.details.callback, '0300 1234567');
  assert.strictEqual(missedC.tookMessage, true);

  // A phone can ask again at any time (a waiting caller hung up); callers can't
  const beforeSync = ofType(nextMobile, 'MISSED_CALLS').length;
  nextMobile.send(JSON.stringify({ type: 'SYNC_MISSED_CALLS' }));
  callerB.send(JSON.stringify({ type: 'SYNC_MISSED_CALLS' }));
  await sleep(150);
  assert.strictEqual(ofType(nextMobile, 'MISSED_CALLS').length, beforeSync + 1, 'the phone gets the list again');
  assert.strictEqual(ofType(callerB, 'MISSED_CALLS').length, 0, 'a caller socket gets nothing');

  // Only a phone can confirm; once confirmed the call isn't offered again
  callerB.send(JSON.stringify({ type: 'CALL_LOGGED', callId: callIdC }));
  nextMobile.send(JSON.stringify({ type: 'CALL_LOGGED', callId: callIdC }));
  await sleep(150);
  const laterMobile = await connect();
  laterMobile.send(JSON.stringify({ type: 'REGISTER_MOBILE', authSecret: SECRET }));
  await sleep(200);
  const stillMissed = (ofType(laterMobile, 'MISSED_CALLS')[0]?.calls || []).map(c => c.callId);
  assert.ok(!stillMissed.includes(callIdC), 'a logged call is not offered again');
  assert.ok(stillMissed.includes(callIdA), 'other unlogged calls still are');
  console.log('PASS: missed calls reach the phone until it confirms logging them');

  console.log('ALL ROUTING AND ROLE CHECKS PASSED');
  process.exit(0);
}

runTest().catch((err) => {
  console.error('Integration Test Failed:', err);
  process.exit(1);
});
