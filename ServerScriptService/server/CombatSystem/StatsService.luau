--!nonstrict

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CombatShared = require(ReplicatedStorage:WaitForChild("CombatShared"))

local DATA_VERSION = 1
local SAVE_ATTEMPTS = 3

local StatsService = {}
StatsService.__index = StatsService

local function keyFor(player: Player): string
	return "Player_" .. player.UserId
end

function StatsService.new(config)
	return setmetatable({
		cfg = config.stats,
		profiles = {},
		changed = CombatShared.newSignal(),
		connections = {},
		store = nil,
		running = false,
	}, StatsService)
end

function StatsService:_blank()
	return {
		version = DATA_VERSION,
		stats = table.clone(self.cfg.defaults),
		unlocks = table.clone(self.cfg.unlocks),
	}
end

function StatsService:_merge(raw)
	local data = self:_blank()
	if type(raw) ~= "table" then
		return data
	end
	if type(raw.stats) == "table" then
		for key in pairs(data.stats) do
			local v = raw.stats[key]
			if CombatShared.isFinite(v) then
				data.stats[key] = v
			end
		end
	end
	if type(raw.unlocks) == "table" then
		for key in pairs(data.unlocks) do
			if type(raw.unlocks[key]) == "boolean" then
				data.unlocks[key] = raw.unlocks[key]
			end
		end
	end
	return data
end

function StatsService:_publishAll(player: Player, profile)
	for key, value in pairs(profile.data.stats) do
		player:SetAttribute("Stat_" .. key, value)
	end
	for key, value in pairs(profile.data.unlocks) do
		player:SetAttribute("Unlock_" .. key, value)
	end
	profile.view = table.freeze(table.clone(profile.data.stats))
end

function StatsService:_load(player: Player)
	local profile = { data = self:_blank(), loaded = false, canSave = false, saving = false }
	profile.view = table.freeze(table.clone(profile.data.stats))
	self.profiles[player] = profile

	local store = self.store
	if store then
		local key = keyFor(player)
		local attempts = self.cfg.loadAttempts
		for attempt = 1, attempts do
			local locked = false
			local ok, result = pcall(function()
				return store:UpdateAsync(key, function(old)
					old = old or {}
					local lock = old.lock
					if type(lock) == "table" and lock.jobId ~= game.JobId and os.time() - (lock.time or 0) < self.cfg.sessionLockTimeout and attempt < attempts then
						locked = true
						return nil
					end
					old.lock = { jobId = game.JobId, time = os.time() }
					return old
				end)
			end)
			if self.profiles[player] ~= profile then
				if ok and not locked then
					self:_save(player, { data = self:_merge(result), loaded = true, canSave = true, saving = false }, true)
				end
				return
			end
			if ok and not locked then
				profile.data = self:_merge(result)
				profile.loaded = true
				profile.canSave = true
				break
			end
			if not ok then
				local message = tostring(result)
				if RunService:IsStudio() and (message:find("403", 1, true) or message:find("StudioAccessToApisNotAllowed", 1, true)) then
					warn("[CombatSystem] Studio has no DataStore access (Game Settings > Security > Enable Studio Access to API Services); stats are session-only.")
					break
				end
				warn(("[CombatSystem] stats load failed for %s (attempt %d/%d): %s"):format(player.Name, attempt, attempts, message))
			end
			task.wait(self.cfg.retryDelay)
		end
		if not profile.loaded then
			warn(("[CombatSystem] could not load stats for %s; using defaults for this session without saving."):format(player.Name))
		end
	end

	if self.profiles[player] ~= profile then
		return
	end
	self:_publishAll(player, profile)
	player:SetAttribute("CombatStatsLoaded", true)
	self.changed:Fire(player, "loaded")
	if not player.Parent then
		self:_release(player)
	end
end

function StatsService:_save(player: Player, profile, release: boolean): boolean
	if not self.store or not profile.canSave then
		return true
	end
	while profile.saving do
		task.wait(0.1)
	end
	profile.saving = true
	local snapshot = {
		version = DATA_VERSION,
		stats = table.clone(profile.data.stats),
		unlocks = table.clone(profile.data.unlocks),
		lock = if release then nil else { jobId = game.JobId, time = os.time() },
	}
	local key = keyFor(player)
	local saved = false
	for attempt = 1, SAVE_ATTEMPTS do
		local stolen = false
		local ok, err = pcall(function()
			self.store:UpdateAsync(key, function(old)
				if type(old) == "table" and type(old.lock) == "table" and old.lock.jobId ~= game.JobId then
					stolen = true
					return nil
				end
				return snapshot
			end)
		end)
		if ok then
			saved = not stolen
			if stolen then
				warn(("[CombatSystem] stats of %s are locked by another server; not saved."):format(player.Name))
				profile.canSave = false
			end
			break
		end
		warn(("[CombatSystem] stats save failed for %s (attempt %d/%d): %s"):format(player.Name, attempt, SAVE_ATTEMPTS, tostring(err)))
		if attempt < SAVE_ATTEMPTS then
			task.wait(self.cfg.retryDelay)
		end
	end
	profile.saving = false
	if release then
		profile.canSave = false
	end
	return saved
end

function StatsService:_release(player: Player)
	local profile = self.profiles[player]
	if not profile then
		return
	end
	self.profiles[player] = nil
	if profile.loaded then
		self:_save(player, profile, true)
	end
end

function StatsService:start()
	if self.running then
		return
	end
	self.running = true
	local studio = RunService:IsStudio()
	if studio and not self.cfg.saveInStudio then
		warn("[CombatSystem] stats.saveInStudio is false; stats are session-only in Studio.")
	else
		local name = if studio then self.cfg.studioDataStoreName else self.cfg.dataStoreName
		local ok, result = pcall(DataStoreService.GetDataStore, DataStoreService, name)
		if ok then
			self.store = result
		else
			warn(("[CombatSystem] DataStore unavailable (%s); stats are session-only. In Studio, enable 'Studio Access to API Services'."):format(tostring(result)))
		end
	end

	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(self._load, self, player)
	end
	table.insert(self.connections, Players.PlayerAdded:Connect(function(player)
		self:_load(player)
	end))
	table.insert(self.connections, Players.PlayerRemoving:Connect(function(player)
		self:_release(player)
	end))

	task.spawn(function()
		while self.running do
			task.wait(self.cfg.autosaveInterval)
			if not self.running then
				break
			end
			for player, profile in pairs(self.profiles) do
				if profile.loaded and profile.dirty then
					profile.dirty = false
					task.spawn(self._save, self, player, profile, false)
				end
			end
		end
	end)

	game:BindToClose(function()
		if not self.running then
			return
		end
		local pending = 0
		for player in pairs(table.clone(self.profiles)) do
			pending += 1
			task.spawn(function()
				self:_release(player)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

function StatsService:stop()
	if not self.running then
		return
	end
	self.running = false
	for _, c in ipairs(self.connections) do
		c:Disconnect()
	end
	table.clear(self.connections)
	for player in pairs(table.clone(self.profiles)) do
		task.spawn(self._release, self, player)
	end
end

function StatsService:isLoaded(player: Player): boolean
	local profile = self.profiles[player]
	return profile ~= nil and profile.loaded
end

function StatsService:get(player: Player)
	local profile = self.profiles[player]
	if profile then
		return profile.view
	end
	return table.freeze(table.clone(self.cfg.defaults))
end

function StatsService:set(player: Player, key: string, value: number): boolean
	local profile = self.profiles[player]
	if not profile or profile.data.stats[key] == nil or not CombatShared.isFinite(value) then
		return false
	end
	profile.data.stats[key] = value
	profile.dirty = true
	profile.view = table.freeze(table.clone(profile.data.stats))
	player:SetAttribute("Stat_" .. key, value)
	self.changed:Fire(player, "stat", key, value)
	return true
end

function StatsService:add(player: Player, key: string, delta: number): boolean
	local profile = self.profiles[player]
	if not profile or profile.data.stats[key] == nil or not CombatShared.isFinite(delta) then
		return false
	end
	return self:set(player, key, profile.data.stats[key] + delta)
end

function StatsService:getUnlock(player: Player, key: string): boolean
	local profile = self.profiles[player]
	return profile ~= nil and profile.data.unlocks[key] == true
end

function StatsService:setUnlock(player: Player, key: string, value: boolean): boolean
	local profile = self.profiles[player]
	if not profile or profile.data.unlocks[key] == nil or type(value) ~= "boolean" then
		return false
	end
	profile.data.unlocks[key] = value
	profile.dirty = true
	player:SetAttribute("Unlock_" .. key, value)
	self.changed:Fire(player, "unlock", key, value)
	return true
end

return StatsService
