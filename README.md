# Scoutica Protocol

<p align="center">
  <img src="assets/logo.png" alt="Scoutica Protocol Logo" width="250" />
</p>
> **LinkedIn charges employers $10,000/year for YOUR data. You get $0. We're building the alternative: you own your skill card, AI agents do the matching — transparently, verifiably, without bias.**

> [!NOTE]
> **Current status:** The protocol, CLI, schemas, and AI-powered card generation are **live and ready to use today**. The monetization layer (micropayments, blockchain identity, $SKILL token) is on the **roadmap** and under active development.

---

## ⚠️ Two-Part Architecture (READ FIRST)

This project has a strict separation between two concerns:

| Part | What | Where | Visibility |
|------|------|--------|------------|
| **The Protocol** | Open standard, schemas, agent rules, registry API, smart contracts, templates | This repo (`scoutica/`) | 🌍 Public — anyone can clone, fork, build on it |
| **Your Skill Card** | Your personal profile, Rules of Engagement, evidence, salary floor | Your private store (e.g. `~/my-card/`) | 🔒 Private — never committed to this repo |

**The protocol is the network. Your skill card is your node on it.**

✅ **Ready to build your node?** Check out the [Candidate Onboarding Guide](protocol/docs/HOW_TO_CREATE_YOUR_CARD.md) to create your personal skill card in 15 minutes.

A user who clones this repo gets:
- JSON Schemas to validate their card
- Agent rule templates to evaluate opportunities
- Registry API spec to run their own node
- CLI tools to publish and discover cards

They do NOT get your private data. Your card lives in your own private directory and will never hit this repo.

---

## Project Structure

```text
scoutica-protocol/
├── README.md                       ← You are here
├── SKILL.md                        ← Agent instructions (candidate side)
├── RECRUITER_SKILL.md              ← Agent instructions (employer side)
├── docs/                           ← 📚 DOCUMENTATION (Astro/Starlight → docs.scoutica.com)
│   ├── astro.config.mjs            ← Starlight navigation and site configuration
│   ├── package.json                ← Docs build and validation commands
│   └── src/content/docs/           ← CLI reference, guides, and architecture
├── .specs/                         ← 🔬 SPECIFICATIONS
│   ├── ROADMAP.md                  ← 5-phase roadmap
│   └── network/                    ← Network architecture specs
│       ├── 05_AGENT_COMMUNICATION  ← Message types, transport, SLAs
│       ├── 12_ARCHITECTURE_DEEP    ← Critical path, milestones
│       └── 13_TRANSPORT_ARCH       ← Git/Nostr/Webhook waterfall
├── .agents/skills/                 ← 🤖 AGENT SKILLS
│   ├── create-skill-card/          ← Generate a card from documents
│   ├── apply-to-role/              ← Draft a card-grounded CV + cover letter for a role
│   ├── evaluate-candidate/         ← Score candidates against jobs
│   ├── build-integration/          ← Build apps consuming cards
│   └── extend-protocol/            ← Add features to the protocol
├── schemas/                        ← JSON Schema definitions
│   └── registry/                   ← Registry index schemas
├── tools/                          ← CLI tools
│   ├── scoutica                    ← Main CLI (bash + embedded Python)
│   ├── scoring.py                  ← Deterministic fit scoring engine
│   ├── import_aijs.py              ← Offline ai-job-search → Skill Card importer
│   └── validate_card.py            ← Schema validator (scoutica validate)
├── protocol/templates/            ← Card and rule templates
└── protocol/
    ├── examples/                   ← Sample candidate + employer cards
    └── registry/                   ← Seed registry data (candidates + roles)
```

---

## How the Network Works

**Today (v0.4.0 — local delivery primitives; real transport is planned):**

```text
1. Candidate installs the CLI → generates Skill Card (profile + evidence + rules)
2. Pushes card to GitHub → registers in the decentralized registry
3. Employer creates Recruiter Card → publishes structured job postings
4. Employer's agent searches registry → runs deterministic fit scoring
5. Agent queues an offer locally (Git-native PR / Nostr are the planned transports) → candidate agent auto-evaluates
6. If rules pass → accept. If rules fail → auto-reject with reasons.
7. All interactions logged for trust scoring + anti-ghosting.
```

**Transport Evolution:**

| Phase | Transport | Status |
|-------|-----------|--------|
| V1 | Git-native inbox (PRs as messages) | 🔧 Local simulation |
| V2 | Nostr relays (encrypted, decentralized) | 🔧 Planned |
| V3 | HTTP webhooks (for always-on agents) | 📋 Spec ready |

**Target cost to hire:** ~$4 total · **LinkedIn Recruiter:** ~$10,000/year · **Agency:** ~$15,000–$30,000/hire

---

## Quick Start — Create Your Card in 5 Minutes

Choose the method that works best for you:

### Option 1: Candidates (AI Zero-Effort Mode)

The easiest way to generate a Candidate Card is to give these instructions directly to an AI agent (like Claude Code, Cursor, or OpenClaw):

```text
Agent: Please install the Scoutica Protocol CLI and generate a Skill Card for my CVs in this folder.

Important constraints:
1. Ensure you are currently in the folder that contains my CV/resume files. If not, ask me which folder contains them before proceeding.
2. If the user doesn't have local AI tools (gemini, claude, ollama), run `scoutica scan . --clipboard` instead.
3. If I have PDFs, you may need `brew install poppler` for extraction.

Supported formats: .md, .txt, .pdf, .docx, .json, .yaml, .csv, .html
TTL: The preview URL generated at the end will expire in 24 hours.

Installation:
curl -fsSL https://raw.githubusercontent.com/traylinx/scoutica-protocol/main/install.sh | bash

Generation:
scoutica scan .
```

### Option 2: Manual CLI Install (Recommended for Devs)

Requires Python 3.11+ with the strict validation dependencies installed:

```bash
python3 -m pip install 'jsonschema[format]' PyYAML
```

The installer verifies these prerequisites before writing files. It never installs Python packages into your global environment.

**macOS / Linux:**

```bash
curl -fsSL https://raw.githubusercontent.com/traylinx/scoutica-protocol/main/install.sh | bash
```
```text
╔═══════════════════════════════════════════════════════╗
║                                                       ║
║   ⚡ Scoutica Protocol — CLI Installer               ║
║                                                       ║
║   Your skills. Your rules. Your data.                 ║
║                                                       ║
╚═══════════════════════════════════════════════════════╝

→ Creating directories in ~/.scoutica...
→ Downloading scoutica CLI...
→ Downloading JSON schemas...
→ Downloading card templates...
→ Downloading AI card generator...
→ Downloading validation tool...

╔═══════════════════════════════════════════════════════╗
║                                                       ║
║   ✅ Scoutica CLI installed successfully!             ║
║                                                       ║
╚═══════════════════════════════════════════════════════╝

  To get started, run:

  source /Users/sebastian/.zshrc && scoutica init
```

**Windows (PowerShell):**

```powershell
irm https://raw.githubusercontent.com/traylinx/scoutica-protocol/main/install.ps1 | iex
```

Once installed, use the built-in help to see all commands:

```bash
scoutica help
```
```text
Scoutica Protocol CLI v0.4.0
Your skills. Your rules. Your data.

Usage:  scoutica <command> [options] [directory]

🚀 Create your card:
  scan <docs-folder>   Auto-generate from your documents (easiest)
  init                 Step-by-step interactive wizard
  init --ai            Generate via AI assistant (paste your CV)
  import aijs <fork>   Convert an ai-job-search fork into a card (offline)

🔧 Manage your card:
  info     [dir]       View your card summary
  preview  [dir]       Build HTML layout and publish to here.now
  validate [dir] [--schema-dir /abs]  Validate against trusted or explicit schemas
  publish  [dir]       Push card to GitHub
  resolve  <url>       Fetch and display any card from a URL

🏢 Employer commands:
  org init             Create a Recruiter/Employer Identity Card
  org verify           Verify domain ownership (DNS TXT record)
  org publish          Push employer card to GitHub
  role create          Create a structured job posting (role.json)
  role validate [dir]  Validate role(s) against protocol schemas

🌐 Network commands:
  evaluate <card> <role>   Score fit between a candidate and role
  jobs search              Search the registry for candidates or roles
  send <url> --type ...    Send a message to another agent
  inbox                    Check for incoming messages
  reply <msg_id> --accept  Accept/reject a message
  deliver                  Push pending messages to recipients
  register <dir> --type    Generate registry entry for PR submission
  identity init            Generate your Nostr keypair

⚙️  Advanced:
  doctor   System diagnostics and health check
  status   Show local card, identity, and network state
  logs     Show recent CLI activity
  update   Update the Scoutica Protocol CLI
  help     Show this help
  version  Show version

Examples:
  # Full workflow: scan → validate → publish
  scoutica scan ~/CV/ && scoutica validate && scoutica publish

  # Score a candidate against a role (clean JSON out)
  scoutica evaluate ./my-card --role ./role.json --json

  # Scaffold an employer identity
  scoutica org init
```

### AI Zero-Effort Mode

Put your CV, certs, and portfolio in a folder and let AI extract your skill card automatically. No server required.

```bash
scoutica scan ~/my-docs/                  # auto-detects installed CLI
scoutica scan ~/my-docs/ --with gemini    # use a specific provider
scoutica scan ~/my-docs/ --clipboard      # copy prompt to clipboard (no CLI needed)
```

Document extraction happens locally. The selected AI CLI may send the full generated prompt and document text to a remote service, depending on that provider's configuration. `--clipboard` copies the same sensitive prompt to your system clipboard for user-controlled transfer.

**Supported providers** (auto-detected in this order):

| Provider | CLI | Repo |
|----------|-----|------|
| Gemini CLI | `gemini` | [google-gemini/gemini-cli](https://github.com/google-gemini/gemini-cli) |
| Claude Code | `claude` | [anthropics/claude-code](https://github.com/anthropics/claude-code) |
| OpenAI Codex | `codex` | [openai/codex](https://github.com/openai/codex) |
| Mistral Vibe | `vibe` | [mistralai/mistral-vibe](https://github.com/mistralai/mistral-vibe) |
| OpenCode | `opencode` | [opencode-ai/opencode](https://github.com/opencode-ai/opencode) |
| Ollama | `ollama` | [ollama.com](https://ollama.com) |
| switchAILocal | `ail` | [traylinx/switchAILocal](https://github.com/traylinx/switchAILocal) |

---

📗 **Learn More:** Check out the [Complete Documentation](https://docs.scoutica.com) for full commands, guides, and architecture.

### Option 3: Employers / Recruiters (Hire passively or actively)

Are you an organization looking to hire from the network? Set up your Recruiter Card:

```bash
# 1. Initialize your organization identity
scoutica org init

# 2. Verify your domain (DNS TXT record)
scoutica org verify --domain company.com

# 3. Create a structured job posting
scoutica role create

# 4. Validate and publish to GitHub
scoutica role validate roles/
scoutica org publish
```

Your roles are now live on the mesh network. Candidate agents will automatically evaluate and pitch you candidates that match your requirements.

### Option 4: AI-Powered Conversation (No Install)

1. Open [`GENERATE_MY_CARD.md`](GENERATE_MY_CARD.md) on GitHub
2. Copy the entire file contents
3. Paste it into **any AI assistant** — ChatGPT, Claude, Gemini, Copilot, etc.
4. Follow the conversation — the AI will interview you and generate your 4 files
5. Save the files to a GitHub repo → your card is live

> **This is the recommended path for non-technical users.** No git, no CLI, no install.

### Option 5: Use the GitHub Template (One Click)

1. Click **"Use this template"** on the [Scoutica Protocol repo](https://github.com/traylinx/scoutica-protocol)
2. Name your repo (e.g., `my-scoutica-card`)
3. Edit the files in `protocol/templates/` with your data
4. Push → done

### Option 6: Clone and Customize (Full Access)

```bash
git clone https://github.com/traylinx/scoutica-protocol.git
cp -r protocol/templates/ my-card/
python tools/validate_card.py ./my-card/
```

### Option 7: Already using ai-job-search? Import it

If you keep your profile in an [ai-job-search](https://github.com/MadsLorentzen/ai-job-search) fork (an independent MIT workflow by Mads Lorentzen), convert it into a Skill Card in one **offline, deterministic** step — no network, no AI, no guessing:

```bash
scoutica import aijs ~/ai-job-search --to ./my-card --salary-floor-eur 85000
scoutica validate ./my-card
```

Keep applying with ai-job-search *and* become discoverable with Scoutica off one profile. Your behavioral profile, interview stories, and salary data are never imported (data minimization). See the [bridge guide](docs/src/content/docs/guides/from-ai-job-search.mdx) and [`scoutica import`](docs/src/content/docs/cli/import.mdx).

---

## Key Decisions

| Decision | Choice | Status |
|----------|--------|--------|
| **Format** | Pure Markdown + JSON + YAML — no runtime needed | ✅ Live |
| **Distribution** | GitHub (Phase 1) → Federated registries (Phase 2) | ✅ Phase 1 Live |
| **Matching** | Agent-side (decentralized, each agent scores locally) | ✅ Live |
| **Identity** | Soulbound Tokens on Base L2 (primary), Polygon (fallback) | 🔜 Roadmap |
| **Payment** | Stripe credits (V1) → On-chain micro-fees (V2) → $SKILL token (V3) | 🔜 Roadmap |
| **Compliance** | EU AI Act High-Risk compliant by design | ✅ Live |
| **Anti-bias** | No demographic fields in schema | ✅ Live |

---

## Contributing

The Scoutica Protocol is built by its community. We welcome contributions of all kinds — protocol design, code, documentation, and ideas.

See the `platform/` folder to understand the schema and implementation, then pick an area that interests you.

*Built with the conviction that your professional identity should belong to you, not a platform.*
