# Kingdom K0 — Plug-in Core Contract

K0 is the integration boundary for Kingdom-sandbox socio-economic systems inside Roblox AstraLife.

## Ownership

K0 owns no physical-world or Agent-cognition authority.

It is explicitly read-only for:
- Agent WorldTick
- LivingWorldTick
- WorldGrid / terrain / biomes / climate / hydrology / ecology
- snapshots / replay
- Agent skills / learning / Goal / Role / memory / belief / perception
- resource stock

The only writable runtime root is:

```text
Workspace/AstraKingdomState
```

## Source adapters

`SourceReader` can read current game state from:
- `Workspace/AstraWorldState`
- `Workspace/AstraLivingWorldState` when W0/W1 are installed
- `Workspace/AstraAgents`
- `Workspace/AstraResources`
- `Workspace/AstraStructures`

No source object is mutated by K0.

## Future module contract

K1-K7 modules must:
1. depend only on K0 Core plus read-only game state;
2. write only into their own child scope under `AstraKingdomState`;
3. remain functional when WorldSim W-series is absent;
4. consume W-series state when present without recreating it;
5. never write Skill XP, Role, Goal or cognition state.

## Acceptance

Runtime:

```text
Workspace.AstraKingdomState.K0Status == "PASS"
```

The verifier also publishes observed Agent/LivingWorld ticks so integration can confirm K0 is consuming, not owning, both clocks.
