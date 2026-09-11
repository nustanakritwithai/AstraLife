local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local Astra = ReplicatedStorage:WaitForChild("Astra")
local eventRemote = Astra:WaitForChild("AstraEventFeed")
local snapshotRemote = Astra:WaitForChild("AstraEventFeedSnapshot")

local gui = Instance.new("ScreenGui")
gui.Name = "AstraEventFeedGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.Parent = player:WaitForChild("PlayerGui")

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(1, 0)
panel.Position = UDim2.new(1, -16, 0, 16)
panel.Size = UDim2.new(0.34, 0, 0, 300)
panel.BackgroundColor3 = Color3.fromRGB(16, 19, 27)
panel.BackgroundTransparency = 0.12
panel.BorderSizePixel = 0
panel.Parent = gui

local sizeConstraint = Instance.new("UISizeConstraint")
sizeConstraint.MinSize = Vector2.new(280, 220)
sizeConstraint.MaxSize = Vector2.new(430, 360)
sizeConstraint.Parent = panel

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 12)
corner.Parent = panel

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -20, 0, 36)
title.Position = UDim2.fromOffset(10, 6)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.TextSize = 16
title.TextColor3 = Color3.fromRGB(244, 247, 255)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "COLONY ACTIVITY"
title.Parent = panel

local subtitle = Instance.new("TextLabel")
subtitle.Size = UDim2.new(1, -20, 0, 22)
subtitle.Position = UDim2.fromOffset(10, 34)
subtitle.BackgroundTransparency = 1
subtitle.Font = Enum.Font.Gotham
subtitle.TextSize = 11
subtitle.TextColor3 = Color3.fromRGB(166, 177, 198)
subtitle.TextXAlignment = Enum.TextXAlignment.Left
subtitle.Text = "เหตุการณ์สำคัญของโลกและ Agent แบบเรียลไทม์"
subtitle.Parent = panel

local list = Instance.new("ScrollingFrame")
list.Name = "EventList"
list.Position = UDim2.fromOffset(8, 62)
list.Size = UDim2.new(1, -16, 1, -70)
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.ScrollBarThickness = 4
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.CanvasSize = UDim2.new()
list.Parent = panel

local layout = Instance.new("UIListLayout")
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 6)
layout.Parent = list

local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0, 2)
padding.PaddingBottom = UDim.new(0, 4)
padding.PaddingLeft = UDim.new(0, 2)
padding.PaddingRight = UDim.new(0, 2)
padding.Parent = list

local visibleRows = {}
local nextOrder = 0
local MAX_VISIBLE = 12

local severityPrefix = {
    info = "•",
    success = "✓",
    warning = "!",
    critical = "‼",
}

local function removeOldRows()
    while #visibleRows > MAX_VISIBLE do
        local row = table.remove(visibleRows, 1)
        if row and row.Parent then
            row:Destroy()
        end
    end
end

local function addEvent(event)
    if type(event) ~= "table" then
        return
    end

    nextOrder += 1
    local row = Instance.new("TextLabel")
    row.Name = "EventRow"
    row.LayoutOrder = nextOrder
    row.Size = UDim2.new(1, -4, 0, 0)
    row.AutomaticSize = Enum.AutomaticSize.Y
    row.BackgroundColor3 = Color3.fromRGB(28, 32, 43)
    row.BackgroundTransparency = 0.18
    row.BorderSizePixel = 0
    row.Font = Enum.Font.Gotham
    row.TextSize = 12
    row.TextWrapped = true
    row.TextXAlignment = Enum.TextXAlignment.Left
    row.TextYAlignment = Enum.TextYAlignment.Top
    row.TextColor3 = Color3.fromRGB(233, 238, 247)

    local tick = tonumber(event.tick) or 0
    local prefix = severityPrefix[tostring(event.severity)] or "•"
    local source = tostring(event.source or "world")
    row.Text = string.format("  %s  [T%d] %s · %s", prefix, tick, source, tostring(event.text or ""))
    row.Parent = list

    local rowCorner = Instance.new("UICorner")
    rowCorner.CornerRadius = UDim.new(0, 8)
    rowCorner.Parent = row

    local rowPadding = Instance.new("UIPadding")
    rowPadding.PaddingTop = UDim.new(0, 7)
    rowPadding.PaddingBottom = UDim.new(0, 7)
    rowPadding.PaddingLeft = UDim.new(0, 6)
    rowPadding.PaddingRight = UDim.new(0, 6)
    rowPadding.Parent = row

    table.insert(visibleRows, row)
    removeOldRows()

    task.defer(function()
        list.CanvasPosition = Vector2.new(0, math.max(0, list.AbsoluteCanvasSize.Y - list.AbsoluteSize.Y))
    end)
end

local ok, snapshot = pcall(function()
    return snapshotRemote:InvokeServer()
end)
if ok and type(snapshot) == "table" then
    for _, event in ipairs(snapshot) do
        addEvent(event)
    end
end

eventRemote.OnClientEvent:Connect(addEvent)
