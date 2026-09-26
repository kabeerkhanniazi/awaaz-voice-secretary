# Awaaz — the AI secretary that keeps you on the line

> Every voice agent either replaces you, or reports to you after the call.
> **Awaaz keeps you in the call.**

A caller opens a link and presses Call. An AI secretary, built on the **AssemblyAI Voice Agent API**, finds out who they are and why they are calling. Your phone rings. A **second** AssemblyAI agent, private to you, briefs you by voice and does what you say while the caller is still on the line:

- *"Put her through."* → the secretary says she is connecting, and a live audio bridge opens between you and the caller.
- *"Hold for five minutes."* → the caller is asked to hold, and your phone counts down.
- *"Tell him I will call back tomorrow."* → she says it to the caller in her own words ("Kabeer will call you back tomorrow").
- *"Remind me to send the invoice by Friday."* → a task with a real due date.
- Nobody answers, or you say *"end the call"*? Before any goodbye she gets a way to reach the caller: a number or email and the best time, read back digit by digit and confirmed. You get a "Call back" task with a button that dials.
- *"Busy for an hour"* or *do not disturb*: she takes messages straight away and tells callers when you'll be free. People you choose can still always get through.
- **She never takes a name on trust** (see [Who is really calling](#who-is-really-calling)).

Built solo in Pakistan for the [lablab.ai AssemblyAI Voice Agent Hackathon](https://lablab.ai/ai-hackathons/assemblyai-voice-agent-hackathon), September 2026.

**Live caller line:** https://aivs.up.railway.app — call it. Kabeer is a real person; if he is busy, the secretary will take your message.

---

## Try it in 60 seconds

| You want to | Do this |
|---|---|
| **Hear the secretary (caller side)** | Open https://aivs.up.railway.app and press Call. Works in any desktop browser with a microphone. |
| **See both sides** | Watch the demo video (link in the submission). Caller page on the left, phone on the right, in one take. |
| **Be the owner yourself** | Install the **[demo APK](https://github.com/kabeerkhanniazi/awaaz-voice-secretary/releases/tag/demo-apk-1)** on an Android phone. Open it: the Calls tab shows **Your demo line** with a link. Open that link on a laptop and press Call. Your phone rings, and you play Kabeer. No account, no API key, no secret to type. See [The demo line](#the-demo-line). |
| **Be the owner in a browser, iPhone included** | Open https://awaaz-demo.up.railway.app/owner and press **Start taking calls**. The page shows your own demo line link. Open that link on another device and press Call. The page rings, your secretary briefs you, and you can put the caller through. Nothing to install. |
| **Run the whole thing yourself** | See [Run it yourself](#run-it-yourself). You need a free AssemblyAI key. |

---

## Documentation

| | |
|---|---|
| [Architecture](docs/ARCHITECTURE.md) | Components, state, and every gateway message |
| [Tech stack](docs/TECH_STACK.md) | Every technology and version, tuning values, audio formats, and why |
| [Workflow](docs/WORKFLOW.md) | The life of a call, message by message, with diagrams; how Awaaz is built and shipped |
| [All possible scenarios](docs/SCENARIOS.md) | Over 100 situations: what the caller, the owner and the record see in each |
| [Building on the Voice Agent API](docs/VOICE_AGENT_API_NOTES.md) | How both agents are wired and steered, lessons from the live API, and costs |
| [Security and privacy](docs/SECURITY.md) | Keys, roles, abuse controls, caller trust, and data retention |
| [User guide](docs/USER_GUIDE.md) | For callers, owners and judges, with a voice-command cheat sheet |
| [Deployment](docs/DEPLOYMENT.md) | Environment, local runs, Railway for both lines, building and releasing the app |
| [Testing](docs/TESTING.md) | All 62 automated checks by name, plus the live tests |
| [Roadmap](docs/ROADMAP.md) | What's done, and what comes next |
| [FAQ](docs/FAQ.md) and [Glossary](docs/GLOSSARY.md) | Quick answers, and the words used throughout |

---

## How a call works

```
   Caller's browser                    Gateway (Node, Railway)                 Owner's phone
 ┌───────────────────┐               ┌───────────────────────┐             ┌──────────────────┐
 │ caller.html       │  PCM16 24k    │  call registry        │  WebSocket  │ Flutter app      │
 │ mic + playback    │◄─────────────►│  roles: caller/owner  │◄───────────►│ call UI, tasks   │
 └─────────┬─────────┘   WebSocket   │  audio relay          │   + binary  └────────┬─────────┘
           │                         │  take-message timer   │     audio            │
           │ WebSocket               └───────────┬───────────┘                      │ mic
           ▼                                     │                                  ▼
 ┌───────────────────────┐                       │                    ┌────────────────────────┐
 │ AssemblyAI            │                       │  server-side       │ AssemblyAI             │
 │ Voice Agent, agent A  │                       └───────────────────►│ Voice Agent, agent B   │
 │ screens the caller    │                                            │ briefs the owner       │
 └───────────────────────┘                                            └────────────────────────┘

 On "put her through": agent A's session ends and the gateway relays raw audio
 between the caller's browser and the phone. Two humans, no AI in the middle.
```

Full detail:
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): the components and every message;
- [docs/WORKFLOW.md](docs/WORKFLOW.md): each step of a call, with sequence diagrams.

## Who is really calling

A web caller has no caller ID, so a name is only what they say. Awaaz never presents a claim as fact:

| What you see | When |
|---|---|
| **Verified: via Maria's link** | They called through the personal link you sent them (Contacts, then Send on WhatsApp). This is the only thing that verifies a caller. You can revoke a link at any time. |
| **Not verified** | Anyone else. If the name matches a contact, you see "name matches your contact Maria Lopez", never "your VIP client". |
| **Warning** | The same browser called before under another name ("This browser called before as Ali Khan"); someone used Maria's link but gave another name; or an old or revoked link was used. |

On top of that:
- **Your secretary warns you about scam patterns.** Someone claiming authority (an official, a bank, a professor) with urgency, or asking for money, codes or documents, gets flagged, with a suggestion to verify them on a number you find yourself.
- **The caller's secretary gives nothing away.** She never shares where you are, your schedule, your contacts or your numbers, and agrees to nothing when a caller claims authority.
- **Impostor or spam: one tap blocks that browser**, and the gateway refuses its calls from then on.
- **"Always ring" and "never ring" only apply to calls through a personal link**, so nobody can get past do-not-disturb by giving a name.

## Where AssemblyAI is used

| What | Where in this repo |
|---|---|
| **Voice Agent API, agent A** — screens the caller; tools `save_caller_details`, `end_call` | Persona and tools in [`gateway/server.js`](gateway/server.js) (`SECRETARY_SYSTEM_PROMPT`, `SECRETARY_TOOLS`); the browser session in [`gateway/web/caller.html`](gateway/web/caller.html) |
| **Voice Agent API, agent B** — the owner's private secretary; tools `connect_caller`, `hold_caller`, `relay_message`, `add_task`, `end_call` | [`gateway/master-session.js`](gateway/master-session.js) |
| Short-lived session tokens, so the API key never reaches a browser | `GET /api/voice-token` in [`gateway/server.js`](gateway/server.js) |
| `reply.create` instructions, mid-session `system_prompt` updates, barge-in and interrupted replies | [`gateway/master-session.js`](gateway/master-session.js), [`gateway/web/caller.html`](gateway/web/caller.html) |
| **LLM Gateway** — post-call summary and task extraction (`qwen3.5-4b-32k-fast`) | `analyzeWithLlm` in [`gateway/server.js`](gateway/server.js) |
| PCM16 24 kHz audio in both directions | [`gateway/web/pcm-processor.js`](gateway/web/pcm-processor.js) (AudioWorklet resampler), [`app/android/.../CallAudioPlayer.kt`](app/android/app/src/main/kotlin) (AudioTrack) |

## What the docs do not tell you

Things we learned the hard way against the live API. Each one is handled in the code:

1. **A `reply.create` sent while the agent is still speaking is silently dropped.** No error, no reply, the instruction simply vanishes. Awaaz queues it and sends it on `reply.done` (`_sendAgent` in `master-session.js`, `dispatchDirective` in `caller.html`).
2. **The same happens right after tool results.** The agent answers the tool result first and swallows a directive sent in the same moment, so a held directive waits a beat longer.
3. **`tool.result.result` must be a JSON *string*.** An object is rejected as `invalid_format`. Send it after the `reply.done` of the reply that made the tool call.
4. **`session.update` must be the first message on the socket**, carrying the prompt, greeting, voice and tools, or no `session.ready` ever arrives. `agent_id` is not a token parameter.
5. **`system_prompt` can be changed mid-session** and the agent honours it. `conversation.message` was accepted but ignored in practice, so live context goes into the prompt.
6. **A detached `ArrayBuffer` has length 0.** After posting mic audio from an AudioWorklet, read the chunk size *before* transferring it.

More lessons, with the full wiring of both agents: [docs/VOICE_AGENT_API_NOTES.md](docs/VOICE_AGENT_API_NOTES.md).

## Evidence

Run these yourself:

| Check | Command | Result |
|---|---|---|
| Gateway routing, roles, security, message-taking, demo-line isolation, personal links, blocking, availability, the owner page | `cd gateway && npm install && npm test` | 28 checks pass |
| Flutter app: state machine, voice commands, missed calls, caller trust, call-back details, demo build | `cd app && flutter test` | 34 tests pass |
| Static analysis | `cd app && flutter analyze --fatal-infos` | no issues |

Both suites run in CI on every push ([.github/workflows/ci.yml](.github/workflows/ci.yml)), with no API key and no network. Every check is listed by name, with the live tests against the real API, in [docs/TESTING.md](docs/TESTING.md).

## Security and privacy

- The AssemblyAI key stays on the server. Browsers get single-use tokens from `/api/voice-token`.
- Only a socket that presents `GATEWAY_AUTH_SECRET` can act as the owner. The comparison is constant-time.
- Per-IP rate limits on the public endpoints, and random UUID call IDs.
- The caller page shows no transcript; the caller sees only the call status.
- The caller page keeps a random, anonymous id in the browser so a repeat caller can be recognised or blocked. The page footer says so. It isn't a fingerprint, and it goes nowhere except your own gateway.
- Personal-link tokens are random and revocable, and live only on your phone and your gateway.
- Call records, tasks and contacts stay on the phone. The gateway keeps a call in memory only while it is live, plus up to 24 hours for calls the phone has not logged yet.
- Every deploy passes a secret scan against the real key values, and the tests, before anything is pushed.

More: [docs/SECURITY.md](docs/SECURITY.md).

## Run it yourself

**1. The gateway**

```bash
cd gateway
npm install
cp ../.env.example .env        # then fill in ASSEMBLYAI_API_KEY and GATEWAY_AUTH_SECRET
npm start                      # http://localhost:3000
```

Open `http://localhost:3000` in a browser with a microphone and press Call. The secretary answers. Nobody is there to take the call yet, so after `TAKE_MESSAGE_AFTER_MS` (90 s by default, set it lower to try it) she takes a message.

Deploying it (Railway, Render, Fly, any Node host): set the same environment variables, and the `Procfile` runs `node server.js`.

**2. The owner app (Android)**

```bash
cd app
flutter pub get
flutter run                    # or: flutter build apk --release
```

Then in the app: **Settings → Gateway** = `ws://<your-machine>:3000` (or your deployed `wss://…` address) and **Gateway secret** = the same `GATEWAY_AUTH_SECRET`. Turn on "Ring when the app is closed" if you want the standby service.

Requires Flutter (see [`app/.flutter-version`](app/.flutter-version)) and an Android device or emulator on Android 8+. Permissions used: microphone, notifications, contacts (optional, for "how you know them"), and a foreground service for ringing while closed.

Every environment variable, hosting on Railway, and building and signing the app: [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md).

## The demo line

The live line rings Kabeer's own phone, so its secret stays private. For judges there is a separate **demo line**: the same gateway code, deployed a second time with `DEMO_MODE=1`.

**Try it:** install [`awaaz-demo.apk`](https://github.com/kabeerkhanniazi/awaaz-voice-secretary/releases/tag/demo-apk-1) on an Android phone. The release notes have the install steps and a SHA-256 checksum. Then open the link the app shows on a laptop, and press Call. The hosted demo line is `https://awaaz-demo.up.railway.app`.

- **No secret.** A phone registers with its own **line code** instead. The demo APK creates one on first launch and keeps it.
- **Personal lines.** The app shows its link, `https://awaaz-demo.up.railway.app/?line=K7Q2PX`. A call placed through that link rings **that phone only**. Every message, directive, secretary session, missed call and log is kept to its own line, so any number of judges can try it at the same time without ringing each other or steering each other's calls. The isolation is tested in [`gateway/test/demo_lines.test.js`](gateway/test/demo_lines.test.js).
- **Nothing changes on the live line.** Outside demo mode every phone and call sits on the one empty line, so behaviour is exactly as before. The original routing and security checks run unchanged.

Run your own demo line:

```bash
# the gateway, with DEMO_MODE=1 and your ASSEMBLYAI_API_KEY (no GATEWAY_AUTH_SECRET needed)
cd gateway && DEMO_MODE=1 npm start

# the demo app, pointed at it
cd app && flutter build apk --release --dart-define=AWAAZ_DEMO_GATEWAY=wss://<your demo host>
```

## Platform support

| Platform | State |
|---|---|
| **Caller side** | Any modern desktop or mobile browser with a microphone. Nothing to install. |
| **Owner side, Android** | Fully supported: lock-screen ringing, a foreground service, and native voice-call audio (`AudioTrack` with `USAGE_VOICE_COMMUNICATION`) so echo cancellation works during the live bridge. |
| **Owner side, any browser (iPhone included)** | **The owner page**, [`gateway/web/owner.html`](gateway/web/owner.html), served at `/owner`. It covers the whole call: the briefing, voice commands, put through, hold, message, end, and the live bridge, plus caller trust and call records with AI summaries. On a demo line, the page also manages availability, personal links and blocking. On the live line, it asks for the secret and leaves those settings to the phone app, so it never overwrites them. It rings only while the page is open: there's no lock-screen ringing. |
| **Owner side, iOS app** | **Not shipped.** The audio player and the ringing service are Android-native (Kotlin). iOS needs a Swift equivalent plus CallKit and PushKit, a Mac to build, and a paid Apple account. The `app/ios` folder is the stock Flutter scaffold and is not wired up. On an iPhone, use the owner page. |
| **Flutter app on the web** | Not used. The app compiles for web, but its audio playback and ringing are Android platform channels with no web implementation, so calls would have no sound. The owner page covers this case. |

## Future enhancements

What comes next, in the order that matters most (the full plan, with the reasons, is in [docs/ROADMAP.md](docs/ROADMAP.md)):

- **A real phone number.** Calls to a number, or forwarded from yours, enter the same gateway as the caller page. The audio is already PCM16, so it's a new front door on the same system.
- **Urdu, and mixing Urdu and English.** The secretary becomes AssemblyAI's real-time transcription, which understands Urdu, plus a model through the LLM Gateway and an Urdu voice.
- **Your own secretary.** Accounts with your name, pronouns, voice and greeting, instead of a persona built for one owner.
- **Persistence and push.** Missed calls, settings and links in a database, and push notifications as a backup to the standby service.
- **Verify strangers.** Email a one-time code the caller reads back, so someone with no personal link can still be verified.
- **Calendar-aware availability.** Busy blocks in your calendar set your availability, and meeting titles are never shared.
- **Recognition hints.** Your contacts' names become speech-recognition hints, so "Brightline" and Urdu names are heard right.
- **iPhone.** The owner page becomes an installable app with web push, then a native iOS app with CallKit.
- **Teams.** One secretary for a small firm: "Who would you like to speak to?", then the right person's phone rings.
- **Integrations.** Summaries and tasks sent to calendars, CRMs and to-do apps.

## Project history

How Awaaz went from a prototype to the submitted system: over 50 commits across two repositories, built solo in Pakistan.

### August 2026: the prototype

- **26 Aug.** The first prototype, **"Vox Sonus"**: five voice agents on the AssemblyAI Voice Agent API. The same day it's renamed **Awaaz**, "voice" in Urdu. A bilingual path is dropped, and the first interface, a glowing orb, is reworked. It was later replaced altogether by a plain, calm design.

### Early September: one idea wins

- The project settles on one idea: **a secretary that keeps you in the call.** One agent screens the caller, a second briefs the owner privately, and the owner decides while the caller is still on the line.
- **14 Sep.** The server repository is reset to hold only the gateway that Railway deploys to `aivs.up.railway.app`.

### 18 September: the gateway grows up

Thirteen changes in one day:
- The voice agent's connection and **persona drift** are fixed; the secretary had been slipping out of character.
- A **gateway secret and socket roles**: only the owner's phone may direct calls, and a caller may report only on its own call.
- The caller's microphone streaming is fixed, and the **Patch In audio bridge** arrives: "put her through" connects two people directly, with no AI in between.
- The caller page shows only the call's status, never a transcript.
- **The owner's own voice session** with the secretary, the second agent.
- Caller details are recorded as data, and briefings use **confirmed facts only**.
- **AI call summaries** through the AssemblyAI LLM Gateway.
- A minimal redesign of the caller page: light and dark, mute, a call timer.
- Briefings mention **how the owner knows the caller**.
- **Dictated tasks** keep their due dates.
- **Message-taking** when the owner doesn't answer. It also brought the first hard lesson: a `reply.create` sent while the agent is speaking is **silently dropped**, so replies are now held until she finishes.
- Call-back numbers are saved as digits.
- **Waiting callers**: a second caller is screened and waits, and the owner's secretary knows who else is calling.

### 19 September: the app, and discipline

- The Android app gets its own version history; it had been developed in another workspace before.
- **AwaazService**: the phone rings over the lock screen even when the app is closed, and calls stay alive with the screen off. Firebase push was considered, and a native standby service chosen instead, so it works without any third-party account.
- A redesign of the app: a minimal full-screen call UI, a calm theme, and only real data.
- The gateway secret moves into the **Android Keystore**, and CI now runs the real tests.
- The call screen shows whether the secretary has actually told the caller what you asked.
- Two more lessons from the live API:
  - tool results swallow a reply sent at the same moment, so held replies now wait a beat;
  - the secretary ends calls herself after the goodbye.
- The secretary tells callers "Kabeer is on another call" when he is, and "busy" means only a live bridge.
- **Hackathon research:** all 84 other submissions read and compared, and the official 1–5 scoring rubric found in the rules page's source.

### 20–21 September: public, and a line for every judge

- **20 Sep.** This Hackathon Edition is published under MIT, with CI. It was assembled as a fresh tree, so its history starts here. The gateway's earlier history lives in the original repository, `kabeerkhanniazi/Awaaz` (branch `sidekick-server`, now archived).
- **21 Sep.** **Demo lines.** A demo deployment gives every phone its own line code, with no secret, so any number of judges can play the owner at once without reaching each other's calls. A preconfigured demo build, and a caller page that explains the line it's on.

### 25 September: who is really calling

It started with a real question: what if a caller named Ali says he's your professor?
- **Caller trust.** Only a personal link verifies. Names stay claims. There are warnings for a browser that switches names, a borrowed link and a stale link, and the owner's secretary flags impersonation-scam patterns. One tap blocks an impostor's browser.
- **Personal links,** sent on WhatsApp from the app and revocable, with "always ring" and "never ring".
- **Call-back details.** The secretary never says goodbye without a number or email and the best time, read back digit by digit and confirmed.
- **Availability.** Busy until a time, or do not disturb. Quiet calls get their message taken after 12 seconds, with "he'll be free after 3:00 PM".
- **Tap to dial, WhatsApp and email** from calls, tasks and contacts, and sharing your call link on WhatsApp.
- **Privacy rules** for the caller's secretary, and an honest English-only rule instead of guessing at other languages.
- The live line is redeployed with all of it. The code moves to one place: the live line now builds from this repository, the old repository is archived, and every deploy runs a secret scan and the tests first.

### 26 September: anyone, anywhere

- The hosted **demo line**, `awaaz-demo.up.railway.app`, and the **demo APK release**, tested on an Android 17 emulator.
- **The owner page.** Take calls in any browser, iPhone included, with nothing to install: the ring, the briefing, voice commands, put through, hold, message, end, and the live bridge.
- The secretary stops guessing callers' genders: *"Someone calling as Maria Lopez from Brightline Studios… they want to talk about Friday's design review."*
- **Documentation** for everything: the architecture, tech stack, workflow, over 100 scenarios, the Voice Agent API notes, security, deployment, testing, a user guide and the roadmap.

### By the numbers

| | |
|---|---|
| AssemblyAI Voice Agent sessions per call | 2, plus the LLM Gateway afterwards |
| Ways to take part | 3: the caller page, the Android app, the owner page |
| Automated checks | 62 (28 gateway, 34 app), on every push |
| Documented scenarios | 104 |
| Live deployments | 2, from one folder |
| Runtime dependencies in the gateway | 2 |

## Licence and name

Code is MIT licensed, see [LICENSE](LICENSE). The licence covers the code, not the name "Awaaz" or the logo.

*Awaaz* means "voice" in Urdu.

**Contact:** mu.kabir2004@gmail.com, or [call me through Awaaz](https://aivs.up.railway.app). If I'm busy, my secretary will take your message.
