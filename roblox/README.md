# AstraLife Roblox (Rojo)

This folder is the Roblox/Rojo runtime for AstraLife. It is intentionally isolated from the existing web simulator.

## What is included

- Three autonomous roles: Scout, Gatherer, Builder
- Shared colony resource pool (`TeamResources`)
- Observe -> Memory -> Belief -> Goal -> Plan -> Action loop
- Scout resource reports to Gatherers
- Gatherers collect resources into the shared pool
- Builders construct structures from blueprints
- Construction progress and world-state attributes
- Pathfinding fallback for stuck agents
- Living World integration (W0-W7): seeded terrain, biome, climate and hydrology, living resources, hazards, ecosystem, affordance navigation, and survival transactions
- World danger -> agent survival bridge (`ObserveEnvironment`, `Escape`) so hazards drive flee behavior
- Physical surface projection for logical waypoints (logical X/Z stays authoritative, Humanoid targets are raycast onto reachable ground)
- Runtime `IntegrationVerifier` reporting `BOOTING`/`RUNNING`/`PASS`/`ERROR` from live evidence
- Reachable-source fallback with bounded route attempts when the best source is unreachable
- Runtime debug UI
- Demo world/agents are created automatically when the place is empty

## Build a Roblox place

From the repository root:

```bash
rojo build roblox/default.project.json -o AstraLife.rbxl
```

Open `AstraLife.rbxl` in Roblox Studio.

## Live sync with Roblox Studio

```bash
rojo serve roblox/default.project.json
```

Then connect the Rojo Studio plugin to the server.

## Source layout

```text
roblox/
    default.project.json
    src/
        ReplicatedStorage/
            Astra/
                Config.lua
                WorldState.lua
                Perception.lua / Memory.lua / Belief.lua / Communication.lua
                Needs.lua / Inventory.lua / Storage.lua / ResourceEconomy.lua
                RoleSystem.lua / SkillLearning.lua / SharedKnowledge.lua
                Construction.lua / Planner.lua / Brain.lua / BrainIntegrated.lua
                WorldSimulation.lua
                P2Verifier.lua ... P7Verifier.lua / ScaleVerifier.lua
                IntegrationVerifier.lua
                World/
                    TerrainGenerator.lua / WorldGrid.lua / WorldClock.lua
                    BiomeCatalog.lua / ResourceCatalog.lua / EcosystemCatalog.lua
                    ClimateModel.lua / HydrologySystem.lua / LivingResourceSystem.lua
                    HazardSystem.lua / EcosystemSystem.lua / DynamicNavigation.lua
                    AffordancePolicy.lua / EnvironmentQuery.lua / SurvivalTransaction.lua
                    WorldSnapshot.lua / WorldEventBus.lua / SeededRandom.lua
                    WorldNoise.lua / DirtyTracker.lua / WorldResourceTransaction.lua
                    W0Verifier.lua ... W7Verifier.lua
        ServerScriptService/
            AstraBootstrap.server.lua
            AstraAgentService.server.lua
            AstraWorld/
                WorldService.lua
                BiomeTerrainService.lua / ClimateHydrologyService.lua
                LivingResourceService.lua / EcosystemService.lua
                DynamicHazardService.lua / AffordanceNavigationService.lua
                SurvivalBridgeService.lua
        StarterPlayer/
            StarterPlayerScripts/
                AstraDebug.client.lua
```

## Runtime folders created in Workspace

```text
Workspace
    AstraAgents
    AstraResources
    AstraStructures
    AstraWorldState
```

If `AstraAgents` is empty, the bootstrap creates three R15 test agents automatically:

- `AstraScout`
- `AstraGatherer`
- `AstraBuilder`

You can later replace those generated agents with your own NPC models as long as they contain `Humanoid`, `HumanoidRootPart`, and `Head`, and have a `Role` attribute.

## Runtime integration status

The composed P7.5 + W7 integration state is published as attributes on the `AstraWorldState` state folder in `Workspace`:

- `P75W7IntegrationStatus`: one of `BOOTING`, `RUNNING`, `PASS`, or `ERROR`
- `I0_*` attributes: per-check live evidence sampled each update (for example `I0_AgentsOnline`, `I0_NoInboxDrops`, `I0_W6TransactionObserved`)
- `I0_FailingEvidence`: comma-separated names of currently failing checks, or `none`

Status meanings:

- `BOOTING`: no tick advancement observed yet (deltas need two verifier samples)
- `RUNNING`: ticks are advancing, but at least one required check is still failing
- `PASS`: all required live evidence holds
- `ERROR`: a runtime system raised an error, or a W-series world verifier reports `FAIL`

`PASS` is derived at runtime by `IntegrationVerifier` and is never granted from startup verifier results alone. It requires live evidence: living-world and colony ticks advancing, hydrology/resource/hazard/ecosystem systems stepping, 12/12 agents online, no dropped inbox messages, and at least one W6 survival transaction observed after the grace window (`Config.IntegrationTransactionGraceTicks` living ticks).
