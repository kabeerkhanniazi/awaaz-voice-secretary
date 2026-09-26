# Awaaz documentation

Everything about how Awaaz works, how to use it, and where it's going.

| Document | What's in it |
|---|---|
| [ARCHITECTURE.md](ARCHITECTURE.md) | The components, what each one owns, and every gateway message with its fields |
| [TECH_STACK.md](TECH_STACK.md) | Every technology and version, the tuning values, the audio formats, and why each choice was made |
| [WORKFLOW.md](WORKFLOW.md) | The life of a call, message by message, with diagrams for every branch; then how Awaaz is built, tested, released and deployed |
| [SCENARIOS.md](SCENARIOS.md) | Every situation a call can end up in (over 100), and what the caller, the owner and the record see in each |
| [VOICE_AGENT_API_NOTES.md](VOICE_AGENT_API_NOTES.md) | How both AssemblyAI agents are wired and steered, the LLM Gateway summaries, the lessons from the live API, and costs |
| [SECURITY.md](SECURITY.md) | Keys, roles, abuse controls, caller trust, what is stored and for how long, and reporting a vulnerability |
| [USER_GUIDE.md](USER_GUIDE.md) | For callers, owners (app and owner page) and judges, with a voice-command cheat sheet |
| [DEPLOYMENT.md](DEPLOYMENT.md) | Environment variables, running locally, Railway setup for both lines, building and releasing the app, rollback |
| [TESTING.md](TESTING.md) | All 62 automated checks by name, the live tests against the real API, and the release checklist |
| [ROADMAP.md](ROADMAP.md) | What's done, and what comes next: phone numbers, Urdu, accounts, iOS, teams |
| [FAQ.md](FAQ.md) | Short answers to the questions people ask first |
| [GLOSSARY.md](GLOSSARY.md) | The words used across the code and docs |

**Where to start:**
- **To try it:** [USER_GUIDE.md](USER_GUIDE.md), then [SCENARIOS.md](SCENARIOS.md).
- **To judge the use of AssemblyAI:** [VOICE_AGENT_API_NOTES.md](VOICE_AGENT_API_NOTES.md), then [WORKFLOW.md](WORKFLOW.md).
- **To run or change it:** [ARCHITECTURE.md](ARCHITECTURE.md), [TECH_STACK.md](TECH_STACK.md), [DEPLOYMENT.md](DEPLOYMENT.md), then [TESTING.md](TESTING.md).
