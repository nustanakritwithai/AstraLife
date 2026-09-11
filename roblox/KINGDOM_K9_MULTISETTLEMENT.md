# K9 Multi-Settlement Economy

Projection layer for local settlement economies. It reads optional `Workspace.AstraSettlements` data and publishes normalized local market state without mutating settlement truth.

Outputs per settlement: stock, demand, coverage, scarcity, price, prosperity and local state.

Fallback: if no multi-settlement source exists, K9 projects the current colony as `colony-main`.

Hard boundaries: no settlement creation, stock writes, route generation, terrain/world ownership, Agent Goal/Role/Skill changes.
