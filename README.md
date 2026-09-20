# Awaaz — the AI secretary that keeps you on the line

> Every voice agent either replaces you, or reports to you after the call.
> **Awaaz keeps you in the call.**

A caller opens a link and presses Call. An AI secretary, built on the **AssemblyAI Voice Agent API**, finds out who they are and why they are calling. Your phone rings. A **second** AssemblyAI agent, private to you, briefs you by voice and does what you say while the caller is still on the line:

- *"Put her through."* → the secretary says she is connecting, and a live audio bridge opens between you and the caller.
- *"Hold for five minutes."* → the caller is asked to hold, and your phone counts down.
- *"Tell him I will call back tomorrow."* → she says it to the caller in her own words ("Kabeer will call you back tomorrow").
- *"Remind me to send the invoice by Friday."* → a task with a real due date.
- Nobody answers? After 90 seconds she says you are unavailable, takes a message and a call-back number, reads it back, and ends the call politely.

Built solo in Pakistan for the [lablab.ai AssemblyAI Voice Agent Hackathon](https://lablab.ai/ai-hackathons/assemblyai-voice-agent-hackathon), September 2026.

**Live caller line:** https://aivs.up.railway.app — call it. Kabeer is a real person; if he is busy, the secretary will take your message.

---

## Try it in 60 seconds

| You want to | Do this |
|---|---|
| **Hear the secretary (caller side)** | Open https://aivs.up.railway.app and press Call. Works in any desktop browser with a microphone. |
| **See both sides** | Watch the demo video (link in the submission). Caller page on the left, phone on the right, in one take. |
| **Be the owner yourself** | Install the Android APK from [Releases](../../releases), then in Settings enter the demo gateway address and secret from the release notes. Call the demo line from a laptop and answer on the phone. |
| **Run the whole thing yourself** | See [Run it yourself](#run-it-yourself). You need a free AssemblyAI key. |

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

Full detail: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

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

## Evidence

Run these yourself:

| Check | Command | Result |
|---|---|---|
| Gateway routing, roles, security, message-taking | `cd gateway && npm install && npm test` | 17 checks pass |
| Flutter app: state machine, voice commands, missed calls | `cd app && flutter test` | 16 tests pass |
| Static analysis | `cd app && flutter analyze --fatal-infos` | no issues |

Both suites run in CI on every push ([.github/workflows/ci.yml](.github/workflows/ci.yml)), with no API key and no network.

## Security and privacy

- The AssemblyAI key stays on the server. Browsers get single-use tokens from `/api/voice-token`.
- Only a socket that presents `GATEWAY_AUTH_SECRET` can act as the owner. The comparison is constant-time.
- Per-IP rate limits on the public endpoints, and random UUID call IDs.
- The caller page shows no transcript; the caller sees only the call status.
- Call records, tasks and contacts stay on the phone. The gateway keeps a call in memory only while it is live, plus up to 24 hours for calls the phone has not logged yet.

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

## Platform support, honestly

| Platform | State |
|---|---|
| **Caller side** | Any modern desktop or mobile browser with a microphone. Nothing to install. |
| **Owner side, Android** | Fully supported: lock-screen ringing, a foreground service, and native voice-call audio (`AudioTrack` with `USAGE_VOICE_COMMUNICATION`) so echo cancellation works during the live bridge. |
| **Owner side, iOS** | **Not shipped.** The audio player and the ringing service are Android-native (Kotlin). iOS needs a Swift equivalent plus CallKit and PushKit, a Mac to build, and a paid Apple account. The `app/ios` folder is the stock Flutter scaffold and is not wired up. |
| **Owner side, web** | The Flutter app compiles for web, but the voice path would be dead there: audio playback and the ringing service are platform channels with no web implementation. A purpose-built **owner console page** is the planned answer, so any device, iPhone included, can take a call without installing anything. |

## Limits

- Callers reach a web page, not a real phone number. A SIP/PSTN number is the next step.
- One owner per deployment. A second caller is screened and waits their turn.
- Missed calls live in the gateway's memory, so a restart before the phone reconnects loses them.
- The secretary's persona names "Kabeer" (see `SECRETARY_SYSTEM_PROMPT` in `gateway/server.js`); change it for your own deployment.
- The post-call summary uses the only model this AssemblyAI account can reach; override with `SUMMARY_MODEL`.

## Project history

- **26 Aug 2026** — first prototype commits, then named "Vox Sonus".
- **1–30 Sep 2026** — Awaaz built during the hackathon window: the two-agent design, the live bridge, the Android app, message taking, waiting callers, tasks with due dates.
- This repository is the **Hackathon Edition**: a clean snapshot of the submitted system, published under MIT. It was assembled as a fresh tree, so the commit history here starts at the snapshot; the gateway's development history lives in the original repository (`kabeerkhanniazi/Awaaz`, branch `sidekick-server`).

## Licence and name

Code is MIT licensed, see [LICENSE](LICENSE). The licence covers the code, not the name "Awaaz" or the logo.

*Awaaz* means "voice" in Urdu.
