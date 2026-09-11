local Contract = require(script.Parent.Contract)

local StateWriter = {}

local function ensureFolder(parent, name)
    local existing = parent:FindFirstChild(name)
    if existing and existing:IsA("Folder") then return existing end
    local value = Instance.new("Folder")
    value.Name = name
    value.Parent = parent
    return value
end

function StateWriter.Root()
    local root = ensureFolder(workspace, Contract.StateRootName)
    Contract.ApplyOwnershipAttributes(root)
    return root
end

function StateWriter.Scope(name)
    assert(type(name) == "string" and name ~= "", "SurvivalCrafting scope required")
    return ensureFolder(StateWriter.Root(), name)
end

function StateWriter.Set(scope, key, value)
    assert(scope and scope:IsDescendantOf(StateWriter.Root()), "SurvivalCrafting write escaped state root")
    scope:SetAttribute(key, value)
end

function StateWriter.SetMany(scope, values)
    for key, value in pairs(values) do
        StateWriter.Set(scope, key, value)
    end
end

return StateWriter
