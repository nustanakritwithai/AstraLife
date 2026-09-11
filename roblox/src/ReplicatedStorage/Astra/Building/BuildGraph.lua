local BuildPieceCatalog = require(script.Parent.BuildPieceCatalog)

local BuildGraph = {}
BuildGraph.__index = BuildGraph

local FLIP = CFrame.Angles(0, math.rad(180), 0)
local MODULUS = 4294967296

local function acceptsKind(attachment, kind)
    for _, accepted in ipairs(attachment.accepts or {}) do
        if accepted == kind then return true end
    end
    return false
end

local function findConnector(definition, name)
    for _, connector in ipairs(definition.connectors or {}) do
        if connector.name == name then return connector end
    end
    return nil
end

local function findAttachment(definition, name, kind)
    for _, attachment in ipairs(definition.attachments or {}) do
        if (not name or attachment.name == name) and acceptsKind(attachment, kind) then
            return attachment
        end
    end
    return nil
end

local function cframeText(cframe)
    local values = { cframe:GetComponents() }
    local out = {}
    for index, value in ipairs(values) do out[index] = string.format("%.4f", value) end
    return table.concat(out, ",")
end

local function hashText(text)
    local hash = 5381
    for index = 1, #text do
        hash = (hash * 33 + string.byte(text, index)) % MODULUS
    end
    return hash
end

function BuildGraph.new()
    return setmetatable({
        sequence = 0,
        pieces = {},
    }, BuildGraph)
end

function BuildGraph:_nextId()
    self.sequence += 1
    return string.format("piece:%d", self.sequence)
end

function BuildGraph:Get(pieceId)
    return self.pieces[pieceId]
end

function BuildGraph:Count()
    local count = 0
    for _ in pairs(self.pieces) do count += 1 end
    return count
end

function BuildGraph:GetSocket(pieceId, socketName)
    local piece = self.pieces[pieceId]
    if not piece then return nil end
    return piece.sockets[socketName]
end

function BuildGraph:GetOpenSockets(pieceId, kind)
    local piece = self.pieces[pieceId]
    if not piece then return {} end
    local result = {}
    for name, socket in pairs(piece.sockets) do
        if not socket.occupiedBy and (not kind or socket.kind == kind) then
            table.insert(result, {
                pieceId = pieceId,
                name = name,
                kind = socket.kind,
                worldCFrame = socket.worldCFrame,
            })
        end
    end
    table.sort(result, function(a, b) return a.name < b.name end)
    return result
end

function BuildGraph:_makePiece(pieceType, cframe, metadata)
    local definition = BuildPieceCatalog.Get(pieceType)
    assert(definition, "unknown piece type: " .. tostring(pieceType))

    local piece = {
        id = self:_nextId(),
        pieceType = pieceType,
        category = definition.category,
        cframe = cframe,
        stability = 0,
        isGrounded = false,
        parentId = nil,
        parentSocket = nil,
        attachmentName = nil,
        children = {},
        sockets = {},
        metadata = metadata or {},
    }

    for _, connector in ipairs(definition.connectors or {}) do
        piece.sockets[connector.name] = {
            name = connector.name,
            kind = connector.kind,
            worldCFrame = cframe * connector.localCFrame,
            occupiedBy = nil,
        }
    end

    return piece, definition
end

function BuildGraph:PreviewSnap(pieceType, parentId, parentSocketName, attachmentName)
    local parent = self.pieces[parentId]
    if not parent then return nil, "missing_parent" end

    local socket = parent.sockets[parentSocketName]
    if not socket then return nil, "missing_socket" end
    if socket.occupiedBy then return nil, "socket_occupied" end

    local definition = BuildPieceCatalog.Get(pieceType)
    if not definition then return nil, "unknown_piece" end
    local attachment = findAttachment(definition, attachmentName, socket.kind)
    if not attachment then return nil, "incompatible_socket" end

    local childCFrame = socket.worldCFrame * FLIP * attachment.localCFrame:Inverse()
    local predictedStability = parent.stability * (definition.stabilityTransfer or 0)

    return {
        pieceType = pieceType,
        cframe = childCFrame,
        parentId = parentId,
        parentSocket = parentSocketName,
        attachmentName = attachment.name,
        predictedStability = predictedStability,
        minStability = definition.minStability or 0,
        size = definition.size,
    }, nil
end

function BuildGraph:PlaceRoot(pieceType, cframe, metadata)
    local definition = BuildPieceCatalog.Get(pieceType)
    if not definition then return nil, "unknown_piece" end
    if definition.grounded ~= true then return nil, "root_requires_grounded_piece" end

    local piece = self:_makePiece(pieceType, cframe, metadata)
    piece.isGrounded = true
    piece.stability = 1
    self.pieces[piece.id] = piece
    return piece, nil
end

function BuildGraph:PlaceSnap(pieceType, parentId, parentSocketName, attachmentName, metadata)
    local preview, reason = self:PreviewSnap(pieceType, parentId, parentSocketName, attachmentName)
    if not preview then return nil, reason end
    if preview.predictedStability < preview.minStability then
        return nil, "insufficient_stability"
    end

    local parent = self.pieces[parentId]
    local piece = self:_makePiece(pieceType, preview.cframe, metadata)
    piece.parentId = parentId
    piece.parentSocket = parentSocketName
    piece.attachmentName = preview.attachmentName
    piece.stability = preview.predictedStability

    parent.sockets[parentSocketName].occupiedBy = piece.id
    parent.children[piece.id] = true
    self.pieces[piece.id] = piece
    return piece, nil
end

function BuildGraph:RecomputeStability()
    for _, piece in pairs(self.pieces) do
        piece.stability = piece.isGrounded and 1 or 0
    end

    local ids = {}
    for id in pairs(self.pieces) do table.insert(ids, id) end
    table.sort(ids)

    local changed = true
    local passes = 0
    while changed and passes <= #ids do
        changed = false
        passes += 1
        for _, id in ipairs(ids) do
            local piece = self.pieces[id]
            if piece and not piece.isGrounded and piece.parentId then
                local parent = self.pieces[piece.parentId]
                local definition = BuildPieceCatalog.Get(piece.pieceType)
                local nextValue = parent and parent.stability * (definition.stabilityTransfer or 0) or 0
                if math.abs(nextValue - piece.stability) > 1e-8 then
                    piece.stability = nextValue
                    changed = true
                end
            end
        end
    end

    local unstable = {}
    for _, id in ipairs(ids) do
        local piece = self.pieces[id]
        local definition = piece and BuildPieceCatalog.Get(piece.pieceType)
        if piece and not piece.isGrounded and piece.stability < (definition.minStability or 0) then
            table.insert(unstable, id)
        end
    end
    return unstable
end

function BuildGraph:Remove(pieceId)
    local piece = self.pieces[pieceId]
    if not piece then return nil, "missing_piece" end

    if piece.parentId then
        local parent = self.pieces[piece.parentId]
        if parent then
            parent.children[pieceId] = nil
            local socket = parent.sockets[piece.parentSocket]
            if socket and socket.occupiedBy == pieceId then socket.occupiedBy = nil end
        end
    end

    for childId in pairs(piece.children) do
        local child = self.pieces[childId]
        if child then
            child.parentId = nil
            child.parentSocket = nil
            child.attachmentName = nil
        end
    end

    self.pieces[pieceId] = nil
    local unstable = self:RecomputeStability()
    return piece, unstable
end

function BuildGraph:Fingerprint()
    local ids = {}
    for id in pairs(self.pieces) do table.insert(ids, id) end
    table.sort(ids)

    local pieces = {}
    for _, id in ipairs(ids) do
        local piece = self.pieces[id]
        local sockets = {}
        local names = {}
        for name in pairs(piece.sockets) do table.insert(names, name) end
        table.sort(names)
        for _, name in ipairs(names) do
            local socket = piece.sockets[name]
            table.insert(sockets, table.concat({ name, socket.kind, tostring(socket.occupiedBy or "") }, ":"))
        end
        table.insert(pieces, table.concat({
            id,
            piece.pieceType,
            cframeText(piece.cframe),
            string.format("%.6f", piece.stability),
            piece.isGrounded and "1" or "0",
            tostring(piece.parentId or ""),
            tostring(piece.parentSocket or ""),
            table.concat(sockets, ";"),
        }, "|"))
    end

    return string.format("%08x", hashText(table.concat(pieces, "#")))
end

return BuildGraph
