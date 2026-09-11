local Chronicle = {}

local SEVERITY = { info = 1, notice = 2, warning = 3, crisis = 4 }

function Chronicle.Normalize(input, tick)
    local severity = tostring(input.severity or "info")
    if not SEVERITY[severity] then severity = "info" end
    return {
        eventId = tostring(input.eventId or ""),
        tick = tonumber(input.tick) or tick or 0,
        category = tostring(input.category or "general"),
        subject = tostring(input.subject or "kingdom"),
        severity = severity,
        title = tostring(input.title or "Kingdom event"),
        summary = tostring(input.summary or ""),
        source = tostring(input.source or "external"),
    }
end

function Chronicle.Aggregate(events)
    local counts = { info = 0, notice = 0, warning = 0, crisis = 0 }
    local last = events[#events]
    for _, event in ipairs(events) do
        counts[event.severity] = (counts[event.severity] or 0) + 1
    end
    return {
        EventCount = #events,
        InfoCount = counts.info,
        NoticeCount = counts.notice,
        WarningCount = counts.warning,
        CrisisCount = counts.crisis,
        LastEventId = last and last.eventId or "",
        LastEventTitle = last and last.title or "",
        LastEventCategory = last and last.category or "",
        LastEventSeverity = last and last.severity or "",
        LastEventTick = last and last.tick or 0,
    }
end

return Chronicle
