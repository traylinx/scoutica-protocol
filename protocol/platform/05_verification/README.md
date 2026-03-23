# Verification — Future Module

> **Status:** 🚧 Not yet implemented — [Help Wanted](https://github.com/traylinx/scoutica-protocol/issues)

## What Goes Here

The algorithms, formulas, and smart contracts for establishing trust and verifying identity on the Scoutica network.

### Planned Files

| File | Purpose |
|------|---------|
| `trust_score_formula.md` | 5-level trust scoring algorithm (Level 0–4) |
| `sbt_smart_contract.sol` | Soulbound Token contract for on-chain identity |
| `zkp_salary_banding.md` | Zero-Knowledge Proof for salary range verification |
| `anti_fraud_rules.md` | Sybil resistance and anomaly detection |
| `canonical_url_validation.md` | Content hash + signed manifest for anti-impersonation |

## Design References

- Trust levels and verification multipliers (0x → 2x) are described in the research docs
- The Soulbound Token approach uses Base L2 (primary) and Polygon (fallback)
- ZKP salary banding uses Semaphore/Noir circuits

## Contributing

Verification is critical for network trust. Contributions to trust scoring formulas and anti-fraud mechanisms are especially welcome.
