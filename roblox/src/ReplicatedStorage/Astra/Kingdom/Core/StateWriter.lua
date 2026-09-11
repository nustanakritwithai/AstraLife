local Contract = require(script.Parent.Contract)

local StateWriter = {}

local function ensureFolder(parent, name)
    local existing = parent:FindFirstChild(name)
    if existing and existing:IsA("Folder") then return existing end
    local folder = Instance.new("Folder")
    folder.Name = name
    folder.Parent = parent
    return folder
end

function StateWriter.Root()
    local root = ensureFolder(workspace, Contract.StateRootName)
    Contract.ApplyOwnershipAttributes(root)
    root:SetAttribute("WriteBoundary", "Workspace/" .. Contract.StateRootName .. " only")
    return root
end

function StateWriter.Scope(name)
    assert(type(name) == "string" and name ~= "", "Kingdom scope name required")
    return ensureFolder(StateWriter.Root(), name)
end

function StateWriter.Set(scope, key, value)
    assert(scope and scope:IsDescendantOf(StateWriter.Root()), "Kingdom write escaped AstraKingdomState")
    scope:SetAttribute(key, value)
end

function StateWriter.SetMany(scope, values)
    for key, value in pairs(values) do StateWriter.Set(scope, key, value) end
end

return StateWriter
