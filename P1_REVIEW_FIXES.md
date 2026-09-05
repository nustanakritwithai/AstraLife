# P1 Review Fixes

Status: P1 remains blocked until the latest full CI passes. Current fix head: `a96b337da1a6571cbeb82f6def05081fd982d475`.

Resolved review findings:

1. Provenance is preserved in real resolver message packets (`originEvidenceId`, `claimFingerprint`).
2. `STALE` and `REFUTED` beliefs are excluded from `activeFor()` and therefore from legacy `mind.facts` / Planner symbolic facts.
3. A newer direct observation marks older same-key beliefs stale, so latest observed state wins even if its confidence/amount band is lower.
4. Rumor loopback with the same origin cannot downgrade a directly observed `CONFIRMED` belief or erase its observed provenance.
5. `newFactKeys` is restored for newly discovered facts to preserve V0.5 reporting behavior.
6. `CONFIRMED` and `UNVERIFIED` beliefs expire to `STALE`; belief/evidence stores are bounded (160/220).
7. Legacy P0.1 message ingestion is suppressed only while the P1 ingestion wrapper runs, preventing the same delivered message from creating a fallback-origin belief before the provenance-aware `receiveBelief()` path.

Acceptance exercises the real path:

`Resolver SHARE -> receiver inbox -> ObservationSystem.capture -> MemorySystem.ingest -> mind.facts -> DecisionRequestFactory`

The latest failed authoritative run was `33950413596`. It confirmed that fixture isolation and confirmed-belief expiry were fixed, while OBS-02/provenance/BEL-01 still failed because legacy message ingest created a duplicate fallback-origin belief. The P1 message-ingest dedupe hotfix addresses that specific root cause without changing P2 or unrelated runtime logic.

Current re-test: GitHub Actions run `33950841338` on head `a96b337da1a6571cbeb82f6def05081fd982d475`.

Do not merge PR #4 or start P2 until P0 + P0.1 + P1 all pass on the same latest head.
