# 🌌 Stargate Integration — ARCHIVED

> **Status:** ⚠️ ARCHIVED — 2026-03-31
>
> This document described how Scoutica would run on the Traylinx Stargate P2P mesh.
> After architectural review, coupling the protocol to proprietary infrastructure was
> identified as incompatible with Scoutica's open protocol thesis.
>
> **The new transport architecture is defined in:**
> - [13_TRANSPORT_ARCHITECTURE.md](./13_TRANSPORT_ARCHITECTURE.md) — Layered transport ADR
> - [05_AGENT_COMMUNICATION.md](./05_AGENT_COMMUNICATION.md) — Transport-agnostic messaging
> - [06_IMPLEMENTATION_ROADMAP.md](./06_IMPLEMENTATION_ROADMAP.md) — Revised build plan
>
> **Decision:** Scoutica uses Git-native (V1) and Nostr (V2) as its open transport layers.
> Stargate may be offered as a premium enterprise acceleration tier in the future,
> but it is not part of the protocol specification or implementation path.

---

## Historical Context (preserved for reference)

The original vision mapped Scoutica protocol requirements to Traylinx infrastructure:

| Scoutica Requirement | Traylinx Solution | Status |
|---------------------|-------------------|--------|
| Identity verification | Sentinel Agent Secret Token | ❌ Replaced by Nostr keypairs |
| Discovery & Search | Agent Registry | ❌ Replaced by GitHub registry + Nostr relays |
| Messaging | Stargate `node.call()` | ❌ Replaced by Git-native inbox + Nostr events |
| Trust & Reputation | Sentinel Activity Monitoring | ❌ Replaced by signed interaction receipts |
| NAT Traversal | Circuit Relay v2 | ❌ Not needed (Nostr relays handle offline delivery) |

### Why This Was Archived

1. **Open protocol ≠ proprietary transport.** If the spec says "you need Stargate," Scoutica is a Traylinx product, not an open protocol.
2. **Stargate is not publicly available.** Third-party devs cannot run Stargate nodes today.
3. **Nostr provides equivalent capabilities** (P2P messaging, keypair identity, relay-based delivery) without any proprietary dependency.
4. **Commercial positioning preserved.** Stargate can still be offered as a premium transport for enterprise users who need real-time multi-agent orchestration, without constraining the open ecosystem.
