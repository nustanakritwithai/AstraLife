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
        Memory.lua
        Belief.lua
        Communication.lua
        Perception.lua
        Construction.lua
        Planner.lua
        Brain.lua
    ServerScriptService/
      AstraBootstrap.server.lua
      AstraAgentService.server.lua
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
