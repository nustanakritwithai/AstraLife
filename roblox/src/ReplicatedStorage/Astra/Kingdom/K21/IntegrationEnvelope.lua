local IntegrationEnvelope = {}

local VALID_DOMAINS = {
    economy = true,
    social = true,
    politics = true,
    logistics = true,
    security = true,
    world = true,
    agent = true,
    system = true,
}

local function sanitize(value, maxLength)
    local text = tostring(value or "")
    if #text > maxLength then
        return string.sub(text, 1, maxLength)
    end
    return text
end

function IntegrationEnvelope.Build(input, tick)
    local domain = sanitize(input.domain, 32)
    if not VALID_DOMAINS[domain] then domain = "system" end
    return {
        contractVersion = "K21-1",
        eventId = sanitize(input.eventId, 96),
        kind = sanitize(input.kind, 64),
        domain = domain,
        source = sanitize(input.source, 64),
        subject = sanitize(input.subject, 96),
        tick = tonumber(input.tick) or tick or 0,
        severity = sanitize(input.severity or "info", 16),
        summary = sanitize(input.summary, 256),
        correlationId = sanitize(input.correlationId, 96),
    }
end

function IntegrationEnvelope.Validate(envelope)
    if envelope.eventId == "" then return false, "event_id_required" end
    if envelope.kind == "" then return false, "kind_required" end
    if envelope.source == "" then return false, "source_required" end
    return true
end

return IntegrationEnvelope
