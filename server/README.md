# AstraLife P6 — Typhoon secure provider bridge

This bridge connects AstraLife to the free OpenTyphoon API without putting the API key in GitHub Pages, HTML, browser storage, snapshots, or exports.

Flow:

`AstraLife browser -> /decide secure bridge -> https://api.opentyphoon.ai/v1/chat/completions`

Default model: `typhoon-v2.5-30b-a3b-instruct`.

## Required secret

Set the API key only in the server environment:

```bash
export OPENTYPHOON_API_KEY='YOUR_KEY_HERE'
node server/typhoon-bridge.mjs
```

Never commit the key to this repository. Because AstraLife is hosted on public GitHub Pages, any key embedded in browser JavaScript would be readable by visitors.

## Useful environment variables

```bash
export PORT=8787
export ASTRALIFE_ALLOWED_ORIGINS='https://nustanakritwithai.github.io'
export OPENTYPHOON_MODEL='typhoon-v2.5-30b-a3b-instruct'
export TYPHOON_MAX_CONCURRENT=4
export TYPHOON_MAX_CALLS_PER_MINUTE=160
export TYPHOON_MAX_TOKENS_PER_MINUTE=120000
export TYPHOON_TIMEOUT_MS=9000
export TYPHOON_RETRY_LIMIT=2
node server/typhoon-bridge.mjs
```

Health check:

```bash
curl http://localhost:8787/health
```

AstraLife should be configured with the public HTTPS URL of this bridge ending in `/decide`, then select `Typhoon 2.5 · secure bridge` in the Provider selector.

## P6 isolation and safety behavior

- Every request carries `simulationId`, `runEpoch`, `agentId`, `sessionId`, `requestId`, `observationId`, and `deadlineTick`.
- Sessions are isolated by simulation epoch + session ID and cannot be reused by another Agent.
- The browser rejects wrong-Agent, wrong-session, wrong-epoch, stale, or duplicate responses before they reach Resolver.
- The bridge caps concurrent calls, calls/minute, tokens/minute, queue depth, output tokens, timeout, and retries.
- HTTP 429 and transient 5xx errors use bounded jittered retry.
- Provider errors fall back to the deterministic local planner.
- Typhoon only proposes an action. AstraLife Validator still accepts/rejects it, and Resolver remains the only gameplay world-state mutation authority.
- The model is instructed to return a compact structured decision and not chain-of-thought.

## Tests

Mocked P6 contract/isolation regression:

```bash
node tests/p6-provider-bridge-acceptance.mjs
```

Optional real Typhoon smoke (not run in public CI because it requires a secret):

```bash
OPENTYPHOON_API_KEY='...' node tests/p6-typhoon-real-smoke.mjs
```
