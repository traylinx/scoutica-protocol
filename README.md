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
├── SKILL.md                        ← Agent instructions for this repo
├── docs-site/                      ← 📚 DOCUMENTATION (Mintlify site → docs.scoutica.com)
│   ├── docs.json                   ← Mintlify configuration
│   ├── introduction.mdx            ← Protocol overview
│   ├── cli/                        ← CLI command reference
│   ├── guides/                     ← User guides & use cases
│   ├── developer/                  ← Build integrations (Python/JS/Go)
│   ├── architecture/               ← 6 pillars, data model, compliance
│   └── skill-card/                 ← Card file format reference
├── .specs/                         ← 🔬 SPECIFICATIONS
│   ├── ROADMAP.md                  ← 5-phase roadmap (blockchain, SDKs)
│   ├── protocol_flows.md           ← 6 mermaid sequence diagrams
│   └── protocol_ecosystem.md       ← Ecosystem analysis
├── .agents/skills/                 ← 🤖 AGENT SKILLS
│   ├── create-skill-card/          ← Generate a card from documents
│   ├── evaluate-candidate/         ← Score candidates against jobs
│   ├── build-integration/          ← Build apps consuming cards
│   └── extend-protocol/            ← Add features to the protocol
├── schemas/                        ← JSON Schema definitions
├── tools/                          ← CLI tools (scoutica, validate)
├── templates/                      ← Card and rule templates
└── protocol/                       ← Protocol specs and examples
```

---

## How the Network Works

**Today (V1 — Live):**

```text
1. Candidate installs the CLI or uses any AI assistant
2. Generates their Skill Card (profile + evidence + rules)
3. Pushes their card to their own GitHub repo
4. Employer's AI agent discovers and scores the card locally
5. Match confirmed → candidate shares contact info directly
```

**Future Vision (V2+ — Roadmap):**

```text
1. Candidate registers on the decentralized network
2. Employer's agent finds them: npx skills find "Senior AI Engineer"
3. Agent scores fit using Zone 1 (free) data
4. Employer pays ~$0.05 to unlock Zone 2 (full profile) → goes to candidate
5. Match confirmed → candidate approves Zone 3 handoff (contact info)
```

**Target cost to hire:** ~$4 total · **LinkedIn Recruiter:** ~$10,000/year · **Agency:** ~$15,000–$30,000/hire

---

## Quick Start — Create Your Card in 5 Minutes

Choose the method that works best for you:

### Option 1: CLI Install (Recommended for Devs)

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

→ Creating directories in /Users/sebastian/.scoutica...
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
Scoutica CLI v0.1.0
Your skills. Your rules. Your data.

Usage:
  scoutica <command> [options] [directory]

Commands:
  init              Create your Skill Card (interactive wizard)
  init --ai         Create card using AI assistant
  scan              Auto-generate card from your documents (AI-powered)
  resolve           Fetch and display a card from a URL
  validate          Validate card against protocol schemas
  publish           Push card to GitHub
  preview           Build HTML layout and publish to here.now
  info              Show card summary
  update            Update the Scoutica CLI to the latest version
  help              Show this help
  version           Show version

Examples:
  # Create your card in the current directory
  scoutica init

  # Create card in a specific folder
  scoutica init ./my-card

  # Validate, preview, and publish
  scoutica validate && scoutica preview && scoutica publish

  # Auto-generate card from your CV folder
  scoutica scan ~/CV/
```

### AI Zero-Effort Mode

Put your CV, certs, and portfolio in a folder and let AI extract your skill card automatically. No server required.

```bash
scoutica scan ~/my-docs/                  # auto-detects installed CLI
scoutica scan ~/my-docs/ --with gemini    # use a specific provider
scoutica scan ~/my-docs/ --clipboard      # copy prompt to clipboard (no CLI needed)
```

Your data never leaves your machine — everything runs through your local AI CLI.

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

### Option 2: Paste Into Any AI (Easiest — No Install Needed)

1. Open [`GENERATE_MY_CARD.md`](GENERATE_MY_CARD.md) on GitHub
2. Copy the entire file contents
3. Paste it into **any AI assistant** — ChatGPT, Claude, Gemini, Copilot, etc.
4. Follow the conversation — the AI will interview you and generate your 4 files
5. Save the files to a GitHub repo → your card is live

> **This is the recommended path for non-technical users.** No git, no CLI, no install.

### Option 3: Use the GitHub Template (One Click)

1. Click **"Use this template"** on the [Scoutica Protocol repo](https://github.com/traylinx/scoutica-protocol)
2. Name your repo (e.g., `my-scoutica-card`)
3. Edit the files in `protocol/templates/` with your data
4. Push → done

### Option 4: Clone and Customize (Full Access)

```bash
git clone https://github.com/traylinx/scoutica-protocol.git
cp -r protocol/templates/ my-card/
python tools/validate_card.py ./my-card/
```

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
