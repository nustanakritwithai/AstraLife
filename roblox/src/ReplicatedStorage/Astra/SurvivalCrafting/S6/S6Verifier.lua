local S6Verifier = {}

function S6Verifier.Verify(CraftQueue, scope)
    local errors = {}
    local queue = CraftQueue.new(2)
    local job = queue:Enqueue({ recipeId = "test", craftTicks = 2, quantity = 1, inputs = { Log = 1 }, outputs = { Plank = 2 } }, "tx1", 0)
    local duplicate, reason = queue:Enqueue({ recipeId = "test", craftTicks = 2 }, "tx1", 0)
    if not job or duplicate ~= job or reason ~= "duplicate" then table.insert(errors, "idempotency") end
    queue:Step(1, 1)
    local ready, readyReason = queue:Step(2, 1)
    if readyReason ~= "ready_to_commit" or ready.state ~= "completed_pending_commit" then table.insert(errors, "completion") end
    local committed = queue:Commit(ready.id, true)
    if not committed or committed.state ~= "committed" then table.insert(errors, "commit") end
    local recommitted, reCommitReason = queue:Commit(ready.id, true)
    if not recommitted or recommitted.state ~= "committed" or reCommitReason ~= "committed" then table.insert(errors, "commit_idempotency") end
    local status = #errors == 0 and "PASS" or "ERROR"
    scope:SetAttribute("S6Status", status)
    scope:SetAttribute("S6Errors", table.concat(errors, ","))
    return status, errors
end
return S6Verifier
