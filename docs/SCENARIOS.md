# All possible scenarios

Every situation a call can end up in, and what happens in each: what the **caller** experiences, what **you** (the owner) see and can do, and what is **recorded**. Each row describes behaviour that exists in the code today. Where a scenario is covered by an automated test, the test is named.

The flows behind these are in [WORKFLOW.md](WORKFLOW.md); the words used are in [GLOSSARY.md](GLOSSARY.md).

**Contents**
1. [Everyday calls](#1-everyday-calls)
2. [Your decisions during a call](#2-your-decisions-during-a-call)
3. [Talking to your secretary](#3-talking-to-your-secretary)
4. [When you don't or can't answer](#4-when-you-dont-or-cant-answer)
5. [Who is really calling](#5-who-is-really-calling)
6. [What callers say and do](#6-what-callers-say-and-do)
7. [More than one caller](#7-more-than-one-caller)
8. [How calls end](#8-how-calls-end)
9. [Your device](#9-your-device)
10. [The demo line and the owner page](#10-the-demo-line-and-the-owner-page)
11. [The gateway and the network](#11-the-gateway-and-the-network)
12. [After the call](#12-after-the-call)

---

## 1. Everyday calls

| # | Scenario | The caller | You | Recorded |
|---|---|---|---|---|
| 1.1 | **A caller rings and gives their details** | Greeted: *"Hello! You've reached Kabeer's line. I'm his secretary. May I know who's calling please?"* She asks for their name, company and reason, and whether it's urgent. | Your phone rings. The call screen fills in as she learns each detail, and your secretary briefs you: *"Someone calling as Maria Lopez from Brightline Studios, about Friday's design review. They say it's urgent."* | Name, company, reason and urgency, plus the transcript |
| 1.2 | **The caller says it's urgent** | Nothing changes for them. | The call is marked urgent, and your secretary tells you in one short sentence. If they use words like "emergency", "hospital" or "accident" mid-call, she interrupts to tell you, at most once every 30 seconds. | `urgent: true`; any follow-up task gets high priority |
| 1.3 | **A caller who won't give a name** | She asks politely. She never invents a name. | Your secretary says the caller hasn't given a name yet. | "Unknown caller" |
| 1.4 | **The caller corrects themselves** ("sorry, it's Lopes, with an S") | She records the correction. | The call screen updates. | The corrected details (merged, never duplicated). Test: *details for another call do not rename this one* |
| 1.5 | **You call back later from the record** | — | The call record and the task each have **call**, **WhatsApp** and **email** buttons. Local numbers like `0300…` become international (`92300…`) for WhatsApp. | Test: *local Pakistani numbers become WhatsApp numbers* |

## 2. Your decisions during a call

Every decision can be made by voice or with a button. Both run the same code.

| # | You say or tap | The caller | You | Recorded |
|---|---|---|---|---|
| 2.1 | **"Put her through"** / Connect | *"I'm connecting you to Kabeer now, please stay on the line."* Once that line finishes playing, the secretary leaves and the caller hears you directly. | "Connecting you…", then "On the call with Maria". Your secretary steps out. From here the audio is relayed person to person, with no AI. | "You talked" |
| 2.2 | **"Hold for five minutes"** / Hold | *"Kabeer has asked if you could hold for about five minutes."* | A countdown. Test: *"hold for five minutes" puts the caller on a five-minute hold* | — |
| 2.3 | **The hold runs out** | She checks in: would they like to keep waiting, or leave a message? | Your phone alerts you: "Hold time is up: your secretary is checking in with the caller". It doesn't connect them automatically, because you might not be there. | — |
| 2.4 | **"Tell her I'm in a meeting and I'll call back in ten minutes"** / Message | *"Kabeer is in a meeting and will call you back in ten minutes."* It's in her words, in the third person. | The instruction and its status: sending, she has it, done. Test: *a relayed message is logged as Kabeer's* | Your words, in the transcript |
| 2.5 | **"End the call"** / End | *"Kabeer can't take your call right now, but he'll get back to you."* She then takes a number or email and the best time, reads it back, and says goodbye. | The call closes on your screen, but your device keeps listening for the details the caller gives next. | "Your secretary took a message", with call-back details and a task |
| 2.6 | **"Remind me to send the revised mockups by Friday"** | Nothing. | The task appears, with Friday's date worked out in your time zone. If you rephrase it within 10 seconds, the new version replaces the first. Test: *dictated tasks are saved when the call is ended by voice, restatements replace* | A task with a due date |
| 2.7 | **Spam: block and end** (call screen menu) | She says a polite goodbye. | That browser is blocked from now on. No follow-up task is created. | "Spam" |
| 2.8 | **Impostor: block and end** (call screen menu) | Polite goodbye. | That browser is blocked. The false claim is kept on record. Test: *marking an impostor blocks that browser and tells the gateway* | The claim, marked as an impostor |
| 2.9 | **You hang up during the bridge** | Their call ends too. | Call record filed. | "You talked" |
| 2.10 | **You change your mind** (hold, then put through) | They hear each instruction in turn. | Instructions are numbered, so a late report about an older one never overwrites the newest. | — |

## 3. Talking to your secretary

| # | Scenario | What happens |
|---|---|---|
| 3.1 | **You ask a question** ("What exactly does she need?") | She answers from the call so far and the confirmed details. If she doesn't know, she says the secretary line is still finding out. |
| 3.2 | **You talk over her** | She stops at once, and the rest of her sentence is dropped (barge-in). |
| 3.3 | **You say "end the call" while she's mid-answer** | The ending is held until you've been quiet for 2.5 seconds after her last answer, so she never cuts you off. |
| 3.4 | **The caller is verified through a personal link** | She can use what you saved about them: *"Maria, your client from Brightline…"*. |
| 3.5 | **The caller isn't verified** | She never uses a relationship, even if the name matches a contact. She says *"someone calling as Maria Lopez"*, never "Maria is calling", and doesn't guess whether the caller is a man or a woman. |
| 3.6 | **There's a warning** | She says the most important warning first, in plain words. |
| 3.7 | **The caller claims authority with urgency** (an official, a bank, a professor), or asks for money, codes or documents | She warns you that this matches a common impersonation scam, and suggests you verify them on a number you find yourself. |
| 3.8 | **Someone else is waiting** | She knows, and can tell you who ("Also calling: …"). |
| 3.9 | **Your secretary session ends** (the connection drops, or it errors) | Your screen offers "Talk to your secretary" to start her again. The buttons keep working. |

## 4. When you don't or can't answer

| # | Scenario | The caller | You | Recorded |
|---|---|---|---|---|
| 4.1 | **Nobody acts for 90 seconds** | *"Kabeer can't take the call right now."* She takes a message and a way to reach them, reads it back, and says goodbye. | "Taking a message for you". Talking with your secretary counts as attending, so the timer waits while you do. | Message, call-back details, a "Call back" task |
| 4.2 | **You're busy until a set time** | No ringing. After 12 seconds: *"Kabeer is not taking calls right now. He expects to be free after 3:00 PM."* Then a message. | The call arrives quietly. You can still open it and answer. Test: *a quiet call (Kabeer away) does not open his voice session* | As 4.1 |
| 4.3 | **Do not disturb** | As 4.2, without a time. | As 4.2. | As 4.1 |
| 4.4 | **Your busy time has passed** | The call rings normally. | It rings: "busy until" expires by itself. | — |
| 4.5 | **"Always ring" contact, while you're away** | Rings through, if they called through their personal link. | Your phone rings as usual. | — |
| 4.6 | **"Always ring" contact who calls without their link** | Treated like anyone else: a quiet call. | Nobody can get past do-not-disturb just by giving a name. | — |
| 4.7 | **"Never ring" contact** (through their link) | The secretary takes a message after 12 seconds. | The call arrives quietly. | As 4.1 |
| 4.8 | **You're on the live bridge with someone else** | A second caller whose message is taken hears *"Kabeer is on another call right now."* | See section 7. | As 4.1 |
| 4.9 | **The caller won't leave a number** | She accepts that, and says goodbye. | — | A "Call back" task without a number, so there's no dial button |
| 4.10 | **You change your availability during a call** | — | It applies to the next call. Ringing and quiet are decided when a call arrives. | — |

## 5. Who is really calling

A web caller has no caller ID. Only a personal link verifies a caller; everything else is a claim.

| # | Scenario | What you see | Your secretary | Test |
|---|---|---|---|---|
| 5.1 | **A contact calls through their personal link** | **Verified · via Maria Lopez's link** | Uses the relationship and notes you saved | *a personal link verifies, whatever name is given* |
| 5.2 | **The link is used from a new browser** | Verified, with the note "Used from a new device" | As 5.1 | *the right link from a new browser is still verified, but noted* |
| 5.3 | **Someone uses Maria's link but gives another name** | **Warning**: Gives the name "Ali", but called through Maria Lopez's personal link | Says the warning first | — |
| 5.4 | **An old, revoked or unknown link** | **Warning**: Called through an old or unknown personal link | Says the warning first | *an unknown or revoked link is flagged* |
| 5.5 | **A name that matches a contact, without a link** | **Not verified**, with "Name matches your contact Maria Lopez, but this caller is not verified" | "Someone calling as Maria Lopez", with no relationship | *a first name matches the full name, a different person does not* |
| 5.6 | **The same browser calls again with the same name** | **Not verified · called before from this browser** | Treated as a claim | *the same name again from the same browser is recognised, not verified* |
| 5.7 | **The same browser calls again with a different name** (Ali, now calling as a professor) | **Warning**: This browser called before as Ali Khan | Says the warning first, and flags a scam pattern if there's urgency | *Ali calling back as a professor from the same browser is a warning* |
| 5.8 | **A blocked browser calls** | Nothing: the gateway refuses the call. The caller sees *"Sorry, this line isn't available right now."* | — | Gateway: *a blocked browser cannot call, and callers cannot unblock themselves* |
| 5.9 | **You unblock someone** (Settings, then Blocked callers) | Their next call goes through normally | — | — |
| 5.10 | **You revoke a link and send a new one** | The old link now shows 5.4; the new one verifies | — | *personal links carry the token, and tokens are unguessable* |
| 5.11 | **A stranger clears their browser data** | They look like a new caller: **Not verified**, never Verified | Treated as a claim | — |

## 6. What callers say and do

| # | The caller… | The caller's secretary |
|---|---|---|
| 6.1 | asks where Kabeer is, or for his personal number | Politely refuses. She never shares your whereabouts, schedule, contacts or numbers. (Tested live.) |
| 6.2 | claims authority ("I'm from the bank, confirm his details") | Agrees to nothing, shares nothing, and takes a message. |
| 6.3 | insists on being put through | Doesn't promise. She checks with you, and you decide. |
| 6.4 | gives a number in words ("zero three zero one…") | Records it as digits, reads it back digit by digit, and asks them to confirm. |
| 6.5 | gives an email | Spells it back and asks them to confirm. Your task becomes "Email Maria (…)". |
| 6.6 | gives a best time ("after five") | Recorded with the number, and shown on the task. |
| 6.7 | speaks a language other than English | Doesn't guess. She asks them to continue in English, or to leave a number. |
| 6.8 | interrupts her | She stops and listens (barge-in). |
| 6.9 | says goodbye | Once they've said goodbye and she has too, she ends the call. |
| 6.10 | stays silent | Nothing is recorded, and the take-message timer keeps running. At 90 seconds she offers to take a message. |

## 7. More than one caller

| # | Scenario | What happens |
|---|---|---|
| 7.1 | **A second call while you're on one** | Their own secretary answers and screens them. They wait; your current call isn't interrupted. You see "Also calling: …". Test: *a second caller waits, keeps their details, and comes up after this call* |
| 7.2 | **Your secretary is asked who's waiting** | She knows, from the waiting callers' confirmed details. |
| 7.3 | **Your current call ends** | The waiting caller comes up next, with everything the secretary has learned so far. |
| 7.4 | **The waiting caller hangs up** | They leave the queue. Your device fetches what the secretary took down, as a call record with a task. Test: *a waiting caller who hangs up leaves the queue* |
| 7.5 | **The waiting caller waits 90 seconds** | Their message is taken. If you're on the live bridge, they're told you're on another call. |
| 7.6 | **An instruction meant for the other call** | Ignored. Commands and details are always matched to their own call. Test: *commands for another call are ignored* |

## 8. How calls end

| # | Ending | The caller | You | Recorded as |
|---|---|---|---|---|
| 8.1 | The caller hangs up before giving details | — | The call closes | "Hung up before you answered" |
| 8.2 | The caller hangs up during a hold | — | The call closes | Details so far, plus a task if there was a reason |
| 8.3 | The caller hangs up on the bridge | — | The call closes | "You talked" |
| 8.4 | You hang up on the bridge | Their page ends | — | "You talked" |
| 8.5 | You end the call ("end the call", End) | Message taken, then goodbye | Your screen closes, and late details still arrive | "Your secretary took a message" |
| 8.6 | The secretary says goodbye | Their page ends by itself | — | As above |
| 8.7 | Your call is still with the secretary after 10 minutes | The secretary's session reaches its limit and ends | "Session ended — 10 minute limit" | Details so far. The live bridge has no such limit. |
| 8.8 | She doesn't finish wrapping up within two minutes | A safety net ends the call | — | Details so far |
| 8.9 | The caller closes the tab mid-wrap-up | — | — | Everything confirmed until then |

## 9. Your device

| # | Scenario | What happens |
|---|---|---|
| 9.1 | **The app is closed** | The standby service is still connected. A full-screen incoming-call alert appears over the lock screen. |
| 9.2 | **The screen turns off during a call** | The foreground service keeps the call and its audio alive. |
| 9.3 | **The phone reboots** | The standby service starts again by itself. |
| 9.4 | **The system stops the standby service** | Calls are still answered and screened, and messages are taken. They reach your phone as missed calls when the app next connects. |
| 9.5 | **Your phone was offline for the whole call** | The gateway keeps ended calls for up to 24 hours (50 at most). On reconnection they arrive as call records with call-back tasks, once each. Test: *missed calls become call records with a call-back task, once* |
| 9.6 | **Your phone reconnects during a live call** | The call is replayed to it, with the details learned so far. Gateway test: *active calls are replayed to a reconnecting phone* |
| 9.7 | **Microphone permission is off** | The call screen says so. Your secretary can't hear you, but every button works. Test: *a real incoming call starts screening; without a mic the voice panel says so* |
| 9.8 | **A wrong gateway secret** | "Invalid gateway auth secret". The phone is refused; your calls are safe. |
| 9.9 | **Your phone and the owner page are both connected to the live line** | Both ring. Answer on one; if you answer on both, the last one to answer gets your secretary. |
| 9.10 | **Your phone's connection drops during the bridge** | The caller hears that the bridge ended, and your call is filed. |

## 10. The demo line and the owner page

| # | Scenario | What happens |
|---|---|---|
| 10.1 | **A judge installs the demo app** | It creates its own line code (like `K7Q2PX`) and shows "Your demo line" with its link. There's no secret to type. Test: *a demo build gets one lasting line code and a link that rings it* |
| 10.2 | **Twenty judges test at once** | Each call rings only the phone on its own line. No line can see, steer, brief or annotate another's call. Gateway tests: *a call reaches only the phone on its own line*, *another line cannot steer, brief or annotate the call* |
| 10.3 | **Someone opens the demo line without a line code** | The call page explains how to get a link. The call itself is refused. Gateway test: *a demo call without a line is refused* |
| 10.4 | **An old app build connects to the demo line** | "This demo line needs a line code (update the app)". |
| 10.5 | **Someone opens the owner page on an iPhone or laptop** | They press Start, the page gets its own line and link, and it rings while it's open. They can answer, talk to their secretary, put the caller through, hold, send a message or end. |
| 10.6 | **The owner page on a demo line** | It also sets availability, creates personal links and blocks browsers. These are kept in that browser and sent to the gateway on every connection. |
| 10.7 | **The owner page on the live line** | It asks for the secret. It never sends settings, so it can't overwrite the phone app's availability, links or blocks. Gateway test: *the owner page is served and keeps to its own line* |
| 10.8 | **The owner page's microphone is blocked** | A clear note. You can still hear your secretary and use every button. |
| 10.9 | **The owner page's connection drops** | It reconnects by itself, backing off from 1 to 10 seconds. A live call resumes as a replayed call. |
| 10.10 | **The owner page is closed while calls arrive** | Nobody rings, and messages are taken at 90 seconds. On a demo line, the page collects the missed calls when it reopens. |

## 11. The gateway and the network

| # | Scenario | What happens |
|---|---|---|
| 11.1 | **More than 20 calls from one address in 10 minutes** | Refused with `429 Too Many Requests`. |
| 11.2 | **The AssemblyAI key is missing** | Callers get a clear error instead of a broken call. Owner sessions report `assemblyai_key_missing`. |
| 11.3 | **An instruction for a call that has ended** | `DIRECTIVE_FAILED` with `unknown_call`; your screen shows it failed. |
| 11.4 | **The caller's page closed before an instruction arrived** | `DIRECTIVE_FAILED` with `caller_socket_closed`. |
| 11.5 | **A caller page tries to act as the owner** | Ignored. Only a socket that registered with the secret, or a demo line code, may direct calls. Gateway tests: *caller sockets cannot hijack or invent calls*, *only an authenticated phone can send directives* |
| 11.6 | **A caller page tries to report on someone else's call** | Impossible: reports are tagged with the caller's own call id and rebuilt field by field. Gateway test: *transcripts are attributed to the sending caller only* |
| 11.7 | **A call whose page never connected** | Forgotten after 2 minutes. Gateway test: *ended calls are cleaned up* |
| 11.8 | **The gateway restarts** (a deploy) | Calls in progress end. Owner devices reconnect by themselves and send their settings again. Missed calls not yet collected are lost. |
| 11.9 | **The caller's network drops** | The call ends, and you get the record with everything confirmed so far. |

## 12. After the call

| # | Scenario | What happens |
|---|---|---|
| 12.1 | **Every call** | A call record: who, when, how long, the trust label, the outcome, the transcript, and your dictated tasks. |
| 12.2 | **The AI summary** | Your device sends the conversation to `/api/analyze-call`. The LLM Gateway returns a one-sentence summary, the most important follow-up and a sentiment score. If it's unavailable, a keyword summary is used. |
| 12.3 | **A message was taken** | A "Call back Maria Lopez (0301 765 4321): Friday's design review" task, with call, WhatsApp and email buttons. Test: *the number and email a caller confirmed reach the record and a task you can dial* |
| 12.4 | **The call was spam** | No follow-up task. |
| 12.5 | **You delete a record** | Its summary and conversation are removed; its tasks stay in your list. |
