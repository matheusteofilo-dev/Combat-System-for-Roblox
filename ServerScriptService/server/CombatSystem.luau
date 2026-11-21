--!nonstrict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local config = require(ReplicatedStorage:WaitForChild("CombatConfig"))
local CombatShared = require(ReplicatedStorage:WaitForChild("CombatShared"))
local Validator = require(script.ConfigValidator)
local Combatant = require(script.Combatant)
local StatsService = require(script.StatsService)
local MovementAuthority = require(script.MovementAuthority)
local BlockService = require(script.BlockService)
local HitService = require(script.HitService)
local AttackService = require(script.AttackService)
local NPCService = require(script.NPCService)

local MAX_ACTION_ARGS = 4
local MAX_STRING_LENGTH = 32

local CombatSystem = {}
CombatSystem.config = config
CombatSystem.StatsChanged = CombatShared.newSignal()
CombatSystem.CombatantAdded = CombatShared.newSignal()
CombatSystem.CombatantRemoved = CombatShared.newSignal()
CombatSystem.Damaged = CombatShared.newSignal()

local started = false
local combatants = {}
local connections = {}
local playerConnections = {}
local actionHandlers = {}
local actionBudget = {}
local weapons = {}
local npcProfiles = {}
local stats = nil
local movement = nil
local blocks = nil
local hits = nil
local attacks = nil
local npcs = nil
local actionRemote = nil
local stateRemote = nil
local warnedWeapons = {}
local registerBuiltInActions

local function log(msg: string)
	print("[CombatSystem] " .. msg)
end

local function weaponFromCharacter(character: Model): string
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") then
			local name = child:GetAttribute("Weapon")
			if name == nil and weapons[child.Name] then
				name = child.Name
			end
			if weapons[name] then
				return name
			end
			if name ~= nil and not warnedWeapons[name] then
				warnedWeapons[name] = true
				warn(("[CombatSystem] tool %s has Weapon = '%s', which is not a valid weapon; using %s."):format(child:GetFullName(), tostring(name), config.defaultWeapon))
			end
		end
	end
	return config.defaultWeapon
end

function CombatSystem.Send(player: Player, ...)
	if stateRemote and player.Parent then
		stateRemote:FireClient(player, ...)
	end
end

function CombatSystem.Broadcast(origin: Vector3, ...)
	if not stateRemote then
		return
	end
	local range = config.network.animationRange
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and (root.Position - origin).Magnitude <= range then
			stateRemote:FireClient(player, ...)
		end
	end
end

local debugPlayers = {}

local function debugAllowed(player: Player): boolean
	local cfg = config.debug
	if not cfg.enabled then
		return false
	end
	if cfg.studioOnly and RunService:IsStudio() then
		return true
	end
	return table.find(cfg.userIds, player.UserId) ~= nil
end

function CombatSystem.SendDebug(...)
	if not stateRemote then
		return
	end
	for player in pairs(debugPlayers) do
		if player.Parent then
			stateRemote:FireClient(player, ...)
		else
			debugPlayers[player] = nil
		end
	end
end

local function removeCombatant(model: Model, reason: string)
	local c = combatants[model]
	if not c then
		return
	end
	combatants[model] = nil
	if movement then
		movement:forget(c)
	end
	c:destroy()
	CombatSystem.CombatantRemoved:Fire(c, reason)
end

local function addCombatant(model: Model, humanoid: Humanoid, root: BasePart, options)
	removeCombatant(model, "replaced")
	options.config = config
	local c = Combatant.new(model, humanoid, root, options)
	combatants[model] = c
	table.insert(c.connections, humanoid.Died:Connect(function()
		removeCombatant(model, "died")
	end))
	table.insert(c.connections, model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(Workspace) then
			removeCombatant(model, "removed from workspace")
		end
	end))
	if c.player then
		local player = c.player
		table.insert(c.connections, c.changed:Connect(function(kind, id, untilTime, duration)
			if kind == "cooldown" and combatants[model] == c then
				CombatSystem.Send(player, "cooldown", id, untilTime, duration)
			end
		end))
	end
	CombatSystem.CombatantAdded:Fire(c)
	return c
end

local function hookCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not started or player.Character ~= character then
		return
	end
	if not humanoid or not root then
		warn(("[CombatSystem] %s has no Humanoid/HumanoidRootPart; combat disabled for this character."):format(character:GetFullName()))
		return
	end
	local c = addCombatant(character, humanoid, root, {
		player = player,
		weapon = weaponFromCharacter(character),
		statsProvider = function()
			return stats:get(player)
		end,
		unlockProvider = function(key)
			return stats:getUnlock(player, key)
		end,
	})
	local function refreshWeapon(child)
		if child:IsA("Tool") and combatants[character] == c then
			c:setWeapon(weaponFromCharacter(character))
		end
	end
	table.insert(c.connections, character.ChildAdded:Connect(refreshWeapon))
	table.insert(c.connections, character.ChildRemoved:Connect(refreshWeapon))
end

local function addPlayer(player: Player)
	local list = {}
	playerConnections[player] = list
	table.insert(list, player.CharacterAdded:Connect(function(character)
		hookCharacter(player, character)
	end))
	if player.Character then
		task.spawn(hookCharacter, player, player.Character)
	end
end

local function removePlayer(player: Player)
	local list = playerConnections[player]
	if list then
		for _, c in ipairs(list) do
			c:Disconnect()
		end
	end
	playerConnections[player] = nil
	actionBudget[player] = nil
	debugPlayers[player] = nil
end

local function allowAction(player: Player): boolean
	local now = os.clock()
	local budget = actionBudget[player]
	if not budget or now - budget.windowStart >= 1 then
		budget = { windowStart = now, count = 0 }
		actionBudget[player] = budget
	end
	budget.count += 1
	return budget.count <= config.network.maxActionsPerSecond
end

local function argsAreSafe(count: number, ...): boolean
	if count > MAX_ACTION_ARGS then
		return false
	end
	for i = 1, count do
		local v = select(i, ...)
		local t = type(v)
		if t == "string" then
			if #v > MAX_STRING_LENGTH then
				return false
			end
		elseif t == "number" then
			if not CombatShared.isFinite(v) or math.abs(v) > 1000 then
				return false
			end
		elseif t ~= "boolean" and t ~= "nil" then
			return false
		end
	end
	return true
end

local function onAction(player: Player, action, ...)
	if type(action) ~= "string" or #action > MAX_STRING_LENGTH then
		return
	end
	if not allowAction(player) then
		return
	end
	local handler = actionHandlers[action]
	if not handler then
		return
	end
	if not argsAreSafe(select("#", ...), ...) then
		return
	end
	local character = player.Character
	local c = character and combatants[character]
	if not c or c.player ~= player or not c:isAlive() then
		return
	end
	local ok, err = xpcall(handler, debug.traceback, c, ...)
	if not ok then
		warn(("[CombatSystem] action '%s' from %s failed: %s"):format(action, player.Name, tostring(err)))
	end
end

function CombatSystem.RegisterAction(name: string, handler)
	if actionHandlers[name] then
		warn(("[CombatSystem] action '%s' registered twice; the last one wins."):format(name))
	end
	actionHandlers[name] = handler
end

local function step(dt: number)
	local now = Combatant.now()
	for _, c in pairs(table.clone(combatants)) do
		local ok, err = xpcall(c.update, debug.traceback, c, now, dt)
		if ok and movement and combatants[c.model] == c then
			ok, err = xpcall(movement.update, debug.traceback, movement, c, now, dt)
		end
		if not ok then
			warn(("[CombatSystem] update error on %s: %s"):format(c.model.Name, tostring(err)))
		end
	end
	if attacks then
		local ok, err = xpcall(attacks.update, debug.traceback, attacks, dt)
		if not ok then
			warn("[CombatSystem] projectile update error: " .. tostring(err))
		end
	end
	if npcs then
		local ok, err = xpcall(npcs.update, debug.traceback, npcs, now)
		if not ok then
			warn("[CombatSystem] NPC update error: " .. tostring(err))
		end
	end
end

function registerBuiltInActions()
	CombatSystem.RegisterAction("Debug", function(c, on)
		if type(on) ~= "boolean" then
			return
		end
		local allowed = on and debugAllowed(c.player)
		debugPlayers[c.player] = if allowed then true else nil
		CombatSystem.Send(c.player, "debug", allowed)
	end)
	CombatSystem.RegisterAction("DebugUnlock", function(c, key, on)
		if not debugPlayers[c.player] or type(key) ~= "string" or type(on) ~= "boolean" then
			return
		end
		if config.stats.unlocks[key] == nil then
			return
		end
		CombatSystem.SetUnlock(c.player, key, on)
	end)
	CombatSystem.RegisterAction("Sync", function(c)
		local now = Combatant.now()
		for id, untilTime in pairs(c.cooldowns) do
			if untilTime > now then
				CombatSystem.Send(c.player, "cooldown", id, untilTime, untilTime - now)
			end
		end
		CombatSystem.Send(c.player, "synced", c.state, c.airJumps)
	end)
end
registerBuiltInActions()

function CombatSystem.Start()
	if started then
		return
	end
	for name, weapon in pairs(config.weapons) do
		local errors = Validator.validateWeapon(name, weapon, config)
		if #errors == 0 then
			weapons[name] = weapon
		else
			warn(("[CombatSystem] weapon '%s' disabled:\n  - %s"):format(tostring(name), table.concat(errors, "\n  - ")))
		end
	end
	local errors = Validator.validateGlobal(config)
	if #errors > 0 then
		table.clear(weapons)
		error("[CombatSystem] invalid global configuration:\n  - " .. table.concat(errors, "\n  - "), 0)
	end
	for tag, npc in pairs(config.npcs) do
		local npcErrors = Validator.validateNPC(tag, npc, config, weapons)
		if #npcErrors == 0 then
			npcProfiles[tag] = npc
		else
			warn(("[CombatSystem] NPC profile '%s' disabled:\n  - %s"):format(tostring(tag), table.concat(npcErrors, "\n  - ")))
		end
	end

	local remotes = ReplicatedStorage:FindFirstChild("CombatRemotes")
	actionRemote = remotes and remotes:FindFirstChild("CombatAction")
	stateRemote = remotes and remotes:FindFirstChild("CombatState")
	if not (actionRemote and actionRemote:IsA("RemoteEvent") and stateRemote and stateRemote:IsA("RemoteEvent")) then
		actionRemote, stateRemote = nil, nil
		warn("[CombatSystem] CombatRemotes (CombatAction, CombatState) not found in ReplicatedStorage; player input is disabled, NPC combat still works.")
	end

	started = true
	local api = {
		RegisterAction = CombatSystem.RegisterAction,
		Send = CombatSystem.Send,
		Broadcast = CombatSystem.Broadcast,
		SendDebug = CombatSystem.SendDebug,
		now = Combatant.now,
		GetWeapon = CombatSystem.GetWeapon,
		GetCombatant = CombatSystem.GetCombatant,
		GetCombatants = CombatSystem.GetCombatants,
		Damaged = CombatSystem.Damaged,
	}
	movement = MovementAuthority.new(api, config)
	blocks = BlockService.new(api, config)
	hits = HitService.new(api, config, movement, blocks)
	blocks.hit = hits
	attacks = AttackService.new(api, config, hits)
	stats = StatsService.new(config)
	table.insert(connections, stats.changed:Connect(function(player, kind, key, value)
		local character = player.Character
		local c = character and combatants[character]
		if c then
			c:refreshDerived(false)
		end
		CombatSystem.StatsChanged:Fire(player, kind, key, value)
	end))
	stats:start()

	if actionRemote then
		table.insert(connections, actionRemote.OnServerEvent:Connect(onAction))
	end
	for _, player in ipairs(Players:GetPlayers()) do
		addPlayer(player)
	end
	table.insert(connections, Players.PlayerAdded:Connect(addPlayer))
	table.insert(connections, Players.PlayerRemoving:Connect(removePlayer))
	table.insert(connections, RunService.Heartbeat:Connect(step))
	npcs = NPCService.new(CombatSystem, config, npcProfiles)
	npcs:start()
	log("started")
end

function CombatSystem.Stop()
	if not started then
		return
	end
	started = false
	if npcs then
		npcs:stop()
		npcs = nil
	end
	for _, c in ipairs(connections) do
		c:Disconnect()
	end
	table.clear(connections)
	for player in pairs(table.clone(playerConnections)) do
		removePlayer(player)
	end
	for model in pairs(table.clone(combatants)) do
		removeCombatant(model, "system stopped")
	end
	if stats then
		stats:stop()
		stats = nil
	end
	if attacks then
		attacks:clear()
	end
	movement, blocks, hits, attacks = nil, nil, nil, nil
	table.clear(actionHandlers)
	registerBuiltInActions()
	table.clear(weapons)
	table.clear(npcProfiles)
end

function CombatSystem.ResetMovementGuard(model: Instance, grace: number?)
	local c = combatants[model]
	if c and movement then
		movement:resetGuard(c, grace)
	end
end

function CombatSystem.GrantMovement(model: Instance, horizontalSpeed: number, rise: number, duration: number)
	local c = combatants[model]
	if c and movement and CombatShared.isFinite(horizontalSpeed) and CombatShared.isFinite(rise) and CombatShared.isFinite(duration) then
		movement:grant(c, horizontalSpeed, rise, duration)
	end
end

function CombatSystem.GetMovement()
	return movement
end

function CombatSystem.GetServices()
	return { movement = movement, block = blocks, hit = hits, attack = attacks }
end

function CombatSystem.RegisterNPC(model: Model, tag: string)
	local profile = npcProfiles[tag]
	if not started or not profile then
		return nil
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root then
		warn(("[CombatSystem] %s has no Humanoid/root part; NPC combat disabled."):format(model:GetFullName()))
		return nil
	end
	local npcStats = table.clone(config.stats.defaults)
	if profile.stats then
		for key, value in pairs(profile.stats) do
			npcStats[key] = value
		end
	end
	npcStats = table.freeze(npcStats)
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	return addCombatant(model, humanoid, root, {
		weapon = profile.weapon,
		statsProvider = function()
			return npcStats
		end,
		unlockProvider = function()
			return false
		end,
	})
end

function CombatSystem.GetNPCProfile(tag: string)
	return npcProfiles[tag]
end

function CombatSystem.GetWeapon(name: string)
	return weapons[name]
end

function CombatSystem.GetCombatant(model: Instance)
	return combatants[model]
end

function CombatSystem.GetCombatants()
	local list = {}
	for _, c in pairs(combatants) do
		table.insert(list, c)
	end
	return list
end

function CombatSystem.GetStats(player: Player)
	return stats and stats:get(player)
end

function CombatSystem.SetStat(player: Player, key: string, value: number): boolean
	return stats ~= nil and stats:set(player, key, value)
end

function CombatSystem.AddStat(player: Player, key: string, delta: number): boolean
	return stats ~= nil and stats:add(player, key, delta)
end

function CombatSystem.GetUnlock(player: Player, key: string): boolean
	return stats ~= nil and stats:getUnlock(player, key)
end

function CombatSystem.SetUnlock(player: Player, key: string, value: boolean): boolean
	return stats ~= nil and stats:setUnlock(player, key, value)
end

function CombatSystem.IsStatsLoaded(player: Player): boolean
	return stats ~= nil and stats:isLoaded(player)
end

return CombatSystem
