# K19 Public Sentiment

K19 models aggregate public support, fear, grievance and loyalty without writing to individual Agent cognition.

A server-only API accepts idempotent public events such as relief, victory, shortage, corruption, disaster or betrayal. Event influence decays over 120 Agent WorldTicks and the event buffer is bounded.

K19 does not modify Agent Memory, Belief, Needs, Role, Goal or health.

Runtime: `Workspace.AstraKingdomState/K19PublicSentiment`.
