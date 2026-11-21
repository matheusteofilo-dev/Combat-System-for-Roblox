--!nonstrict

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local remotes = ReplicatedStorage:WaitForChild("CombatRemotes", 30)
local actionRemote = remotes and remotes:WaitForChild("CombatAction", 10)
local stateRemote = remotes and remotes:WaitForChild("CombatState", 10)
if not actionRemote or not stateRemote then
	warn("[CombatSystem] CombatRemotes not found in ReplicatedStorage; combat input is disabled.")
	return
end

local config = require(ReplicatedStorage:WaitForChild("CombatConfig"))
local CombatShared = require(ReplicatedStorage:WaitForChild("CombatShared"))
local ProceduralAnimator = require(script.ProceduralAnimator)
local MovementController = require(script.MovementController)
local CombatInput = require(script.CombatInput)
local ShieldIndicator = require(script.ShieldIndicator)
local HudController = require(script.HudController)
local Effects = require(script.Effects)
local DebugPanel = require(script.DebugPanel)

local context = {
	player = player,
	config = config,
	cooldowns = {},
	cooldownDurations = {},
	animator = ProceduralAnimator,
	effects = Effects,
}

function context.send(...)
	actionRemote:FireServer(...)
end

function context.now(): number
	return Workspace:GetServerTimeNow()
end

function context.stats()
	local s = {}
	for key, default in pairs(config.stats.defaults) do
		local v = player:GetAttribute("Stat_" .. key)
		s[key] = if type(v) == "number" then v else default
	end
	return s
end

function context.resolve(value)
	return CombatShared.resolve(value, context.stats())
end

function context.hasUnlock(key: string): boolean
	return player:GetAttribute("Unlock_" .. key) == true
end

function context.setCooldown(id: string, untilTime: number, duration: number)
	context.cooldowns[id] = untilTime
	context.cooldownDurations[id] = duration
end

function context.cooldownRemaining(id: string): number
	local untilTime = context.cooldowns[id]
	if not untilTime then
		return 0
	end
	return math.max(0, untilTime - context.now())
end

function context.combatState(): string
	local character = player.Character
	local state = character and character:GetAttribute("CombatState")
	return if type(state) == "string" then state else "Idle"
end

function context.currentWeapon()
	local character = player.Character
	local name = character and character:GetAttribute("Weapon")
	if type(name) ~= "string" then
		name = config.defaultWeapon
	end
	return name, config.weapons[name]
end

local function animationFor(weaponName, kind, key)
	local weapon = config.weapons[weaponName]
	if not weapon then
		return nil
	end
	if kind == "m1" then
		local hit = type(key) == "number" and weapon.m1.hits[key]
		return hit and hit.animation
	elseif kind == "ability" then
		for _, ability in ipairs(weapon.abilities) do
			if ability.id == key then
				return ability.animation
			end
		end
	end
	return nil
end

local movement = MovementController.new(context)
context.movement = movement
CombatInput.new(context)
local shields = ShieldIndicator.new(config.hud.indicatorDistance, config.hud.shieldWidthStuds)
local debugPanel = DebugPanel.new(context)
task.spawn(HudController.new, context)

local LOCAL_FX = { doubleJump = true, skyJump = true }

stateRemote.OnClientEvent:Connect(function(kind, ...)
	if kind == "cooldown" then
		local id, untilTime, duration = ...
		if type(id) == "string" and type(untilTime) == "number" and type(duration) == "number" then
			context.setCooldown(id, untilTime, duration)
		end
	elseif kind == "fx" then
		local effect, model = ...
		if LOCAL_FX[effect] and model == player.Character then
			return
		end
		if (effect == "hitbox" or effect == "hitsphere") and not debugPanel:wantsHitboxes() then
			return
		end
		Effects.play(...)
		if effect == "guardBreak" then
			shields:shatter(model)
		end
	elseif kind == "anim" then
		local model, weaponName, animKind, key = ...
		if typeof(model) == "Instance" and model:IsA("Model") then
			local animation = animationFor(weaponName, animKind, key)
			if animation then
				ProceduralAnimator.play(model, animation)
			end
		end
	elseif kind == "projectile" then
		local id, origin, direction, speed, range, weaponName = ...
		Effects.projectile(id, origin, direction, speed, range, weaponName, config)
	elseif kind == "debug" then
		debugPanel:setEnabled((...) == true)
	elseif kind == "projectileEnd" then
		Effects.projectileEnd(...)
	else
		movement:onServer(kind, ...)
	end
end)

local function onCharacter(character: Model)
	movement:bind(character)
end

local function watchActor(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local function refresh()
		local state = model:GetAttribute("CombatState")
		local own = model == player.Character
		if state == "Blocking" then
			shields:set(model, own or config.block.showToOthers)
			ProceduralAnimator.startGuard(model)
		else
			shields:set(model, false)
			ProceduralAnimator.stopGuard(model)
		end
		if not own then
			if state == "Climbing" then
				ProceduralAnimator.startClimb(model)
			else
				ProceduralAnimator.stopClimb(model)
			end
		end
	end
	model:GetAttributeChangedSignal("CombatState"):Connect(refresh)
	refresh()
end

CollectionService:GetInstanceAddedSignal(CombatShared.ACTOR_TAG):Connect(watchActor)
for _, model in ipairs(CollectionService:GetTagged(CombatShared.ACTOR_TAG)) do
	task.spawn(watchActor, model)
end

player.CharacterAdded:Connect(onCharacter)
if player.Character then
	task.spawn(onCharacter, player.Character)
end

actionRemote:FireServer("Sync")
