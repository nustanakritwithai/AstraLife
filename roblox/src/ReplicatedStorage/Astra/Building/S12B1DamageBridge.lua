-- I5 command boundary: S12 DurabilityPolicy remains quote-only.
-- Authoritative structure health mutation is B1 PieceLifecycle via
-- BuildingLifecycleService.ApplyDamage. This bridge never stores health.

local S12B1DamageBridge = {}

-- quote: result of DurabilityPolicy.StructureDecayQuote (or compatible table)
-- opts: { pieceId, damageType?, transactionId? }
function S12B1DamageBridge.ApplyQuotedDamage(lifecycleService, quote, opts)
	opts = opts or {}
	if not lifecycleService or type(lifecycleService.ApplyDamage) ~= "function" then
		return { ok = false, reason = "missing_lifecycle_service" }
	end
	if type(quote) ~= "table" or type(quote.damage) ~= "number" then
		return { ok = false, reason = "invalid_quote" }
	end
	local pieceId = opts.pieceId
	if pieceId == nil or pieceId == "" then
		return { ok = false, reason = "missing_piece_id" }
	end
	if quote.damage <= 0 then
		return {
			ok = true,
			skipped = true,
			reason = "zero_damage_quote",
			transactionId = opts.transactionId,
		}
	end

	local damageType = opts.damageType or "Decay"
	local transactionId = opts.transactionId
		or string.format("s12decay:%s:%s", tostring(pieceId), tostring(quote.damage))

	local result = lifecycleService.ApplyDamage(pieceId, quote.damage, damageType, transactionId)
	if type(result) ~= "table" then
		return { ok = false, reason = "apply_damage_failed" }
	end
	result.source = "S12Quote"
	result.quoteDamage = quote.damage
	return result
end

return S12B1DamageBridge
