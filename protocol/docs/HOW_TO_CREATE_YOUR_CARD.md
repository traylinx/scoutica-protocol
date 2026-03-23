# How to Create Your Scoutica Skill Card

Your Skill Card is your node on the decentralized talent network. It's a machine-readable professional profile that AI recruiting agents can discover, evaluate, and negotiate with — on YOUR terms.

**Time needed:** ~5 minutes

---

## The Fastest Way: Use Any AI Assistant

We built a special file called **`GENERATE_MY_CARD.md`** that works with any AI coding assistant.

### Step 1: Get the Generator

Download or clone this repository:

```bash
git clone https://github.com/traylinx/scoutica-protocol.git
```

### Step 2: Open in Your AI Assistant

Open `GENERATE_MY_CARD.md` in **any** of these tools:

- **ChatGPT** (web or app) — just paste the file contents
- **Claude** (web or app) — just paste the file contents
- **Gemini CLI** — open the file in your project
- **Cursor / Windsurf / VS Code + Copilot** — open the file
- **Any other AI assistant** — it works with all of them

### Step 3: Follow the Conversation

The AI will interview you step by step:

1. **Your skills & experience** — paste your CV or answer a few questions
2. **Your rules** — set your minimum salary, remote policy, and blocked industries
3. **Your evidence** — link to your GitHub repos, articles, or portfolios

### Step 4: Get Your Card

The AI generates 4 files for you:

| File | What It Does |
|------|-------------|
| `SKILL.md` | Your main card — AI agents read this first |
| `profile.json` | Your structured skills and experience |
| `rules.yaml` | Your Rules of Engagement (salary, remote, blocked industries) |
| `evidence.json` | Links to your public work as proof |

### Step 5: Publish

Save the files to a new GitHub repository and push. That's it — your card is live on the network.

```bash
# Create your card repo
mkdir my-scoutica-card && cd my-scoutica-card

# Copy the generated files here, then:
git init
git add .
git commit -m "feat: publish my Scoutica Skill Card"
git push
```

---

## The 3 Zones of Privacy

Your data is protected by a strict 3-zone model:

| Zone | What's Shared | Who Can See It |
|------|---------------|----------------|
| **Zone 1 (Free)** | Title, top skills, availability | Everyone (AI search engines) |
| **Zone 2 (Paid)** | Full experience, evidence, capabilities | Employers who pay a micro-fee |
| **Zone 3 (Private)** | Email, phone, calendar | Only after YOU explicitly approve |

Your salary floor is **never exposed**. Agents only see pass/fail.

---

## What Happens Next?

The Scoutica Protocol is in **v0.1.0 Alpha**. Registry infrastructure is actively being built. Soon you'll be able to register your card on the federated network so employer AI agents can discover you automatically.

For now, hosting your card on GitHub prepares you for the moment the network goes live — and gives you a machine-readable professional identity you can share with any AI today.
