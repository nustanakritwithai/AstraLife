# AstraLife Roblox — WorldSim Core Pack

This package ports the most reusable systems from the Living World / World Simulator architecture into the Roblox runtime without taking ownership away from P1-P5 systems.

## Isolation rule

The pack is passive and additive:

- it does not create or increment `WorldTick`
- it does not modify `Brain`, `Planner`, `Needs`, `Perception`, `Construction`, `ResourceEconomy`, or P5 `WorldSimulation`
- it observes the authoritative runtime and projects additional simulation state
- world modifiers are exposed as attributes; they do not mutate base stats or WalkSpeed
- injury is a separate world-outcome state and does not write HP

## Ported systems

| WorldSim concept | Roblox module | Runtime output |
|---|---|---|
| deterministic ordering / seeded randomness | `WorldSimDeterminism.lua` | stable hash/RNG/fingerprint helpers |
| WorldGrid / canonical position | `WorldSimGrid.lua` | stable `x:z` cells |
| world-tick snapshots | `WorldSimSnapshot.lua` | sorted Agent/Resource/Structure snapshot + fingerprint |
| replay / regression identity | `WorldSimReplay.lua` | bounded 240-tick fingerprint log |
| stock-demand-scarcity economy | `WorldSimEconomy.lua` | demand, scarcity, price, volatility, trade health |
| personality | `WorldSimTraits.lua` | bravery, greed, loyalty, ambition, risk tolerance, discipline |
| learn-by-doing skills | `WorldSimSkills.lua` | 15 skills + XP/level growth from current actions |
| motives | `WorldSimMotives.lua` | survival/safety/belonging/wealth/status/exploration motives |
| personal history | `WorldSimPersonalHistory.lua` | bounded life events + career/crisis transitions |
| relationships | `WorldSimRelationships.lua` | score/trust/gratitude/grudge/loyalty graph with decay/pruning |
| injury separated from HP | `WorldSimInjury.lua` | injury severity/type/cause from world outcomes |
| effective world modifiers | `WorldSimModifiers.lua` | move/work/perception/combat/reasoning multipliers |
| settlement health | `WorldSimSettlement.lua` | prosperity/danger/stability/unrest/food-water security |
| territory | `WorldSimTerritory.lua` | claimed WorldGrid cells and frontier |
| route graph | `WorldSimRoutes.lua` | strategic base/structure/resource node graph |
| organizations | `WorldSimOrganization.lua` | colony membership/roles/reputation/reserves |
| materialization LOD | `WorldSimLOD.lua` | A Full / B Reduced / C Abstract classification |
| liveness observability | `WorldSimMetrics.lua` | tick, skill, injury, relation, state-change counters |

`AstraWorldSimService.server.lua` attaches these systems to the existing authoritative `WorldTick`.

## Workspace projection

```text
Workspace
  AstraWorldSim
    Market
    Settlement
    Relationships
    Territory
    Routes
    Organization
    Metrics
    Replay
```

Agent models receive additional attributes such as:

```text
Trait_*
Skill_* / SkillXP_*
Motive_*
DominantMotive
InjurySeverity / InjuryType / InjuryCause
WorldMod_*
RelationTopAgent / RelationTopScore / RelationTopTrust
SimulationLOD
OrganizationId / OrganizationRole / OrganizationRank
LifeEventCount / LastLifeEvent
```

## Next safe ports

The next systems can build on this package without touching P4/P5 cognition:

1. labor market + profession opportunity scoring
2. multi-settlement economy and trade routes
3. organizations/factions with recruitment contracts
4. governance, treasury, tax and unrest decisions
5. strategic threat/bandit pressure
6. population/ecology abstraction for LOD-C
7. persistence serialization and deterministic replay verification

Those should remain separate from the current Agent planner until their own acceptance tests are ready.
