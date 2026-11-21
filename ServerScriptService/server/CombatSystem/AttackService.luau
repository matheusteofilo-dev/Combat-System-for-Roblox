--!nonstrict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CombatShared = require(ReplicatedStorage:WaitForChild("CombatShared"))

local flat = CombatShared.flat

local MAX_PITCH = 1.45

local AttackService = {}
AttackService.__index = AttackService

function AttackService.cooldownId(weaponName: string, abilityId: string): string
	return weaponName .. "." .. abilityId
end

function AttackService.new(api, config, hit)
	local self = setmetatable({
		api = api,
		config = config,
		hit = hit,
		projectiles = {},
		nextProjectileId = 0,
	}, AttackService)
	api.RegisterAction("M1", function(c)
		c.aimDirection = nil
		self:m1(c)
	end)
	api.RegisterAction("Ability", function(c, id, yaw, pitch)
		if type(id) ~= "string" then
			return
		end
		local ability = self:findAbility(c.weapon, id)
		if ability and ability.kind == "projectile" then
			self:_readAim(c, yaw, pitch)
		else
			c.aimDirection = nil
		end
		self:ability(c, id)
	end)
	return self
end

function AttackService:_readAim(c, yaw, pitch)
	if CombatShared.isFinite(yaw) and CombatShared.isFinite(pitch) then
		c.aimDirection = CombatShared.aimDirection(yaw, math.clamp(pitch, -MAX_PITCH, MAX_PITCH))
	else
		c.aimDirection = nil
	end
end

function AttackService:_aim(c): Vector3
	local aim = c.aimDirection
	if typeof(aim) == "Vector3" and aim.Magnitude > 1e-3 then
		return aim.Unit
	end
	local look = flat(c.root.CFrame.LookVector)
	return if look.Magnitude > 1e-3 then look.Unit else Vector3.new(0, 0, -1)
end

function AttackService:_frame(c, aim: Vector3): CFrame
	local direction = flat(aim)
	if direction.Magnitude < 0.2 then
		return c.root.CFrame
	end
	local position = c.root.Position
	return CFrame.lookAt(position, position + direction.Unit)
end

function AttackService:m1(c): boolean
	if not c:canAct() or c.state ~= "Idle" or not c:isReady("M1") then
		return false
	end
	local weapon = self.api.GetWeapon(c.weapon)
	if not weapon then
		return false
	end
	local m1 = weapon.m1
	local now = self.api.now()
	if now - c.lastM1At > m1.comboResetTime or c.comboWeapon ~= c.weapon then
		c.combo = 0
	end
	local index = c.combo % #m1.hits + 1
	c.combo = index
	c.comboWeapon = c.weapon
	c.lastM1At = now
	local attack = m1.hits[index]
	local total = attack.windup + attack.recovery
	if index == #m1.hits then
		c.combo = 0
		c:startCooldown("M1", total + m1.comboEndCooldown)
	else
		c:startCooldown("M1", total)
	end
	self:perform(c, attack, c.weapon, "m1", index)
	return true
end

function AttackService:findAbility(weaponName: string, id: string)
	local weapon = self.api.GetWeapon(weaponName)
	if not weapon then
		return nil
	end
	for _, ability in ipairs(weapon.abilities) do
		if ability.id == id then
			return ability
		end
	end
	return nil
end

function AttackService:ability(c, id: string): boolean
	if not c:canAct() or c.state ~= "Idle" then
		return false
	end
	local ability = self:findAbility(c.weapon, id)
	if not ability then
		return false
	end
	local key = AttackService.cooldownId(c.weapon, id)
	if not c:isReady(key) then
		return false
	end
	c:startCooldown(key, c:resolve(ability.cooldown))
	self:perform(c, ability, c.weapon, "ability", id)
	return true
end

function AttackService:perform(c, attack, weaponName: string, kind: string, key)
	local total = attack.windup + attack.recovery
	c:setState("Attacking", total)
	c.attackToken = (c.attackToken or 0) + 1
	local token = c.attackToken
	local aim = self:_aim(c)
	self.api.Broadcast(c.root.Position, "anim", c.model, weaponName, kind, key)
	task.delay(attack.windup, function()
		if c.attackToken ~= token or c.state ~= "Attacking" or not c:isAlive() then
			return
		end
		self:_release(c, attack, weaponName, aim)
	end)
end

function AttackService:_release(c, attack, weaponName: string, aim: Vector3)
	local weapon = self.api.GetWeapon(weaponName)
	local effect = weapon and weapon.effect
	local kind = attack.kind or "melee"
	if kind == "melee" then
		local frame = self:_frame(c, aim)
		local center = (frame * attack.hitbox.offset).Position
		if effect then
			self.api.Broadcast(center, "fx", "blast", c.model, center, effect)
		end
		for _, target in ipairs(self.hit:queryBox(c, attack.hitbox, frame)) do
			self.hit:apply(c, target, attack, c.root.Position)
		end
	elseif kind == "area" then
		local center = c.root.Position
		self.api.Broadcast(center, "fx", "burst", c.model, attack.area.radius, effect)
		for _, target in ipairs(self.hit:queryRadius(c, center, attack.area.radius)) do
			self.hit:apply(c, target, attack, center)
		end
	elseif kind == "projectile" then
		self:_spawnProjectile(c, attack, weaponName, aim)
	end
end

function AttackService:_spawnProjectile(c, attack, weaponName: string, direction: Vector3)
	local p = attack.projectile
	local origin = c.root.Position + direction * 2 + Vector3.new(0, 0.5, 0)
	self.nextProjectileId += 1
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { c.model }
	local projectile = {
		id = self.nextProjectileId,
		owner = c,
		attack = attack,
		position = origin,
		direction = direction,
		traveled = 0,
		params = params,
	}
	table.insert(self.projectiles, projectile)
	self.api.Broadcast(origin, "projectile", projectile.id, origin, direction, p.speed, p.range, weaponName)
end

function AttackService:_explode(projectile, position: Vector3, hitPart: BasePart?)
	local owner = projectile.owner
	local attack = projectile.attack
	local radius = attack.projectile.explosionRadius
	local targets = {}
	if radius > 0 then
		targets = self.hit:queryRadius(owner, position, radius)
	elseif hitPart then
		local model = hitPart:FindFirstAncestorOfClass("Model")
		local target = model and self.api.GetCombatant(model)
		if target and self.hit:canHit(owner, target) then
			targets = { target }
		end
	end
	for _, target in ipairs(targets) do
		self.hit:apply(owner, target, attack, position)
	end
	self.api.Broadcast(position, "projectileEnd", projectile.id, position, true)
end

function AttackService:update(dt: number)
	for i = #self.projectiles, 1, -1 do
		local pr = self.projectiles[i]
		local spec = pr.attack.projectile
		local step = math.min(spec.speed * dt, spec.range - pr.traveled)
		local result = if step > 0 then Workspace:Spherecast(pr.position, spec.radius, pr.direction * step, pr.params) else nil
		if result then
			table.remove(self.projectiles, i)
			self:_explode(pr, result.Position + result.Normal * 0.5, result.Instance)
		else
			pr.position += pr.direction * step
			pr.traveled += step
			if pr.traveled >= spec.range - 1e-3 then
				table.remove(self.projectiles, i)
				self.api.Broadcast(pr.position, "projectileEnd", pr.id, pr.position, false)
			end
		end
	end
end

function AttackService:clear()
	table.clear(self.projectiles)
end

return AttackService
