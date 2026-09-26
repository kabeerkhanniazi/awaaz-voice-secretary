# Testing

How Awaaz is tested: **62 automated checks** (28 for the gateway, 34 for the app) that run on every push with no network and no API key, plus live tests against the real Voice Agent API.

---

## Run them

```bash
cd gateway && npm install && npm test         # 28 checks, in seconds
cd app && flutter analyze --fatal-infos         # static analysis, no issues allowed
cd app && flutter test                          # 34 tests
```

Both suites also run in GitHub Actions on every push and pull request ([`.github/workflows/ci.yml`](../.github/workflows/ci.yml)):
- **Gateway and audio tests:** Node 18, `npm test`.
- **Flutter analyse and tests:** `flutter analyze --fatal-infos`, then `flutter test`, then the demo-build test with `--dart-define=AWAAZ_DEMO_GATEWAY=wss://demo.example.app`.

---

## Gateway: 28 checks in four suites

- **The audio suite** runs the AudioWorklet resampler directly.
- **The other three** each start a real gateway in-process, on their own port, and talk to it over real WebSockets and HTTP. A placeholder key is used, so nothing reaches AssemblyAI.

### Audio (`test/pcm_processor.test.js`): 3 checks

The AudioWorklet resampler is run on a generated 440 Hz tone at three input rates. The output must be 24 kHz, arrive in whole chunks, and still carry a 440 Hz tone:

| Check |
|---|
| 48,000 Hz input: 200 chunks, 24,000 samples/s, tone 439.9 Hz |
| 44,100 Hz input: 200 chunks, 24,000 samples/s, tone 439.9 Hz |
| 16,000 Hz input: 199 chunks, 23,880 samples/s, tone 439.9 Hz |

### Routing, roles and security (`test/concurrent_routing.test.js`): 14 checks

| Check | Why it matters |
|---|---|
| Spoken call-back numbers become digits | "oh three zero one…" must dial |
| Mobile registration requires the gateway secret | Only you take your calls |
| Caller sockets cannot hijack or invent calls | A caller can't pretend to be another call |
| Directives are routed only to the owning caller | Your instruction reaches the right person only |
| Only an authenticated phone can send directives | Nobody else can steer your calls |
| Transcripts are attributed to the sending caller only | No forged transcript lines |
| Caller details are recorded only by the caller page, and merged | No forged details, and corrections merge |
| Active calls are replayed to a reconnecting phone | A dropped connection doesn't lose a call |
| Secretary sessions are limited to authenticated phones and live calls | No AI spending by strangers |
| Patch In relays audio only between the caller and the patching phone | The bridge is private |
| Hang-up and phone disconnect end the bridge for the caller | Nobody is left in silence |
| Ended calls are cleaned up | No leaks |
| Unattended calls get a message taken | Every caller is looked after |
| Missed calls reach the phone until it confirms logging them | Nothing is lost while you're offline |

### Demo lines (`test/demo_lines.test.js`): 7 checks

| Check |
|---|
| Demo phones register with their own line code, no secret |
| A demo call without a line is refused |
| A call reaches only the phone on its own line |
| Another line cannot steer, brief or annotate the call |
| Analysis needs a registered line |
| Hang-ups and missed calls stay on their line |
| The owner page is served, and keeps to its own line (it sends settings only on a demo line) |

### Owner settings and trust (`test/owner_settings.test.js`): 4 checks

| Check |
|---|
| A blocked browser cannot call, and callers cannot unblock themselves |
| Personal links verify callers; claims and stale links do not |
| Call-back number, email and best time are recorded cleanly |
| Availability, always-ring and never-ring decide who gets through, including when "busy until" expires |

---

## App: 34 tests in four files

### Caller trust (`test/caller_trust_test.dart`): 11 tests

- a first name matches the full name, a different person does not
- a personal link verifies, whatever name is given
- the right link from a new browser is still verified, but noted
- someone else's name on Maria's link is a warning
- saying Maria's name without her link is only a match
- Ali calling back as a professor from the same browser is a warning
- the same name again from the same browser is recognised, not verified
- an unknown or revoked link is flagged
- local Pakistani numbers become WhatsApp numbers
- personal links carry the token, and tokens are unguessable
- the gateway gets availability, links and blocked browsers in one message

### The call flow (`test/voice_commands_test.dart`): 15 tests

These drive the real call state machine with gateway messages, and assert on what the app shows and sends:
- a real incoming call starts screening; without a mic the voice panel says so
- "hold for five minutes" puts the caller on a five-minute hold
- a relayed message is logged as Kabeer's
- a caller who only says a contact's name is a claim, not that contact
- a caller through a personal link is verified, under the name Kabeer saved
- a browser that called as Ali and now claims to be a professor is flagged
- marking an impostor blocks that browser and tells the gateway
- the number and email a caller confirmed reach the record and a task you can dial
- a quiet call (Kabeer away) does not open his voice session
- details for another call do not rename this one
- missed calls become call records with a call-back task, once
- a second caller waits, keeps their details, and comes up after this call
- a waiting caller who hangs up leaves the queue
- commands for another call are ignored
- dictated tasks are saved when the call is ended by voice, and restatements replace

### The demo build (`test/demo_config_test.dart`): 2 tests

- a normal build has no demo line and uses the live gateway
- a demo build gets one lasting line code and a link that rings it (run in CI with the demo gateway defined)

### Models and safety (`test/widget_test.dart`): 6 tests

- round-trip serialisation for transcript entries, call records, tasks and contacts (4 tests)
- a directive with quotes, newlines and fake tags cannot escape its delimiters (prompt-injection safety)
- the app starts (smoke test)

---

## Live tests against the real API

Automated tests prove the logic. The sound and the AI's behaviour are proven live, against a gateway on the laptop with a real AssemblyAI key:

| Live test | What it proved |
|---|---|
| **Decline and privacy** | A scripted caller spoke recorded lines into the caller's secretary. Asked where Kabeer was and for his number, she refused. After a decline she kept the caller on the line, took "0300 123 4567" and read it back digit by digit, then ended the call herself |
| **Honest briefings** | For an unverified caller, your secretary said "someone calling as Maria Lopez from Brightline Studios", never a relationship |
| **The owner page, every branch** | A scripted caller rang the page. It tested answer, the briefing, put through, the bridge, hang-up, the record and AI summary, end with late call-back details, a returning browser, a personal link, the impostor warning and block (the next call refused with 403), and do-not-disturb with hold and relay |
| **The demo app on an emulator** | An Android 17 emulator with 16 KB pages, a stricter check than most phones. The app created its line code, a scripted caller rang its link, only that phone rang, and its secretary joined |
| **Production smoke tests** | After each deploy: `/health` shows the new build and the right mode, and the owner page on the demo line takes a scripted call end to end |

The scripted callers do exactly what the caller page does over the gateway protocol: they register the call, send transcript lines and details, answer instructions, and open the bridge. So every branch can be tested by one person, at any time, against the real services.

---

## Manual checklist before a release

- [ ] `npm test` and `flutter test` pass, and `flutter analyze` finds nothing
- [ ] Call the live line from a laptop; answer on the phone; say "put her through"; talk both ways
- [ ] "Tell her I'll call back in ten minutes": the caller hears it in the third person
- [ ] "Remind me to send the invoice by Friday": the task has Friday's date
- [ ] Don't answer: at 90 seconds a message is taken, the number is read back, and the task dials it
- [ ] Do not disturb: the call doesn't ring, and a message is taken after 12 seconds
- [ ] A personal link shows "Verified"; the same browser with another name shows a warning
- [ ] The owner page takes a call in a browser with a real microphone
- [ ] Both lines' `/health` show the new build

---

## Not automated yet

- **Audio quality and echo on real devices,** checked by ear on a phone.
- **Ringing over the lock screen,** checked on a phone.
- **End-to-end calls with recorded audio in CI.** On the [roadmap](ROADMAP.md).
