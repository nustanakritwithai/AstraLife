local BuildPieceCatalog = require(script.Parent.BuildPieceCatalog)

local PieceRenderer = {}

local function configure(part, piece, name)
    part.Name = name or piece.pieceType
    part.Anchored = true
    part.CanCollide = true
    part.CanQuery = true
    part:SetAttribute("IsModularBuildPiece", true)
    part:SetAttribute("PieceId", piece.id)
    part:SetAttribute("PieceType", piece.pieceType)
    part:SetAttribute("Stability", piece.stability)
end

local function basicPart(piece, size, offset)
    local part = Instance.new("Part")
    part.Size = size
    part.CFrame = piece.cframe * (offset or CFrame.new())
    part.Material = Enum.Material.WoodPlanks
    configure(part, piece)
    return part
end

local function frameModel(piece, isDoor)
    local model = Instance.new("Model")
    model.Name = piece.pieceType .. "_" .. piece.id
    model:SetAttribute("IsModularBuildPiece", true)
    model:SetAttribute("PieceId", piece.id)
    model:SetAttribute("PieceType", piece.pieceType)
    model:SetAttribute("Stability", piece.stability)

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
    local model = Instance.new("Model")
    model.Name = piece.pieceType .. "_" .. piece.id
    model:SetAttribute("IsModularBuildPiece", true)
    model:SetAttribute("PieceId", piece.id)
    model:SetAttribute("PieceType", piece.pieceType)
    model:SetAttribute("Stability", piece.stability)

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
        part.Material = Enum.Material.WoodPlanks
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

return PieceRenderer
