--!nonstrict

local BlockService = {}
BlockService.__index = BlockService

function BlockService.new(api, config)
	local self = setmetatable({ api = api, config = config, hit = nil }, BlockService)
	api.RegisterAction("Block", function(c, on)
		if on == true then
			self:raise(c)
		elseif on == false then
			self:lower(c)
		end
	end)
	return self
end

function BlockService:raise(c): boolean
	if not c:canAct() or c.state ~= "Idle" then
		return false
	end
	if c.shield < c.shieldMax * self.config.block.minRaiseFraction then
		return false
	end
	c:setState("Blocking")
	return true
end

function BlockService:lower(c)
	if c.state == "Blocking" then
		c:setState("Idle")
	end
end

function BlockService:absorb(c, damage: number): boolean
	c.lastShieldHitAt = self.api.now()
	local remaining = c.shield - damage
	if remaining > 1e-6 then
		c:setShield(remaining)
		return false
	end
	self:breakGuard(c, "depleted")
	return true
end

function BlockService:breakGuard(c, reason: string)
	c.lastShieldHitAt = self.api.now()
	c:setShield(0)
	self.api.Broadcast(c.root.Position, "fx", "guardBreak", c.model, reason)
	self.hit:stun(c, c:resolve(self.config.block.guardBreakStun), "guardBreak")
end

return BlockService
