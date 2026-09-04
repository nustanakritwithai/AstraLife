# AstraLife

AstraLife is an experimental multi-agent survival world where independent Astra-style agents observe, plan, communicate, build trust, learn skills, and cooperate to survive.

Current live checkpoint: **ASTRA COLONY V0.5 — Emergent Roles + Skill Learning**.

Live page: https://nustanakritwithai.github.io/AstraLife/

## Core loop

World Truth → Partial Observation → Individual World Model → Decision Provider → Validated Action → Consequence → Learning → Emergent Specialization

## V0.5 rule

No agent receives Scout, Gatherer, Builder, Healer, Carrier, or Coordinator at spawn.

Every agent starts with:

- `role: human`
- `emergentRole: generalist`
- independent Skill Experience
- Competency
- Preference
- Domain Reputation
- Task Success / Failure history

Specialization is derived from lived experience. Exploration can create Scouts, gathering can create Gatherers, construction can create Builders, treatment can create Healers, logistics can create Carriers, and communication can create Coordinators.

## Development rule

Development continues incrementally from the latest checkpoint. Do not rebuild the simulator from scratch or discard earlier capabilities.
