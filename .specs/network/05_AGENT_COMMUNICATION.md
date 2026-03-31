# 🤖 Agent-to-Agent Communication Protocol

> **Revised 2026-03-31** — Transport-agnostic design.
> The message schema IS the protocol. The delivery mechanism is an implementation detail.

## 1. Core Message Format

Every message must adhere to the `message.schema.json` schema. Messages are transport-agnostic signed data packets.

```
{
  "$schema": "https://schema.scoutica.com/v1/message.schema.json",
  "message_id": "msg_9f1b2c",
  "type": "opportunity.offer",
  "sender": {
    "card_url": "https://github.com/traylinx/.scoutica/recruiter_profile.json",
    "pubkey": "npub1abc...",
    "signature": "..."
  },
  "recipient": "https://github.com/candidate/card",
  "conversation_id": "conv_a3e8f1",
  "timestamp": "2026-03-25T14:30:00Z",
  "ttl_hours": 168,
  "transport_used": "nostr",
  "payload": {
    "role_url": "https://github.com/traylinx/.scoutica/roles/req_88f9a2.json",
    "message": "We think you'd be a great fit for the AI Architect role."
  }
}
```

## 2. The 8 Message Types

### Negotiation Messages (Bidirectional)

1. `opportunity.pitch` — **Either party** sends an abstract interest signal (checking waters). Employers use it to express interest in a candidate; candidates use it to express interest in a role.
   - **Payload:** `{ "message": string, "fit_score"?: number, "role_url"?: string, "card_url"?: string }`
2. `opportunity.offer` — Employer sends a specific, structured `role.json` with full compensation data.
   - **Payload:** `{ "role_url": string, "message"?: string, "compensation_summary"?: { "base_min": number, "base_max": number, "currency": string } }`
3. `rules.check` — Pre-flight ping to see if the other party is open/available before sending a full offer.
   - **Payload:** `{ "engagement_type"?: string, "seniority"?: string, "location"?: string }`
   - **Response:** `{ "status": "open" | "unavailable" | "paused", "availability"?: string, "zone_1_data"?: object }`

### Response Messages

4. `response.accept` — Candidate/Employer agent agrees to proceed (shares Zone 2 contact info).
   - **Payload:** `{ "calendar_url"?: string, "email"?: string, "message"?: string, "preferred_compensation"?: number }`
5. `response.reject` — Agent auto-declines (failed `rules.yaml` or `hiring_rules.yaml`).
   - **Payload:** `{ "reasons": string[], "auto_rejected": boolean, "fit_score"?: number }`
6. `response.withdraw` — Either party terminates the conversation thread.
   - **Payload:** `{ "reason"?: string }`

### Lifecycle Messages

7. `status.check` — Follow-up ping to check if a conversation is still active (used for ghosting detection).
   - **Payload:** `{ "conversation_id": string, "days_since_last_response": number }`
   - **Response:** `{ "status": "active" | "paused" | "closed", "message"?: string }`
8. `event.ghosting` — Logged when a party fails to respond within the SLA defined in their rules. Recorded in the sender's local transparency log and optionally published as a signed event for trust computation.
   - **Payload:** `{ "conversation_id": string, "ghosted_by": string, "days_without_response": number, "last_message_type": string, "last_message_id": string }`

## 3. Transport Resolution Waterfall

The protocol defines HOW to find the recipient's inbox. The sender follows this resolution order:

```
GIVEN: recipient's scoutica.json

Step 1: CHECK agent_endpoint
  IF scoutica.json.contact.agent_endpoint exists:
    → POST message to endpoint (HTTP Webhook)
    → IF 2xx: DELIVERED. Stop.
    → IF error: fall to Step 2.

Step 2: CHECK nostr transport
  IF scoutica.json.transport.nostr.pubkey exists:
    → Publish signed Nostr event to declared relays
    → DELIVERED (async). Stop.

Step 3: FALLBACK to Git-Native Inbox
  → Create message file: registry/inbox/<recipient_hash>/<msg_id>.json
  → Candidate retrieves via: scoutica inbox

Step 4: UNREACHABLE
  → Log "delivery_failed"
  → Sender moves to next candidate
```

## 4. Conversation Flow

```
RECRUITER AGENT                          CANDIDATE AGENT

1. rules.check ─────────────────────►  Evaluate availability
                                        ◄──── response: "open, in_2_weeks"

2. opportunity.offer ───────────────►  Run deterministic matching
   (role.json + compensation)           vs rules.yaml
                                        │
                              ┌─────────┴──────────┐
                              │                      │
                        Rules FAIL              Rules PASS
                              │                      │
              ◄── response.reject           ◄── response.accept
              (reasons: salary_below)       (calendar_url, email)

3. [If accepted: human interview process happens off-protocol]

4. [If silence > SLA]:
   status.check ────────────────────►  
                                        ◄──── response or silence

5. [If silence > 14 days]:
   Log event.ghosting locally
   Publish ghosting event (Nostr)
   Trust score impact applied
```

## 5. Authentication Tiers

- **`V1` GitHub Identity:** Validate sender by checking that `sender.card_url` repository exists and the GitHub username matches. Simple, zero-crypto.
- **`V2` Nostr Signatures:** Messages are signed Nostr events. Sender identity = Nostr pubkey. Signature verification is built into the protocol. Tamper-proof.
- **`V3` DNS + Domain Binding:** For organizations, `nostr.pubkey` is confirmed via DNS TXT record (`_scoutica-nostr.example.com TXT "npub1..."`). Prevents impersonation.

## 6. Anti-Spam Enforcement

- If an employer agent drops a connection, ignores an acceptance, or ghosts, the Candidate Agent logs an `event.ghosting` event.
- Excess ghosting drops the employer's `trust_score` on the aggregated interaction logs.
- If `trust_score < 40`, Candidate Agents auto-block incoming `opportunity.pitch` messages.
- Mass-pinging (>50 offers in 24h with >80% rejection rate) triggers an automatic `spam_flag` and 7-day cool-down.
- On Nostr: relays can enforce NIP-13 proof-of-work for messages from unknown pubkeys. This imposes computational cost on spam without requiring payment infrastructure.

## 7. Privacy Zone Enforcement in Messages

Messages carry data classified by privacy zone:

| Message Type | Data Transmitted | Zone |
|-------------|-----------------|------|
| `rules.check` response | title, seniority, domains, availability | Zone 1 (Public) |
| `opportunity.offer` | role details, compensation range, company info | Zone 1 (Public) |
| `response.accept` | calendar_url, email, preferred_compensation | Zone 2 (Gated) |
| `response.reject` | rejection reasons | Zone 1 (Public) |

**Zone 2/3 data in transit must be encrypted:**
- V1 (Git): HTTPS provides transport encryption. Message payloads containing Zone 2/3 data should be GPG-encrypted to the recipient's key.
- V2 (Nostr): NIP-44 gift-wrapped events provide end-to-end encryption. The relay cannot read Zone 2/3 data.

**Critical rule:** Zone 3 data (exact salary, references) is NEVER transmitted in a message. It is shared out-of-band after bilateral agreement, using the `calendar_url` or direct communication established in `response.accept`.
