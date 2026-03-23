# Registry API — Future Module

> **Status:** 🚧 Not yet implemented — [Help Wanted](https://github.com/traylinx/scoutica-protocol/issues)

## What Goes Here

The OpenAPI specification for federated registry nodes that index and serve Scoutica Skill Cards.

### Planned Files

| File | Purpose |
|------|---------|
| `openapi.yaml` | OpenAPI 3.0 spec for registry endpoints |
| `zone_access_control.md` | Data zone access rules (Zone 1/2/3) |
| `rate_limits.config.md` | Rate limiting and bot detection rules |
| `federation_protocol.md` | How registries sync with each other |

## Design References

- The registry architecture is described in the research docs under `.specs/strategy_docs/research_audits/03_PROTOCOL_AND_NETWORK_DESIGN.md`
- Rate limiting and anti-scraping rules are defined in the protocol's privacy pillar

## Contributing

This is one of the most impactful areas to contribute. If you're interested in building the registry API, please open an issue for discussion before starting work.
