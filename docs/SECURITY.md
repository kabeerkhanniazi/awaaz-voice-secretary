# Security and privacy

How Awaaz protects the owner, the caller and the keys, and what it deliberately doesn't store.

---

## Trust boundaries

```
  Anyone on the internet            Your gateway (Railway)              Your devices
 ┌────────────────────────┐        ┌────────────────────────┐        ┌────────────────────┐
 │ Caller page             │ HTTPS  │ Holds the API key      │  WSS   │ Android app         │
 │ - no key, no secret     │◄──────►│ Checks every socket's  │◄──────►│ Owner page          │
 │ - a single-use token    │  WSS   │ role and line          │        │ - the secret, or a  │
 │ - its own call only     │        │ Rate limits, caps      │        │   demo line code    │
 └──────────┬──────────────┘        └──────────┬─────────────┘        └────────────────────┘
            │ WSS (token)                      │ WSS (API key, server-side)
            ▼                                  ▼
      AssemblyAI (agent A)               AssemblyAI (agent B, LLM Gateway)
```

Everything travels over TLS: HTTPS and WSS, terminated by the host.

---

## Keys and secrets

| Secret | Where it lives | Protection |
|---|---|---|
| `ASSEMBLYAI_API_KEY` | Server environment only (a Railway variable). The demo line references the live one's, so it's entered once | Never sent to a browser. Callers get **single-use tokens** from `/api/voice-token`, valid for 5 minutes, and sessions are capped at 10 minutes |
| `GATEWAY_AUTH_SECRET` | Server environment, the owner's phone, and optionally the owner page | The phone keeps it in the **Android Keystore** (`flutter_secure_storage`). The gateway hashes both sides with SHA-256 and compares them in **constant time** (`crypto.timingSafeEqual`), so timing reveals nothing. The owner page keeps it in the browser only if you tick "Remember on this device" |
| Demo line codes | The demo phone or owner page | Six random characters. They grant the owner role for that line only. A demo deployment has no secret, and no line can reach another's calls |
| Personal-link tokens | Your phone (or owner page) and your gateway's memory | Ten characters from a 32-character alphabet, about 50 bits, made with a secure random generator. Revocable at any time |

**Publishing hygiene:**
- Every push to this repository first goes through a **secret scan**. It checks every file that would be published against the actual values in the maintainer's `.env`, and against common key patterns (hex keys, `sk-` keys, Google and GitHub tokens, private keys, UUID-style tokens). It stops the push if anything matches.
- CI runs with **no secrets**.
- Internal notes, keystores and build output are never copied into this repository.

---

## Who may do what

Every WebSocket starts anonymous and gets a role by registering:

| Role | How it's earned | What it may do |
|---|---|---|
| **Caller** | `REGISTER_CALLER` for a call that exists and has no caller yet | Report on **its own call only**: transcript lines, caller details, instruction status, bridge ready. Every report is tagged with that call's id and rebuilt field by field, so nothing else passes through |
| **Owner** | `REGISTER_MOBILE` with the secret (or, on a demo deployment, a line code) | Answer, direct and bridge calls **on its own line**, start its secretary, and send its settings |
| Anonymous | — | Nothing |

- **Instructions for another line's call are treated as unknown** (`DIRECTIVE_FAILED`), so one demo phone can't steer another's call.
- **The live bridge relays audio only** between the caller and the owner device that put the call through.
- These rules are tested in `gateway/test/concurrent_routing.test.js` and `gateway/test/demo_lines.test.js`.

---

## Abuse controls

| Control | Detail |
|---|---|
| Rate limits | 20 requests per IP address per 10 minutes on `/api/call` and `/api/voice-token` (and on demo-line summaries). Over the limit: `429` |
| Size caps | WebSocket messages 64 KB; call registration 16 KB; post-call analysis 512 KB; transcript lines 2,000 characters; notes per call 200 |
| Input cleaning | Control characters are stripped. Names, companies, notes, warnings and links have maximum lengths. Phone numbers and emails are normalised, and invalid ones are dropped |
| Prompt injection | A message you relay is sanitised before it goes into the secretary's instructions, so quotes, newlines or fake tags in it can't break out and change them. Tested: *directive with quotes, newlines, and fake tags cannot escape delimiter structure* |
| Blocking | A browser the owner marks as spam or an impostor is refused at `/api/call` (`403`, *"Sorry, this line isn't available right now."*). Callers can't unblock themselves |
| Stale calls | A registered call whose page never connected is forgotten after 2 minutes |
| Paid endpoints | `/api/analyze-call` calls an LLM, so only the owner may use it: the secret, or a demo line that is registered right now |

---

## Caller trust (anti-impersonation)

A web caller has no caller ID, so Awaaz never presents a claim as fact:

1. **Only a personal link verifies.** A link's token is checked by the gateway against the owner's links for that line. A call through it is "Verified · via Maria's link".
2. **Claims stay claims.**
   - A name that matches a contact is shown as a match, never with the contact's relationship.
   - The owner's secretary says "someone calling as…", and never uses a relationship for an unverified caller.
3. **History raises warnings.** Each caller browser has a random, anonymous id. If it called before under another name, the call shows a warning ("This browser called before as Ali Khan"). So do a link used with the wrong name, and an old or revoked link.
4. **Scam patterns are flagged.** Claimed authority plus urgency, or requests for money, codes or documents, get a spoken warning, with the advice to verify on a number the owner finds themselves.
5. **"Always ring" and "never ring" apply only to calls through a personal link**, so nobody gets past do-not-disturb by giving a name.

The browser id is not a fingerprint. It is a random UUID in that browser's storage, and it goes nowhere but the owner's gateway. Clearing it makes a caller look new, never verified.

---

## What the secretary will and won't say

The caller's secretary follows privacy rules in her prompt:
- She never shares the owner's whereabouts, schedule, contacts or phone numbers.
- She agrees to nothing, and shares nothing, when a caller claims authority.
- She never invents a name, company or reason.
- She speaks English only, and doesn't guess at a language she can't understand.

The owner's secretary mentions only confirmed facts, and says the most important warning first.

---

## What is stored, where, and for how long

| Data | Where | How long |
|---|---|---|
| Call records, transcripts, summaries, tasks | The owner's phone, or the owner page's browser storage | Until the owner deletes them |
| Contacts, personal links, blocked browsers, availability | The owner's phone (or the owner page on a demo line). A copy of the settings is kept in the gateway's memory for routing | Until changed |
| A live call: details, transcript notes | Gateway memory | While the call is live |
| Ended calls the phone hasn't collected yet | Gateway memory | Up to 24 hours, at most 50 |
| Audio | Not stored by Awaaz. It streams between the browser, the gateway and AssemblyAI in real time | — |
| Caller browser id | The caller's own browser storage | Until they clear it |

The caller page shows no transcript. The caller sees only the call status.

---

## Hardening next

These are on the [roadmap](ROADMAP.md):
- **Accounts,** with per-owner keys instead of one secret per deployment.
- **Persistence** with encryption at rest, plus retention controls: export and delete.
- **One-time codes** to verify strangers by email.
- **A notice to callers** that an AI secretary is answering, where local rules require one.

---

## Reporting a vulnerability

Please email **mu.kabir2004@gmail.com** with the details and steps to reproduce. Please don't open a public issue for security problems.
