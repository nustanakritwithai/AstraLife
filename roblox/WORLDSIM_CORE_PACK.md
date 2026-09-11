# AstraLife Roblox — WorldSim Core Pack

This package ports reusable systems from the Living World / World Simulator architecture into Roblox AstraLife without taking ownership away from P1-P5 systems.

## Isolation rule

The pack is passive and additive:

- it does not create or increment `WorldTick`
- it does not modify `Brain`, `Planner`, `Needs`, `Perception`, `Construction`, `ResourceEconomy`, `Config`, or P5 `WorldSimulation`
- it observes the authoritative runtime and projects additional simulation state
- advisory systems never change Agent Role/Goal or move an Agent
- world modifiers are exposed as attributes; they do not mutate base stats or WalkSpeed
- injury is a separate world-outcome state and does not write HP
- economy/labor/governance calculate indices and recommendations; they do not spend stock, tax players, or write gameplay truth

## Ported systems

| WorldSim concept | Roblox module | Runtime output |
|---|---|---|
| deterministic ordering / seeded randomness | `WorldSimDeterminism.lua` | stable hash/RNG/fingerprint helpers |
| WorldGrid / canonical position | `WorldSimGrid.lua` | stable `x:z` cells |
| world-tick snapshots | `WorldSimSnapshot.lua` | sorted Agent/Resource/Structure snapshot + fingerprint |
| deterministic serialization contract | `WorldSimSerialization.lua` | canonical text representation of a snapshot |
| replay / regression identity | `WorldSimReplay.lua` | bounded 240-tick fingerprint log |
| observed intent ordering | `WorldSimIntentQueue.lua` | stable order of already-selected Agent goals |
| stock-demand-scarcity economy | `WorldSimEconomy.lua` | demand, scarcity, price, volatility, trade health |
| labor market | `WorldSimLaborMarket.lua` | shortage-driven wage premium + best profession opportunity |
| personality | `WorldSimTraits.lua` | bravery, greed, loyalty, ambition, risk tolerance, discipline |
| learn-by-doing skills | `WorldSimSkills.lua` | 15 skills + XP/level growth from current actions |
| motives | `WorldSimMotives.lua` | survival, wealth, safety, loyalty, revenge, ambition, duty, trade, power, family-clan, fear + Astra extensions |
| personal history | `WorldSimPersonalHistory.lua` | bounded life events + career/crisis transitions |
| relationships | `WorldSimRelationships.lua` | score/trust/fear/respect/rivalry/gratitude/grudge/loyalty with decay/pruning |
| psychology | `WorldSimPsychology.lua` | fear, stress, morale and psychology state |
| injury separated from HP | `WorldSimInjury.lua` | injury severity/type/cause from world outcomes |
| effective world modifiers | `WorldSimModifiers.lua` | move/work/perception/combat/reasoning multipliers |
| settlement health | `WorldSimSettlement.lua` | prosperity/danger/stability/unrest/food-water security |
| governance projection | `WorldSimGovernance.lua` | suggested tax/security/relief policy + legitimacy |
| recruitment demand | `WorldSimRecruitment.lua` | role shortage/targets/urgency; never changes Role |
| migration pressure | `WorldSimMigration.lua` | stay/consider/refuge/leave pressure; never moves Agent |
| territory | `WorldSimTerritory.lua` | claimed WorldGrid cells and frontier |
| safe/danger zones | `WorldSimZones.lua` | Safe/Caution/Danger classification from territory + threats |
| route graph | `WorldSimRoutes.lua` | strategic base/structure/resource node graph |
| hydrology | `WorldSimHydrology.lua` | water nodes/cells/access/recharge/drought pressure |
| ecology | `WorldSimEcology.lua` | resource population, occupied cells and regeneration pressure |
| threats | `WorldSimThreats.lua` | threat pressure, unsafe population and threat hot cell |
| strategic situation | `WorldSimSituation.lua` | crisis/recovery/expansion classification + suggested focus |
| organizations | `WorldSimOrganization.lua` | colony membership/roles/reputation/reserves |
| population abstraction | `WorldSimPopulation.lua` | population, role, injury, critical and spatial aggregates |
| materialization LOD | `WorldSimLOD.lua` | A Full / B Reduced / C Abstract classification |
| liveness observability | `WorldSimMetrics.lua` | tick, skill, injury, relation and world health counters |
| data hygiene | `WorldSimDataHygiene.lua` | cap/reference/count health checks |
| runtime acceptance | `WorldSimVerifier.lua` | `WorldSimCoreStatus=PASS/RUNNING/ERROR` |

`AstraWorldSimService.server.lua` attaches the pack to the existing authoritative `WorldTick`. It is an observer/projection service and explicitly sets `OwnsWorldTick=false`.

## Workspace projection

```text
Workspace
  AstraWorldSim
    Market
    Labor
    Ecology
    Threats
    Settlement
    Relationships
    Territory
    Routes
    Organization
    Population
    Migration
    Governance
    Recruitment
    Zones
    Hydrology
    Situation
    IntentQueue
    DataHygiene
    Metrics
    Replay
```

Agent models receive additional attributes such as:

```text
Trait_*
Skill_* / SkillXP_*
Motive_*
DominantMotive
PsychologicalFear / PsychologicalStress / Morale / PsychologyState
InjurySeverity / InjuryType / InjuryCause
WorldMod_*
RelationTopAgent / RelationTopScore / RelationTopTrust
RelationTopFear / RelationTopRespect / RelationTopRivalry / RelationTopGrudge
SimulationLOD
WorldGridCell / WorldZone / WaterAccess
OrganizationId / OrganizationRole / OrganizationRank
LaborBestProfession / LaborOpportunityScore
MigrationPressure / MigrationIntent
WorldIntentOrder
LifeEventCount / LastLifeEvent
```

## Runtime pipeline

```text
Existing authoritative WorldTick
        ↓
Traits / Skills / Motives / Injury / Effective modifiers
        ↓
Relationships
        ↓
Economy → Labor → Ecology → Threat pressure → Settlement health
        ↓
Territory → Routes → Organization → LOD → Population → Hydrology → Zones
        ↓
Psychology → Migration pressure → Governance → Recruitment → Strategic situation
        ↓
Observed intent ordering
        ↓
Stable Snapshot → deterministic serialization → Replay fingerprint
        ↓
Liveness metrics → data hygiene → runtime verifier
```

## What is intentionally not activated yet

These are the remaining high-impact World Simulator systems that should be their own isolated PRs because they would start changing gameplay truth instead of only projecting it:

1. multi-settlement world generation, independent settlement inventories and real inter-settlement trade/caravans
2. actual professions/job switching driven by labor opportunities
3. factions, diplomacy, treaties, vassalage, rebellion and government ownership
4. recruitment contracts, squads/warbands/armies and military command
5. bandit/raid/siege/combat world consequences
6. mutable ecology: resource migration/regeneration carrying-capacity rules
7. true LOD execution throttling and population simulation for distant actors
8. DataStore persistence/save migration plus full deterministic replay restore
9. integration of world modifiers into authoritative combat/skill execution

Those systems should stay isolated from P4/P5 cognition until their own authority contracts and acceptance tests are ready.
