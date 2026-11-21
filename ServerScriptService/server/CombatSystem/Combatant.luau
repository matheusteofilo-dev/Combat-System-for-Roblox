--!nonstrict

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CombatShared = require(ReplicatedStorage:WaitForChild("CombatShared"))

local HISTORY_SIZE = 30
local HISTORY_INTERVAL = 0.1

local Combatant = {}
Combatant.__index = Combatant

local function now(): number
	return Workspace:GetServerTimeNow()
end
Combatant.now = now

function Combatant.new(model: Model, humanoid: Humanoid, root: BasePart, options)
	local self = setmetatable({
		model = model,
		humanoid = humanoid,
		root = root,
		player = options.player,
		isNPC = options.player == nil,
		config = options.config,
		statsProvider = options.statsProvider,
		unlockProvider = options.unlockProvider,
		weapon = options.weapon,
		state = "Idle",
		stateUntil = nil,
		cooldowns = {},
		shield = 0,
		shieldMax = 0,
		lastShieldHitAt = -math.huge,
		airJumps = 0,
		combo = 0,
		lastM1At = -math.huge,
		history = {},
		lastHistoryAt = -math.huge,
		destroyed = false,
		changed = CombatShared.newSignal(),
		connections = {},
		lastPublished = {},
	}, Combatant)
	self:refreshDerived(true)
	self:_publish("CombatState", self.state)
	self:_publish("Weapon", self.weapon)
	CollectionService:AddTag(model, CombatShared.ACTOR_TAG)
	return self
end

function Combatant:getStats()
	return self.statsProvider()
end

function Combatant:hasUnlock(key: string): boolean
	return self.unlockProvider ~= nil and self.unlockProvider(key) == true
end

function Combatant:resolve(value)
	return CombatShared.resolve(value, self:getStats())
end

function Combatant:_publish(name: string, value)
	if self.lastPublished[name] == value then
		return
	end
	self.lastPublished[name] = value
	self.model:SetAttribute(name, value)
end

function Combatant:isAlive(): boolean
	return not self.destroyed and self.model.Parent ~= nil and self.humanoid.Health > 0
end

function Combatant:canAct(): boolean
	return self:isAlive() and self.state ~= "Stunned" and self.state ~= "Ragdoll"
end

function Combatant:isBusy(): boolean
	return self.state ~= "Idle"
end

function Combatant:setState(state: string, duration: number?)
	local old = self.state
	self.state = state
	self.stateUntil = if duration then now() + duration else nil
	self:_publish("CombatState", state)
	if old ~= state then
		self.changed:Fire("state", state, old)
	end
end

function Combatant:clearState(state: string)
	if self.state == state then
		self:setState("Idle")
	end
end

function Combatant:cooldownRemaining(id: string): number
	local untilTime = self.cooldowns[id]
	if not untilTime then
		return 0
	end
	return math.max(0, untilTime - now())
end

function Combatant:isReady(id: string): boolean
	return self:cooldownRemaining(id) <= 0
end

function Combatant:startCooldown(id: string, duration: number)
	if duration <= 0 then
		return
	end
	local untilTime = now() + duration
	self.cooldowns[id] = untilTime
	self.changed:Fire("cooldown", id, untilTime, duration)
end

function Combatant:setWeapon(name: string)
	if self.weapon == name then
		return
	end
	self.weapon = name
	self.combo = 0
	self:_publish("Weapon", name)
	self.changed:Fire("weapon", name)
end

function Combatant:refreshDerived(fill: boolean?)
	local cfg = self.config
	local maxShield = self:resolve(cfg.block.max)
	local ratio = if self.shieldMax > 0 then self.shield / self.shieldMax else 1
	self.shieldMax = maxShield
	self.shield = if fill then maxShield else math.clamp(maxShield * ratio, 0, maxShield)
	self:_publish("ShieldMax", math.floor(self.shieldMax + 0.5))
	self:_publish("Shield", math.floor(self.shield + 0.5))

	local maxHealth = self:resolve(cfg.health.max)
	local hum = self.humanoid
	if hum.MaxHealth ~= maxHealth then
		local healthRatio = if hum.MaxHealth > 0 then hum.Health / hum.MaxHealth else 1
		hum.MaxHealth = maxHealth
		if fill then
			hum.Health = maxHealth
		elseif hum.Health > 0 then
			hum.Health = math.clamp(maxHealth * healthRatio, 0.01, maxHealth)
		end
	end
end

function Combatant:setShield(value: number)
	self.shield = math.clamp(value, 0, self.shieldMax)
	self:_publish("Shield", math.floor(self.shield + 0.5))
end

function Combatant:recordPosition(t: number)
	if t - self.lastHistoryAt < HISTORY_INTERVAL then
		return
	end
	self.lastHistoryAt = t
	table.insert(self.history, { time = t, position = self.root.Position, cframe = self.root.CFrame })
	if #self.history > HISTORY_SIZE then
		table.remove(self.history, 1)
	end
end

function Combatant:positionAt(t: number): CFrame
	local history = self.history
	for i = #history, 1, -1 do
		if history[i].time <= t then
			return history[i].cframe
		end
	end
	return self.root.CFrame
end

function Combatant:update(t: number, dt: number)
	if not self:isAlive() then
		return
	end
	self:recordPosition(t)
	if self.stateUntil and t >= self.stateUntil then
		self.stateUntil = nil
		self:setState("Idle")
	end
	if self.state ~= "Blocking" and self.state ~= "Stunned" and self.shield < self.shieldMax and t - self.lastShieldHitAt >= self.config.block.regenDelay then
		self:setShield(self.shield + self:resolve(self.config.block.regenRate) * dt)
	end
end

function Combatant:destroy()
	if self.destroyed then
		return
	end
	self.destroyed = true
	for _, c in ipairs(self.connections) do
		c:Disconnect()
	end
	table.clear(self.connections)
	if self.model.Parent then
		self.model:SetAttribute("CombatState", nil)
		CollectionService:RemoveTag(self.model, CombatShared.ACTOR_TAG)
	end
end

return Combatant
