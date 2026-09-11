# Kingdom-sandbox → Roblox AstraLife: Society/Economy Adapter

This branch intentionally does **not** implement WorldSim infrastructure or Agent learning.

## Ownership boundary

Reserved for Living World track (#53 W0, #55 W1 and successors):
- world clock / fixed-step scheduler
- deterministic RNG / noise
- WorldGrid / terrain / biome / environment query
- snapshots / dirty tracking / world event bus
- physical climate / hydrology / ecology / terrain simulation
- materialization / LOD / world persistence owned by that track

Reserved for Agent track (#54 P7 and successors):
- skill XP / learning
- Agent role switching
- Planner / Brain / Goal ownership
- Agent memory/belief/perception changes
- outcome learning and skill effects

This adapter owns only Kingdom-sandbox-inspired socio-economic projections:
- market scarcity / price / trade health
- labor shortage / wage premium indicators
- settlement prosperity / food-water security / stability / unrest
- organization aggregate state
- governance recommendations / legitimacy
- recruitment demand recommendations
- aggregate migration pressure

## Namespace

```text
ReplicatedStorage/Astra/Kingdom/*
ServerScriptService/AstraKingdom/*
Workspace/AstraKingdomState
```

It never writes to `ReplicatedStorage/Astra/World/*` or `Workspace.AstraLivingWorldState`.

## Runtime contract

The service observes the existing Agent `WorldTick` only as a cadence source. It does not increment that clock and does not create a replacement clock.

All outputs are read-only/advisory. This adapter does not:
- change Agent Role
- change Agent Goal
- award skill XP
- move an Agent
- mutate terrain/biomes
- mutate P2 stock
- charge taxes
- recruit Agents

`Workspace.AstraKingdomState.VerifierStatus == "PASS"` is the runtime acceptance target.
