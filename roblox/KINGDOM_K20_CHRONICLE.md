# K20 Kingdom Chronicle

K20 is a bounded, idempotent event history for Kingdom-level events.

It accepts explicit events through a server-only API and also observes Kingdom module `*State` / `*Status` attributes to record meaningful transitions without directly depending on any K1-K19 module.

History is capped at 256 events. K20 is read-only with respect to gameplay, agents, resources and WorldSim.

Runtime: `Workspace.AstraKingdomState/K20Chronicle`.
API: `ServerScriptService/AstraKingdom/K20ChronicleApi`.
