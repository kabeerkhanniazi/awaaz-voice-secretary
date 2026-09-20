# Awaaz: how it works today

The source of truth for the current system. Other documents in `docs/` and the root
`*.md` files describe earlier plans; where they disagree with this file, this file wins.

## The product

1. Someone calls Kabeer from the web page (`https://aivs.up.railway.app`).
2. The **screening secretary** (an AssemblyAI voice agent) answers, learns the caller's
   name and reason, and records them with the `save_caller_details` tool.
3. Kabeer's phone shows the call. If the app is closed and "Ring when the app is closed"
   is on, a native Android service rings with a full-screen call alert.
4. Kabeer talks to **his own secretary session** by voice. It briefs him from confirmed
   details, answers questions about the call, and acts on commands: connect me, put them
   on hold for N minutes, tell them X, remind me to Y, end the call.
5. "Connect" hands the caller over: the secretary says she's connecting, her session ends,
   and caller and Kabeer talk over a live audio bridge through the gateway.
6. When the call ends the phone saves a call record with an AI summary (AssemblyAI LLM
   Gateway) and the tasks Kabeer dictated (with due dates when he says when).
7. If nobody acts on the call within `TAKE_MESSAGE_AFTER_MS` (default 90 s), the secretary
   tells the caller Kabeer is unavailable, takes a message and a call-back number, and ends
   the call. Calls the phone never logged (it was offline) are kept for 24 hours and sent as
   `MISSED_CALLS` when it reconnects; each becomes a call record plus a call-back task.
8. If the caller is in Kabeer's phone contacts, the phone tells the gateway how he knows
   them (`CALLER_CONTEXT`) and his secretary mentions it in the briefing.

## Pieces

| Piece | Where | Notes |
|---|---|---|
| Gateway | `gateway/server.js` | HTTP + WebSocket relay, deployed on Railway. |
| The owner's secretary session | `gateway/master-session.js` | Server-side AssemblyAI session per call; phone streams mic over the gateway socket. |
| Caller page | `gateway/web/caller.html`, `gateway/web/pcm-processor.js` | Browser ↔ AssemblyAI directly (token from gateway); relay socket to gateway. |
| Phone app | `app/` (Flutter, Android) | Published here under MIT as the hackathon edition. |
| Android native | `app/android/app/src/main/kotlin/.../` | `CallAudioPlayer` (voice-call playback), `AwaazService` (standby ring + in-call microphone foreground service), `BootReceiver`. |

The gateway serves the caller page itself from `gateway/web/`.

## Audio

- Everything is PCM16 mono, 24 kHz.
- Caller mic: AudioWorklet resamples device rate → 24 kHz, 50 ms chunks (`pcm-processor.js`).
- Caller ↔ AssemblyAI: base64 in JSON (`input.audio` / `reply.audio.data`).
- Phone ↔ gateway: raw binary WebSocket frames, both for the secretary session and the bridge.
- Phone playback: `CallAudioPlayer.kt` (AudioTrack, `USAGE_VOICE_COMMUNICATION`); mic via
  the `record` package with `voiceCommunication` source for echo cancellation.

## AssemblyAI protocol rules we learned the hard way

- The **first** WebSocket message must be `session.update` with the persona
  (`system_prompt`, `greeting`, `output.voice`, `tools`). Without it no `session.ready`
  ever arrives. `agent_id` is not a token parameter.
- Make the agent speak now with `reply.create` (optional `instructions`). Updating
  `system_prompt` does not make it speak.
- `system_prompt` can be updated mid-session and the agent uses it. `conversation.message`
  is accepted but was ignored in practice.
- `tool.result.result` must be a **string** (JSON-encode objects), and should be sent after
  the `reply.done` of the reply that made the tool call.
- `reply.audio` carries audio in `data`; `input.audio` in `audio`.
- A `reply.create` sent while a reply is still playing is silently dropped. Both the caller
  page and `master-session.js` hold it until `reply.done`.
- LLM Gateway: this account can use `qwen3.5-4b-32k-fast` only (Claude/Gemini return
  "no access"). Override with the `SUMMARY_MODEL` env var after upgrading.

## Gateway messages (JSON over WebSocket unless noted)

Phone → gateway: `REGISTER_MOBILE {authSecret}`, `MASTER_DIRECTIVE {data:{callId, action,
spokenDirective?, holdMinutes?, directiveVersion}}` (actions: `holding`, `patchedToMaster`,
`custom`, `declined`, `hangup`), `MASTER_SESSION_START {callId}`, `MASTER_SESSION_STOP`,
`CALLER_CONTEXT {callId, relationship, company?, note?}`, `CALL_LOGGED {callId}`,
`SYNC_MISSED_CALLS` (answered with `MISSED_CALLS`),
binary mic frames.

Gateway → phone: `REGISTERED_SUCCESS`, `AUTH_FAILED`, `INCOMING_CALL {callId, details?}`,
`CALLER_DETAILS {callId, name, company, reason, urgent, message, callback}`, `TRANSCRIPT_UPDATE`,
`TAKING_MESSAGE {callId}`, `MISSED_CALLS {calls:[{callId, startedAt, endedAt, details,
tookMessage, transcript}]}`,
`DIRECTIVE_STATE`, `DIRECTIVE_FAILED`, `CALLER_HUNG_UP`, `SESSION_EXPIRED`,
`BRIDGE_CONNECTED`, `MASTER_SESSION_STATE {state}`, `MASTER_TRANSCRIPT {speaker, text}`,
`MASTER_COMMAND {command: connect|hold|relay|task|end, ...}`, `MASTER_AUDIO_FLUSH`,
binary audio (secretary speech or the caller on the bridge).

Caller page → gateway: `REGISTER_CALLER {callId}`, `TRANSCRIPT_UPDATE`, `CALLER_DETAILS`,
`DIRECTIVE_STATE`, `DIRECTIVE_FAILED`, `SESSION_EXPIRED`, `BRIDGE_READY`, binary mic frames
(bridge only). Gateway → caller page: `DIRECTIVE_UPDATED`, `TAKE_MESSAGE`, `BRIDGE_ENDED`, binary audio.

Only a socket that registered with the secret may act as a phone; a caller socket may only
report on its own call. See `test/concurrent_routing.test.js`.

HTTP: `GET /` caller page, `GET /api/voice-token` (rate-limited), `POST /api/call`
(rate-limited), `POST /api/analyze-call` (needs `X-Awaaz-Secret`), `GET /health`.

## Configuration

Railway variables: `ASSEMBLYAI_API_KEY`, `GATEWAY_AUTH_SECRET` (required for phones),
optional `SUMMARY_MODEL`, `TAKE_MESSAGE_AFTER_MS` (default 90000), `KABEER_TIMEZONE`
(default `Asia/Karachi`, used to turn "tomorrow" into a due date). Local `.env` holds the same for running the server on the PC.

Phone: Settings → Gateway (defaults to `wss://aivs.up.railway.app`) and Gateway secret
(stored in the Android keystore via `flutter_secure_storage`).

## Testing

- `npm test`: PCM worklet test and gateway routing/security test (no network).
- `flutter analyze` (CI uses `--fatal-infos`) and `flutter test`.
- Live checks against AssemblyAI used throwaway Node harnesses with synthetic speech
  (Windows text-to-speech); see the session notes of 2026-09-19.

## Known limits

- Kabeer handles one call at a time. A caller who rings meanwhile is screened by the
  secretary, shown on the call screen as waiting, and comes up when the current call ends
  (or leaves a message after `TAKE_MESSAGE_AFTER_MS`, fetched with `SYNC_MISSED_CALLS`).
  Kabeer's secretary knows who is waiting and mentions them if asked or if urgent.
- Background ringing depends on the standby service staying alive; aggressive battery
  savers on some phones can stop it. Firebase push would be a sturdier backup channel.
- Echo on speakerphone depends on the device; earphones avoid it.
- Missed calls are held in gateway memory: a Railway restart before the phone reconnects
  loses them.
- The screening secretary's greeting and prompt name "Kabeer" in `server.js`.
