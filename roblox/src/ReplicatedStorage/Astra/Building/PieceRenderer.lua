local BuildPieceCatalog = require(script.Parent.BuildPieceCatalog)
local MaterialGradeCatalog = require(script.Parent.MaterialGradeCatalog)

local PieceRenderer = {}

local function ensureLifecycle(piece)
    local grade = piece.materialGrade
    if not MaterialGradeCatalog.IsValid(grade) then
        grade = MaterialGradeCatalog.DefaultGrade()
        piece.materialGrade = grade
    end
    local expectedMax = MaterialGradeCatalog.MaxHealth(piece.pieceType, grade) or 1
    if piece.maxHealth == nil or piece.maxHealth <= 0 then piece.maxHealth = expectedMax end
    if piece.health == nil then piece.health = piece.maxHealth end
    piece.health = math.clamp(piece.health, 0, piece.maxHealth)
    piece.destroyed = piece.destroyed == true or piece.health <= 0
end

local function applyLifecycleAttributes(instance, piece)
    instance:SetAttribute("MaterialGrade", piece.materialGrade)
    instance:SetAttribute("Health", piece.health)
    instance:SetAttribute("MaxHealth", piece.maxHealth)
    instance:SetAttribute("HealthPercent", piece.maxHealth > 0 and piece.health / piece.maxHealth or 0)
    instance:SetAttribute("Destroyed", piece.destroyed == true)
end

local function applyVisual(part, piece)
    local visual = MaterialGradeCatalog.Visual(piece.materialGrade)
    part.Material = visual.material
    part.Color = visual.color
    part.Transparency = visual.transparency
end

local function configure(part, piece, name)
    ensureLifecycle(piece)
    part.Name = name or piece.pieceType
    part.Anchored = true
    part.CanCollide = true
    part.CanQuery = true
    part:SetAttribute("IsModularBuildPiece", true)
    part:SetAttribute("PieceId", piece.id)
    part:SetAttribute("PieceType", piece.pieceType)
    part:SetAttribute("Stability", piece.stability)
    applyLifecycleAttributes(part, piece)
    applyVisual(part, piece)
end

local function basicPart(piece, size, offset)
    local part = Instance.new("Part")
    part.Size = size
    part.CFrame = piece.cframe * (offset or CFrame.new())
    configure(part, piece)
    return part
end

local function frameModel(piece, isDoor)
    ensureLifecycle(piece)
    local model = Instance.new("Model")
    model.Name = piece.pieceType .. "_" .. piece.id
    model:SetAttribute("IsModularBuildPiece", true)
    model:SetAttribute("PieceId", piece.id)
    model:SetAttribute("PieceType", piece.pieceType)
    model:SetAttribute("Stability", piece.stability)
    applyLifecycleAttributes(model, piece)

    local pieces = {}
    local function beam(name, size, offset)
        local part = basicPart(piece, size, offset)
        part.Name = name
        part.Parent = model
        table.insert(pieces, part)
        return part
    end

    if isDoor then
        beam("LeftPost", Vector3.new(1, 8, 0.6), CFrame.new(-5.5, 4, 0))
        beam("RightPost", Vector3.new(1, 8, 0.6), CFrame.new(5.5, 4, 0))
        beam("Header", Vector3.new(10, 1, 0.6), CFrame.new(0, 7.5, 0))
    else
        beam("LeftPost", Vector3.new(1, 8, 0.6), CFrame.new(-5.5, 4, 0))
        beam("RightPost", Vector3.new(1, 8, 0.6), CFrame.new(5.5, 4, 0))
        beam("Header", Vector3.new(10, 1, 0.6), CFrame.new(0, 7.5, 0))
        beam("Sill", Vector3.new(10, 1, 0.6), CFrame.new(0, 2.2, 0))
    end

    model.PrimaryPart = pieces[1]
    return model
end

local function stairsModel(piece)
    ensureLifecycle(piece)
    local model = Instance.new("Model")
    model.Name = piece.pieceType .. "_" .. piece.id
    model:SetAttribute("IsModularBuildPiece", true)
    model:SetAttribute("PieceId", piece.id)
    model:SetAttribute("PieceType", piece.pieceType)
    model:SetAttribute("Stability", piece.stability)
    applyLifecycleAttributes(model, piece)

    local steps = 8
    local stepHeight = 8 / steps
    local stepDepth = 10 / steps
    for index = 1, steps do
        local height = stepHeight * index
        local depth = stepDepth
        local z = 5 - (index - 0.5) * stepDepth
        local part = basicPart(
            piece,
            Vector3.new(6, height, depth),
            CFrame.new(0, height / 2, z)
        )
        part.Name = "Step" .. tostring(index)
        part.Parent = model
        if index == 1 then model.PrimaryPart = part end
    end
    return model
end

function PieceRenderer.Create(piece)
    ensureLifecycle(piece)
    local definition = BuildPieceCatalog.Get(piece.pieceType)
    assert(definition, "unknown piece type")

    if piece.pieceType == "DoorFrame" then
        return frameModel(piece, true)
    elseif piece.pieceType == "WindowFrame" then
        return frameModel(piece, false)
    elseif piece.pieceType == "Stairs" then
        return stairsModel(piece)
    end

    local offset = CFrame.new()
    if piece.pieceType == "Wall" then
        offset = CFrame.new(0, 4, 0)
    elseif piece.pieceType == "HalfWall" then
        offset = CFrame.new(0, 2, 0)
    end

    local part
    if piece.pieceType == "FoundationTriangle" or piece.pieceType == "FloorTriangle" then
        part = Instance.new("WedgePart")
        part.Size = definition.size
        part.CFrame = piece.cframe * offset
        configure(part, piece)
    else
        part = basicPart(piece, definition.size, offset)
    end
    return part
end

function PieceRenderer.UpdateStability(instance, stability)
    if not instance then return end
    instance:SetAttribute("Stability", stability)
    for _, descendant in ipairs(instance:GetDescendants()) do
        if descendant:IsA("BasePart") then
            descendant:SetAttribute("Stability", stability)
        end
    end
end

function PieceRenderer.UpdateLifecycle(instance, piece)
    if not instance or not piece then return end
    ensureLifecycle(piece)
    applyLifecycleAttributes(instance, piece)
    if instance:IsA("BasePart") then
        applyVisual(instance, piece)
    end
    for _, descendant in ipairs(instance:GetDescendants()) do
        if descendant:IsA("BasePart") then
            applyLifecycleAttributes(descendant, piece)
            applyVisual(descendant, piece)
        end
    end
end

return PieceRenderer
