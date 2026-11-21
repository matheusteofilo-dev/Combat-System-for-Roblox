--!nonstrict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CombatShared = require(ReplicatedStorage:WaitForChild("CombatShared"))

local flat = CombatShared.flat

local HitService = {}
HitService.__index = HitService

function HitService.new(api, config, movement, block)
	return setmetatable({
		api = api,
		config = config,
		movement = movement,
		block = block,
	}, HitService)
end

function HitService:canHit(attacker, target): boolean
	if attacker == target or not target:isAlive() then
		return false
	end
	local cfg = self.config.hit
	if not attacker.isNPC and not target.isNPC and not cfg.pvp then
		return false
	end
	if attacker.isNPC and target.isNPC and not cfg.npcFriendlyFire then
		return false
	end
	return true
end

function HitService:_overlapParams(attacker)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { attacker.model }
	return params
end

function HitService:hasLineOfSight(from: Vector3, target, ignore): boolean
	if not self.config.hit.lineOfSight then
		return true
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local list = { target.model }
	for _, model in ipairs(ignore) do
		table.insert(list, model)
	end
	for _, c in ipairs(self.api.GetCombatants()) do
		table.insert(list, c.model)
	end
	params.FilterDescendantsInstances = list
	local to = target.root.Position
	return Workspace:Raycast(from, to - from, params) == nil
end

function HitService:_collect(attacker, parts, origin: Vector3, ignore)
	local found, list = {}, {}
	for _, part in ipairs(parts) do
		local model = part:FindFirstAncestorOfClass("Model")
		while model and not self.api.GetCombatant(model) do
			model = model:FindFirstAncestorOfClass("Model")
		end
		local target = model and self.api.GetCombatant(model)
		if target and not found[target] and self:canHit(attacker, target) then
			found[target] = true
			if self:hasLineOfSight(origin, target, ignore) then
				table.insert(list, target)
			end
		end
	end
	table.sort(list, function(a, b)
		return (a.root.Position - origin).Magnitude < (b.root.Position - origin).Magnitude
	end)
	local max = self.config.hit.maxTargets
	while #list > max do
		table.remove(list)
	end
	return list
end

function HitService:queryBox(attacker, hitbox, frame: CFrame?)
	local tol = self.config.hit.reachTolerance
	local cframe = (frame or attacker.root.CFrame) * hitbox.offset
	local size = hitbox.size + Vector3.new(tol, tol * 0.5, tol)
	if self.config.debug.showHitboxes then
		self.api.Broadcast(cframe.Position, "fx", "hitbox", attacker.model, cframe, size)
	else
		self.api.SendDebug("fx", "hitbox", attacker.model, cframe, size)
	end
	local parts = Workspace:GetPartBoundsInBox(cframe, size, self:_overlapParams(attacker))
	return self:_collect(attacker, parts, attacker.root.Position, { attacker.model })
end

function HitService:queryRadius(attacker, center: Vector3, radius: number)
	local r = radius + self.config.hit.reachTolerance * 0.5
	if self.config.debug.showHitboxes then
		self.api.Broadcast(center, "fx", "hitsphere", attacker.model, CFrame.new(center), Vector3.one * r * 2)
	else
		self.api.SendDebug("fx", "hitsphere", attacker.model, CFrame.new(center), Vector3.one * r * 2)
	end
	local parts = Workspace:GetPartBoundsInRadius(center, r, self:_overlapParams(attacker))
	return self:_collect(attacker, parts, center, { attacker.model })
end

function HitService:stun(target, duration: number, reason: string)
	if duration <= 0 or not target:isAlive() or target.state == "Ragdoll" then
		return
	end
	if target.state == "Climbing" then
		self.movement:stopClimb(target, "hit")
	elseif target.state == "Blocking" then
		self.block:_announce(target, false)
	end
	target:setState("Stunned", duration)
	target.attackToken = (target.attackToken or 0) + 1
	self.api.Broadcast(target.root.Position, "fx", "stun", target.model, duration, reason)
end

function HitService:knockback(target, source: Vector3, horizontal: number, vertical: number)
	if horizontal <= 0 and vertical <= 0 then
		return
	end
	local dir = flat(target.root.Position - source)
	dir = if dir.Magnitude > 1e-3 then dir.Unit else flat(-target.root.CFrame.LookVector).Unit
	local velocity = dir * horizontal + Vector3.yAxis * vertical
	local duration = self.config.hit.knockbackTime + vertical / Workspace.Gravity * 2
	if target.isNPC then
		target.root.AssemblyLinearVelocity = velocity
	else
		self.movement:grant(target, horizontal + target.humanoid.WalkSpeed, vertical * vertical / (2 * Workspace.Gravity), duration + 0.5)
		self.api.Send(target.player, "knockback", velocity, self.config.hit.knockbackTime)
	end
end

function HitService:apply(attacker, target, attack, source: Vector3)
	if not self:canHit(attacker, target) then
		return "invalid"
	end
	local now = self.api.now()
	if target.invulnerableUntil and now < target.invulnerableUntil then
		self.api.Broadcast(target.root.Position, "fx", "dodge", target.model)
		return "dodged"
	end

	local damage = math.max(0, attacker:resolve(attack.damage))
	local front = CombatShared.isInFront(target.root.CFrame, source, self.config.block.arc)
	local result = "hit"

	if target.state == "Blocking" and front then
		if attack.breaksBlock then
			self.block:breakGuard(target, "breaker")
			result = "guardBreak"
		else
			local broke = self.block:absorb(target, damage)
			result = if broke then "guardBreak" else "blocked"
			self.api.Damaged:Fire(attacker, target, 0, result)
			if not broke then
				self.api.Broadcast(target.root.Position, "fx", "blocked", target.model)
			end
			return result
		end
	elseif target.state == "Blocking" then
		result = "backstab"
	end
	target.lastShieldHitAt = now

	target.humanoid:TakeDamage(damage)
	self.api.Broadcast(target.root.Position, "fx", "hit", target.model, result)
	if target.humanoid.Health > 0 then
		if result ~= "guardBreak" then
			self:stun(target, target:resolve(self.config.hit.hitStun), "hit")
		end
		local horizontal = if attack.knockback then attacker:resolve(attack.knockback) else 0
		local vertical = if attack.launch then attacker:resolve(attack.launch) else 0
		self:knockback(target, source, horizontal, vertical)
	end
	self.api.Damaged:Fire(attacker, target, damage, result)
	return result
end

return HitService
