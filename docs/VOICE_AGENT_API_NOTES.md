# Building on the AssemblyAI Voice Agent API

How Awaaz uses AssemblyAI, in enough detail to rebuild it, and what we learned that the documentation doesn't say. Every point here is backed by code in this repository.

---

## 1. Why two agents per call

A single voice agent talks to one person. Awaaz needs to hold two conversations at once, about the same call:

| | Agent A: the caller's secretary | Agent B: your secretary |
|---|---|---|
| Talks to | The caller | You, privately |
| Runs | In the caller's browser | On the gateway |
| Knows | Only what the caller tells her, plus your instructions | The confirmed details, the call so far, who the caller really is, and who else is waiting |
| Tools | `save_caller_details`, `end_call` | `connect_caller`, `hold_caller`, `relay_message`, `add_task`, `end_call` |
| Voice | `alba` | `alba`, because to both people she's the same secretary |

The gateway is the only link between them, and it passes **confirmed facts only**: what agent A recorded with her tool, never raw guesses. When you say "put her through", agent A's session ends, agent B steps out, and the gateway relays raw audio person to person.

---

## 2. Connecting

### Agent A, from the browser

1. **The token.** The caller page asks the gateway for `GET /api/voice-token`. The gateway calls `https://agents.assemblyai.com/v1/token?expires_in_seconds=300&max_session_duration_seconds=600` with the API key, and returns the token together with the persona: system prompt, greeting, voice and tools. **The key never reaches the browser.**
2. **The socket.** The page connects to `wss://agents.assemblyai.com/v1/ws?token=…`.
3. **The first message is `session.update`**, carrying `system_prompt`, `greeting`, `output.voice` and `tools`. Nothing else may come first.
4. **Audio** goes up as `input.audio` messages: base64 PCM16, mono, 24 kHz, one 50 ms chunk each, produced by the AudioWorklet in `web/pcm-processor.js`.

### Agent B, from the gateway

The gateway opens the session itself, authenticated with the API key, when your device sends `MASTER_SESSION_START`. Your device streams its microphone to the gateway as raw PCM16 binary frames; the gateway wraps each frame as `input.audio`. The agent's audio (`reply.audio`) goes back to your device as raw binary frames.

---

## 3. The events Awaaz handles

| Event | What Awaaz does with it |
|---|---|
| `session.ready` | The session is configured; audio may flow |
| `session.updated` | Confirms a mid-session prompt change |
| `reply.started` | The agent is speaking. Any new instruction must now wait (see lesson 1) |
| `reply.audio` | Schedule the audio chunk for playback, or forward it to your device |
| `reply.done` | The agent finished. Release queued instructions and tool results. If `status` is `interrupted`, stop playback at once (barge-in) |
| `transcript.user` | What the caller (or you) said, forwarded to your screen and your secretary's notes |
| `transcript.agent` | What the agent said. The `interrupted` flag tells us an instruction may not have been said in full |
| `tool.call` | Run the tool, then answer with `tool.result` |
| `session.error`, `error` | Surface it. Before the session is ready, end cleanly |
| `session.ended` | Clean up |

---

## 4. The tools

### Agent A

| Tool | Parameters | What happens |
|---|---|---|
| `save_caller_details` | `name`, `company`, `reason`, `urgent`, `message`, `callbackNumber`, `callbackEmail`, `bestTime` | The caller page sends them to the gateway (`CALLER_DETAILS`). The gateway cleans them before merging them with what it had: spoken digits become digits, a number needs at least 7 digits, spoken "at" and "dot" become `@` and `.`, and an invalid number or email is dropped rather than stored. Then it updates your screen and briefs your secretary |
| `end_call` | — | The caller page ends the call once the goodbye has finished playing |

### Agent B

| Tool | Parameters | Becomes |
|---|---|---|
| `connect_caller` | — | `MASTER_COMMAND connect`, then the `patchedToMaster` instruction, then the live bridge |
| `hold_caller` | `minutes` | `hold`, then `holding` (1 to 30 minutes) |
| `relay_message` | `message` (up to 300 characters) | `relay`, then a `custom` instruction |
| `add_task` | `task`, optional `due` | `task`: saved with the call. A restatement within 10 seconds replaces the last one |
| `end_call` | — | `end`, then `declined`. Held until you've been quiet for 2.5 s after her last answer |

Tools are declared with JSON Schema in `SECRETARY_TOOLS` (`server.js`) and `TOOLS` (`master-session.js`).

---

## 5. Steering agent A with your decisions

When you decide something, agent A has to say it, in the middle of a live conversation. Awaaz does this with **`reply.create` carrying instructions**. The caller page builds one per decision (`buildDirectiveInstructions` in `caller.html`):

| Decision | The instruction, in short |
|---|---|
| Hold | "Kabeer has asked the caller to hold for about N minutes. Tell the caller this politely now." |
| Put through | "Kabeer has decided to take this call. Tell the caller you're connecting them, and ask them to stay on the line." |
| Decline | "Kabeer can't take this call now… before you say goodbye, make sure you can reach them: a number or email and the best time. Read it back… then call `end_call`." |
| Check in | "The hold time is up… ask whether they'd like to keep holding or leave a message." |
| Relay | "Kabeer has sent you this message to pass on: "…". Relay it in your own words. If it's written as 'I', talk about Kabeer." |

Every instruction ends with *"Speak as Kabeer's secretary and refer to Kabeer in the third person."* Relayed text is **sanitised** first, so quotes, newlines or fake tags in a message can't break out of the instruction and change its meaning.

The caller page reports each instruction back: `injected` when it was given to the agent, and `spoken` when she finished saying it. If the caller interrupted her mid-instruction, the instruction is retried or reported as failed.

---

## 6. Keeping your secretary up to date

Agent B's knowledge changes during the call: new details, new transcript lines, trust results, other callers. Awaaz keeps it current by **sending a new `system_prompt` with `session.update` mid-session** (`_refreshPrompt`). It contains:
- the confirmed caller details and their trust level: "Trust: verified", or not;
- any warnings, most important first;
- the latest lines of the call;
- the callers waiting on other calls.

When something needs saying now, a `reply.create` follows:
- the first identity briefing, about 0.7 s after the details arrive, so your app has time to say who the caller really is;
- an urgency note when the caller uses words like "emergency" or "hospital", at most once every 30 seconds.

---

## 7. Lessons from the live API

Each of these cost us a debugging session. All are handled in the code.

1. **A `reply.create` sent while the agent is speaking is silently dropped.** There's no error and no reply; the instruction just vanishes. Awaaz **queues** instructions while a reply is active and sends them on `reply.done` (`_sendAgent` in `master-session.js`, `dispatchDirective` in `caller.html`).
2. **Right after tool results, it's dropped too.** The agent answers the tool result first and swallows an instruction sent in the same moment. Queued instructions wait **1.5 s** after tool results are sent.
3. **`tool.result.result` must be a JSON string.** An object is rejected as `invalid_format`. Send results after the `reply.done` of the reply that made the tool call.
4. **`session.update` must be the first message.** Without it the agent never becomes ready. If the persona is missing, the agent runs as a generic assistant, so the caller page refuses to start without one. `agent_id` is not a token parameter.
5. **`system_prompt` can be replaced mid-session, and the agent follows it.** `conversation.message` was accepted but ignored in practice, so live context goes into the prompt instead.
6. **Don't end a call from the tool call itself.** The agent calls `end_call` and then says goodbye in the same reply. Awaaz waits for that reply's `reply.done`, and for the audio to finish playing, before hanging up.
7. **Examples in prompts are copied literally.** A prompt example *"someone who says he's John"* made the secretary say "he's" about every caller. The example became *"someone calling as John"*, with an explicit rule: never guess whether a caller is a man or a woman.
8. **Tell the agent what it doesn't know.** Without a rule, agent B guessed names and reasons before the caller had given them. The prompt says the details are known **only** once confirmed, and to say "the secretary line is still finding out" otherwise.
9. **Spoken numbers need normalising.** Callers say "oh three zero one…". The gateway converts digit words to digits (`spokenDigits`), so the task's call button dials the right number.
10. **A detached `ArrayBuffer` has length 0.** After an AudioWorklet posts a chunk with a transfer, the original buffer is empty. Read the size before transferring.
11. **Language support is specific.** The Voice Agent API speaks English, Spanish, French, German, Italian and Portuguese. For other languages, Awaaz tells the secretary to ask the caller to continue in English rather than guess. AssemblyAI's real-time transcription (Universal-3.5 Pro Realtime) does understand Urdu, which is the path on the [roadmap](ROADMAP.md).

---

## 8. The LLM Gateway, after the call

`POST /api/analyze-call` sends the call's transcript to `https://llm-gateway.assemblyai.com/v1/chat/completions` (model `qwen3.5-4b-32k-fast`). It asks for a JSON object:

```json
{"summary": "one sentence for the call log",
 "actionItem": "the most important follow-up, or null",
 "sentiment": -1.0}
```

Your words are labelled "Kabeer" and the rest keep their speaker. The reply is tidied, and the fields are length-limited and clamped. If the model call fails, a keyword-based summary is returned, so the record is never empty.

---

## 9. What it costs

AssemblyAI's Voice Agent API is priced at **$4.50 per hour ($0.075 per minute)**, all-in.
- **A typical screened call:** about 1.5 minutes of agent A, plus about 1 minute of agent B when you engage, comes to about **$0.19**.
- **The live bridge costs nothing in AI:** once you're connected, the gateway relays audio itself.
- **The post-call summary** is a fraction of a cent.

---

## 10. Code map

| Concern | Where |
|---|---|
| Agent A's persona, greeting, voice, tools | `gateway/server.js`: `SECRETARY_SYSTEM_PROMPT`, `SECRETARY_GREETING`, `SECRETARY_VOICE`, `SECRETARY_TOOLS` |
| Token minting | `gateway/server.js`: `GET /api/voice-token` |
| Agent A session, instructions, barge-in, wrap-up | `gateway/web/caller.html` |
| Mic capture and resampling | `gateway/web/pcm-processor.js` |
| Agent B session, live prompt, tools, queueing | `gateway/master-session.js` |
| Commands to buttons (app) | `app/lib/providers/call_provider.dart`: `_runVoiceCommand` |
| Commands to buttons (owner page) | `gateway/web/owner.html`: `runVoiceCommand` |
| Summaries | `gateway/server.js`: `analyzeWithLlm`, `analyzeWithKeywords` |
