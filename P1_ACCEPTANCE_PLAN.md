# P1 Structured Belief Acceptance

Scope: Structured Belief + Evidence + Provenance only.

Required gates:
- OBS-02: A reports to B; B receives an UNVERIFIED belief; C does not receive it.
- BEL-01: the same origin evidence circulating through agents does not multiply into independent origins.
- BEL-02: a claim that is no longer true under later conditions becomes STALE without automatically penalizing the original reporter as a liar.
- Direct observation can CONFIRM a belief.
- Agent persistent boundary exports structured beliefs and evidence.
- P0 and P0.1 regression suites still pass.

Belief states:
- UNVERIFIED
- CONFIRMED
- STALE
- REFUTED

Compatibility rule: `mind.beliefs` / `mind.evidence` are authoritative for P1 belief lifecycle; the best usable belief is mirrored into legacy `mind.facts` so V0.5 planners/providers remain functional during migration.
