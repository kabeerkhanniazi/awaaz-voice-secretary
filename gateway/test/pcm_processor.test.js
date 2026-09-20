/**
 * Unit test for sidekick_server/web/pcm-processor.js (the caller's mic AudioWorklet).
 * The fake port transfers buffers like a real MessagePort does, which detaches them.
 *
 * Run: node test/pcm_processor.test.js [path-to-processor]
 */

const fs = require('fs');
const path = require('path');
const assert = require('assert');

const file = process.argv[2] || path.join(__dirname, '..', 'web', 'pcm-processor.js');
const source = fs.readFileSync(file, 'utf8');

function loadProcessor(deviceRate) {
  let Processor;
  const posted = [];
  class FakeWorkletProcessor {
    constructor() {
      this.port = {
        postMessage: (buffer, transfer) => {
          // Real postMessage with a transfer list detaches the sender's buffer
          posted.push(new Int16Array(structuredClone(buffer, { transfer })));
        },
      };
    }
  }
  new Function('sampleRate', 'AudioWorkletProcessor', 'registerProcessor', source)(
    deviceRate, FakeWorkletProcessor, (_, cls) => { Processor = cls; });
  const processor = new Processor({
    processorOptions: { inputSampleRate: deviceRate, targetSampleRate: 24000, chunkSamples: 1200 },
  });
  return { processor, posted };
}

for (const rate of [48000, 44100, 16000]) {
  const { processor, posted } = loadProcessor(rate);
  // 10 s of a 440 Hz tone in 128-frame render quanta
  const total = rate * 10;
  for (let t = 0; t < total;) {
    const block = new Float32Array(128);
    for (let i = 0; i < 128; i++, t++) block[i] = 0.5 * Math.sin(2 * Math.PI * 440 * t / rate);
    processor.process([[block]]);
  }

  const samples = posted.reduce((n, c) => n + c.length, 0);
  assert.ok(posted.length >= 199, `${rate} Hz: expected ~200 chunks over 10 s, got ${posted.length}`);
  assert.ok(posted.every(c => c.length === 1200), `${rate} Hz: every chunk must be 1200 samples (50 ms)`);
  assert.ok(Math.abs(samples / 10 - 24000) < 250, `${rate} Hz: output rate ${samples / 10}/s, expected 24000`);

  const all = posted.flatMap(c => Array.from(c));
  let crossings = 0;
  for (let i = 1; i < all.length; i++) if ((all[i - 1] < 0) !== (all[i] < 0)) crossings++;
  const freq = crossings / 2 / (all.length / 24000);
  assert.ok(Math.abs(freq - 440) < 2, `${rate} Hz: tone came out at ${freq.toFixed(1)} Hz, expected 440`);
  console.log(`PASS ${rate} Hz input: ${posted.length} chunks, ${(samples / 10).toFixed(0)} samples/s, tone ${freq.toFixed(1)} Hz`);
}
console.log('ALL PCM PROCESSOR CHECKS PASSED');
