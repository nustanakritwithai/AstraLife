# P1 Review Fixes

Status: fixes applied, full CI pending on head `57d4499cefce351031620f437fc1682247c09df0`.

Resolved review findings:

1. Provenance is now preserved in real resolver message packets (`originEvidenceId`, `claimFingerprint`).
2. `STALE` and `REFUTED` beliefs are excluded from `activeFor()` and therefore from legacy `mind.facts` / Planner symbolic facts.
3. A newer direct observation marks older same-key beliefs stale, so latest observed state wins even if its confidence/amount band is lower.
4. Rumor loopback with the same origin cannot downgrade a directly observed `CONFIRMED` belief or erase its observed provenance.
5. `newFactKeys` is restored for newly discovered facts to preserve V0.5 reporting behavior.
6. `CONFIRMED` and `UNVERIFIED` beliefs expire to `STALE`; belief/evidence stores are bounded (160/220).

Acceptance was rewritten to exercise the real path:

`Resolver SHARE -> receiver inbox -> ObservationSystem.capture -> MemorySystem.ingest -> mind.facts -> DecisionRequestFactory`

New gates include real OBS-02 delivery isolation, provenance preservation, A->B->C->A loopback integrity, high->low direct observation replacement, stale exclusion from Planner input, BEL-02 trust stability, `newFactKeys`, expiry, bounded stores, persistent export, and P0 integrity.

Do not start P2 until the latest P0 + P0.1 + P1 CI run passes.
