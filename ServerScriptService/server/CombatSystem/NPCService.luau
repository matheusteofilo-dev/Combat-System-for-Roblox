--!nonstrict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CombatShared = require(ReplicatedStorage:WaitForChild("CombatShared"))

local PROFILE_ATTRIBUTE = "CombatProfile"
local DEFAULT_INTERVAL = { 0.2, 0.4 }

local flat = CombatShared.flat

local LOCKED_STATES = {
	Enum.HumanoidStateType.FallingDown,
	Enum.HumanoidStateType.Ragdoll,
	Enum.HumanoidStateType.GettingUp,
	Enum.HumanoidStateType.PlatformStanding,
}
local UPRIGHT_LIMIT = 0.995

local NPCService = {}
NPCService.__index = NPCService

function NPCService.new(system, config, profiles)
	return setmetatable({
		system = system,
		config = config,
		profiles = profiles,
		rng = Random.new(),
		entries = {},
		connections = {},
		warned = {},
		running = false,
	}, NPCService)
end

function NPCService:_track(model: Instance)
	if not self.running or not model:IsA("Model") or self.entries[model] or not model:IsDescendantOf(Workspace) then
		return
	end
	local tag = model:GetAttribute(PROFILE_ATTRIBUTE)
	if type(tag) ~= "string" then
		return
	end
	local profile = self.profiles[tag]
	if not profile then
		if not self.warned[tag] then
			self.warned[tag] = true
			warn(("[CombatSystem] %s has %s = '%s', which is not a valid NPC profile in config.npcs."):format(model:GetFullName(), PROFILE_ATTRIBUTE, tag))
		end
		return
	end
	local archivable = model.Archivable
	model.Archivable = true
	local template = model:Clone()
	model.Archivable = archivable
	local c = self.system.RegisterNPC(model, tag)
	if not c then
		return
	end
	local humanoid = c.humanoid
	humanoid.AutoRotate = false
	local tool = model:FindFirstChildOfClass("Tool")
	if tool then
		task.defer(function()
			if tool.Parent == model and humanoid.Parent == model then
				humanoid:EquipTool(tool)
			end
		end)
	end
	for _, state in ipairs(LOCKED_STATES) do
		humanoid:SetStateEnabled(state, false)
	end
	local entry = {
		model = model,
		combatant = c,
		profile = profile,
		template = template,
		parent = model.Parent,
		nextActionAt = 0,
		sequenceIndex = 0,
	}
	self.entries[model] = entry
	c.humanoid.Died:Connect(function()
		self:_onDied(entry)
	end)
end

function NPCService:_onDied(entry)
	self.entries[entry.model] = nil
	local delay = entry.profile.respawnTime
	if not delay or delay <= 0 or not entry.template then
		return
	end
	task.delay(delay, function()
		if not self.running then
			return
		end
		if entry.model.Parent then
			entry.model:Destroy()
		end
		if entry.parent and entry.parent:IsDescendantOf(Workspace) then
			entry.template:Clone().Parent = entry.parent
		end
	end)
end

function NPCService:start()
	self.running = true
	for _, inst in ipairs(Workspace:GetDescendants()) do
		if inst:IsA("Model") then
			self:_track(inst)
		end
	end
	table.insert(self.connections, Workspace.DescendantAdded:Connect(function(inst)
		if inst:IsA("Model") then
			task.defer(function()
				self:_track(inst)
			end)
		end
	end))
end

function NPCService:stop()
	self.running = false
	for _, c in ipairs(self.connections) do
		c:Disconnect()
	end
	table.clear(self.connections)
	table.clear(self.entries)
end

function NPCService:_interval(profile): number
	local range = profile.interval or DEFAULT_INTERVAL
	return self.rng:NextNumber(range[1], range[2])
end

function NPCService:_nearestPlayer(c, range: number)
	local best, bestDistance = nil, range
	for _, other in ipairs(self.system.GetCombatants()) do
		if not other.isNPC and other:isAlive() then
			local d = (other.root.Position - c.root.Position).Magnitude
			if d <= bestDistance then
				best, bestDistance = other, d
			end
		end
	end
	return best
end

function NPCService:_isReady(c, id: string): boolean
	if id == "M1" then
		return c:isReady("M1")
	end
	return c:isReady(c.weapon .. "." .. id)
end

function NPCService:_pick(entry): string?
	local profile = entry.profile
	local c = entry.combatant
	if profile.abilityMode == "sequence" then
		local id = profile.sequence[entry.sequenceIndex % #profile.sequence + 1]
		return if self:_isReady(c, id) then id else nil
	end
	local weapon = self.system.GetWeapon(c.weapon)
	if not weapon then
		return nil
	end
	local options = { "M1" }
	for _, ability in ipairs(weapon.abilities) do
		table.insert(options, ability.id)
	end
	local total, pool = 0, {}
	for _, id in ipairs(options) do
		local weight = if profile.weights then profile.weights[id] or 0 else 1
		if weight > 0 and self:_isReady(c, id) then
			total += weight
			table.insert(pool, { id = id, weight = weight })
		end
	end
	if total <= 0 then
		return nil
	end
	local roll = self.rng:NextNumber(0, total)
	for _, option in ipairs(pool) do
		roll -= option.weight
		if roll <= 0 then
			return option.id
		end
	end
	return pool[#pool].id
end

function NPCService:_turn(c, direction: Vector3)
	local position = c.root.Position
	c.root.CFrame = CFrame.lookAt(position, position + direction)
	c.root.AssemblyAngularVelocity = Vector3.zero
end

function NPCService:_stabilize(c)
	local root = c.root
	if c.state == "Ragdoll" then
		return
	end
	if root.CFrame.UpVector.Y >= UPRIGHT_LIMIT and root.AssemblyAngularVelocity.Magnitude < 0.5 then
		return
	end
	local look = flat(root.CFrame.LookVector)
	if look.Magnitude < 1e-3 then
		look = flat(root.CFrame.UpVector)
	end
	if look.Magnitude < 1e-3 then
		look = Vector3.new(0, 0, -1)
	end
	self:_turn(c, look.Unit)
end

function NPCService:_face(c, target)
	local delta = target.root.Position - c.root.Position
	local to = flat(delta)
	if to.Magnitude < 1e-3 then
		return
	end
	c.aimDirection = delta.Unit
	self:_turn(c, to.Unit)
end

function NPCService:_act(entry, now: number)
	local c = entry.combatant
	local profile = entry.profile
	local services = self.system.GetServices()
	if profile.behavior == "block" then
		if c.state == "Idle" and services.block then
			services.block:raise(c)
		end
	elseif profile.behavior == "attack" and services.attack then
		local target = self:_nearestPlayer(c, profile.range)
		if target then
			self:_face(c, target)
		else
			c.aimDirection = nil
		end
		if c.state == "Idle" and (target or profile.attackWithoutTarget) then
			local id = self:_pick(entry)
			if id then
				local ok = if id == "M1" then services.attack:m1(c) else services.attack:ability(c, id)
				if ok then
					entry.sequenceIndex += 1
				end
			end
		end
	end
	entry.nextActionAt = now + self:_interval(profile)
end

function NPCService:update(now: number)
	for model, entry in pairs(self.entries) do
		local c = entry.combatant
		if c.destroyed then
			self.entries[model] = nil
		elseif c:isAlive() then
			self:_stabilize(c)
			if entry.profile.behavior ~= "idle" and now >= entry.nextActionAt then
				self:_act(entry, now)
			end
		end
	end
end

return NPCService
