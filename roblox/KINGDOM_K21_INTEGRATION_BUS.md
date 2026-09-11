# K21 Kingdom Integration Bus

K21 is the composition boundary between Kingdom modules and external World/Agent systems.

It standardizes event envelopes (`eventId`, `kind`, `domain`, `source`, `subject`, `tick`, `severity`, `summary`, `correlationId`), provides an idempotent bounded queue, exposes a server-only Publish/Snapshot API, and fires a BindableEvent for subscribers.

K21 also reports installed Kingdom module health from their `K*Status` attributes. If K20 Chronicle is installed, events are optionally mirrored to it; K21 does not require K20.

K21 does not execute gameplay commands, mutate resources, change Agent decisions, or own WorldSim state.

Runtime: `Workspace.AstraKingdomState/K21IntegrationBus`.
API: `ServerScriptService/AstraKingdom/K21IntegrationBusApi`.
Event: `ServerScriptService/AstraKingdom/K21IntegrationEvent`.
