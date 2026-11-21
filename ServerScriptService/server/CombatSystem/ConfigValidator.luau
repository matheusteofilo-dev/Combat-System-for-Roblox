--!nonstrict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatShared = require(ReplicatedStorage:WaitForChild("CombatShared"))

local Validator = {}

local isFinite = CombatShared.isFinite

local function checkNumber(errors, path, value, min, max, minExclusive)
	if not isFinite(value) then
		table.insert(errors, ("%s must be a finite number (got %s)"):format(path, tostring(value)))
		return false
	end
	if min ~= nil and ((minExclusive and value <= min) or (not minExclusive and value < min)) then
		table.insert(errors, ("%s must be %s %s (got %s)"):format(path, if minExclusive then ">" else ">=", tostring(min), tostring(value)))
		return false
	end
	if max ~= nil and value > max then
		table.insert(errors, ("%s must be <= %s (got %s)"):format(path, tostring(max), tostring(value)))
		return false
	end
	return true
end

local function checkValue(errors, path, value, stats, min, max, minExclusive)
	if type(value) == "function" then
		local ok, result = pcall(value, stats)
		if not ok then
			table.insert(errors, ("%s errored with default stats: %s"):format(path, tostring(result)))
			return false
		end
		return checkNumber(errors, path .. "(defaults)", result, min, max, minExclusive)
	end
	return checkNumber(errors, path, value, min, max, minExclusive)
end

local function checkBool(errors, path, value)
	if type(value) ~= "boolean" then
		table.insert(errors, ("%s must be a boolean (got %s)"):format(path, tostring(value)))
		return false
	end
	return true
end

local function checkString(errors, path, value)
	if type(value) ~= "string" or value == "" then
		table.insert(errors, ("%s must be a non-empty string (got %s)"):format(path, tostring(value)))
		return false
	end
	return true
end

local function checkTable(errors, path, value)
	if type(value) ~= "table" then
		table.insert(errors, ("%s must be a table (got %s)"):format(path, type(value)))
		return false
	end
	return true
end

local function checkKey(errors, path, value)
	if not CombatShared.keyCode(value) then
		table.insert(errors, ("%s must be an Enum.KeyCode name (got %s)"):format(path, tostring(value)))
		return false
	end
	return true
end

local function checkAnimation(errors, path, anim)
	if anim == nil then
		return
	end
	if not checkTable(errors, path, anim) then
		return
	end
	if anim.id ~= nil and type(anim.id) ~= "string" then
		table.insert(errors, path .. ".id must be a string")
	end
	if anim.keyframes ~= nil then
		checkNumber(errors, path .. ".duration", anim.duration, 0, nil, true)
		if checkTable(errors, path .. ".keyframes", anim.keyframes) then
			local last = -math.huge
			for i, kf in ipairs(anim.keyframes) do
				local kp = ("%s.keyframes[%d]"):format(path, i)
				if checkTable(errors, kp, kf) and checkNumber(errors, kp .. ".t", kf.t, 0) then
					if kf.t < last then
						table.insert(errors, kp .. ".t must not be lower than the previous keyframe")
					end
					last = kf.t
					checkTable(errors, kp .. ".pose", kf.pose)
				end
			end
		end
	end
end

local function checkAttack(errors, path, attack, stats)
	if not checkTable(errors, path, attack) then
		return
	end
	checkNumber(errors, path .. ".windup", attack.windup, 0)
	checkNumber(errors, path .. ".recovery", attack.recovery, 0)
	checkValue(errors, path .. ".damage", attack.damage, stats, 0)
	if attack.knockback ~= nil then
		checkValue(errors, path .. ".knockback", attack.knockback, stats, 0)
	end
	if attack.launch ~= nil then
		checkValue(errors, path .. ".launch", attack.launch, stats, 0)
	end
	if attack.breaksBlock ~= nil then
		checkBool(errors, path .. ".breaksBlock", attack.breaksBlock)
	end
	local kind = attack.kind or "melee"
	if kind == "melee" then
		if checkTable(errors, path .. ".hitbox", attack.hitbox) then
			if typeof(attack.hitbox.size) ~= "Vector3" then
				table.insert(errors, path .. ".hitbox.size must be a Vector3")
			end
			if typeof(attack.hitbox.offset) ~= "CFrame" then
				table.insert(errors, path .. ".hitbox.offset must be a CFrame")
			end
		end
	elseif kind == "projectile" then
		if checkTable(errors, path .. ".projectile", attack.projectile) then
			local p = attack.projectile
			checkNumber(errors, path .. ".projectile.speed", p.speed, 0, nil, true)
			checkNumber(errors, path .. ".projectile.range", p.range, 0, nil, true)
			checkNumber(errors, path .. ".projectile.radius", p.radius, 0, nil, true)
			checkNumber(errors, path .. ".projectile.explosionRadius", p.explosionRadius, 0)
		end
	elseif kind == "area" then
		if checkTable(errors, path .. ".area", attack.area) then
			checkNumber(errors, path .. ".area.radius", attack.area.radius, 0, nil, true)
		end
	else
		table.insert(errors, ("%s.kind must be \"melee\", \"projectile\" or \"area\" (got %s)"):format(path, tostring(kind)))
	end
	checkAnimation(errors, path .. ".animation", attack.animation)
end

function Validator.validateWeapon(name, weapon, config)
	local errors = {}
	local p = "weapons." .. tostring(name)
	local stats = config.stats.defaults
	if not checkTable(errors, p, weapon) then
		return errors
	end
	checkString(errors, p .. ".displayName", weapon.displayName)
	if checkTable(errors, p .. ".m1", weapon.m1) then
		local m1 = weapon.m1
		checkNumber(errors, p .. ".m1.comboResetTime", m1.comboResetTime, 0)
		checkNumber(errors, p .. ".m1.comboEndCooldown", m1.comboEndCooldown, 0)
		if checkTable(errors, p .. ".m1.hits", m1.hits) then
			if #m1.hits == 0 then
				table.insert(errors, p .. ".m1.hits must have at least one hit")
			end
			for i, hit in ipairs(m1.hits) do
				checkAttack(errors, ("%s.m1.hits[%d]"):format(p, i), hit, stats)
			end
		end
	end
	local globalKeys = {}
	for _, key in pairs(config.keys) do
		globalKeys[key] = true
	end
	if checkTable(errors, p .. ".abilities", weapon.abilities) then
		local ids, keys = {}, {}
		for i, ability in ipairs(weapon.abilities) do
			local ap = ("%s.abilities[%d]"):format(p, i)
			if checkTable(errors, ap, ability) then
				if checkString(errors, ap .. ".id", ability.id) then
					if CombatShared.RESERVED_ACTIONS[ability.id] then
						table.insert(errors, ap .. ".id uses a reserved name: " .. ability.id)
					elseif ids[ability.id] then
						table.insert(errors, ap .. ".id is duplicated: " .. ability.id)
					end
					ids[ability.id] = true
				end
				checkString(errors, ap .. ".name", ability.name)
				if checkKey(errors, ap .. ".key", ability.key) then
					if globalKeys[ability.key] then
						table.insert(errors, ap .. ".key conflicts with config.keys: " .. ability.key)
					elseif keys[ability.key] then
						table.insert(errors, ap .. ".key is used twice in this weapon: " .. ability.key)
					end
					keys[ability.key] = true
				end
				checkValue(errors, ap .. ".cooldown", ability.cooldown, stats, 0)
				checkAttack(errors, ap, ability, stats)
			end
		end
	end
	return errors
end

function Validator.validateNPC(tag, npc, config, weapons)
	local errors = {}
	local p = "npcs." .. tostring(tag)
	if not checkTable(errors, p, npc) then
		return errors
	end
	local weapon = weapons[npc.weapon]
	if not weapon then
		table.insert(errors, ("%s.weapon '%s' is not a valid weapon"):format(p, tostring(npc.weapon)))
	end
	local behavior = npc.behavior
	if behavior ~= "idle" and behavior ~= "block" and behavior ~= "attack" then
		table.insert(errors, p .. ".behavior must be \"idle\", \"block\" or \"attack\"")
	end
	local known = { M1 = true }
	if weapon then
		for _, ability in ipairs(weapon.abilities) do
			known[ability.id] = true
		end
	end
	if behavior == "attack" then
		if npc.abilityMode ~= "random" and npc.abilityMode ~= "sequence" then
			table.insert(errors, p .. ".abilityMode must be \"random\" or \"sequence\"")
		end
		if npc.abilityMode == "sequence" then
			if checkTable(errors, p .. ".sequence", npc.sequence) and #npc.sequence == 0 then
				table.insert(errors, p .. ".sequence must not be empty")
			end
		end
		checkNumber(errors, p .. ".range", npc.range, 0, nil, true)
		checkBool(errors, p .. ".attackWithoutTarget", npc.attackWithoutTarget)
	end
	if npc.sequence ~= nil and type(npc.sequence) == "table" then
		for i, id in ipairs(npc.sequence) do
			if not known[id] then
				table.insert(errors, ("%s.sequence[%d] '%s' is not M1 or an ability of %s"):format(p, i, tostring(id), tostring(npc.weapon)))
			end
		end
	end
	if npc.weights ~= nil and checkTable(errors, p .. ".weights", npc.weights) then
		for id, w in pairs(npc.weights) do
			if not known[id] then
				table.insert(errors, ("%s.weights.%s is not M1 or an ability of %s"):format(p, tostring(id), tostring(npc.weapon)))
			end
			checkNumber(errors, p .. ".weights." .. tostring(id), w, 0)
		end
	end
	if npc.interval ~= nil and checkTable(errors, p .. ".interval", npc.interval) then
		local r = npc.interval
		if checkNumber(errors, p .. ".interval[1]", r[1], 0) and checkNumber(errors, p .. ".interval[2]", r[2], 0) and r[2] < r[1] then
			table.insert(errors, p .. ".interval[2] must be >= interval[1]")
		end
	end
	if npc.stats ~= nil and checkTable(errors, p .. ".stats", npc.stats) then
		for key, v in pairs(npc.stats) do
			if config.stats.defaults[key] == nil then
				table.insert(errors, ("%s.stats.%s is not a stat in config.stats.defaults"):format(p, tostring(key)))
			end
			checkNumber(errors, p .. ".stats." .. tostring(key), v)
		end
	end
	if npc.respawnTime ~= nil then
		checkNumber(errors, p .. ".respawnTime", npc.respawnTime, 0)
	end
	return errors
end

function Validator.validateGlobal(config)
	local errors = {}
	if not checkTable(errors, "config.stats", config.stats) then
		return errors
	end
	local s = config.stats
	checkString(errors, "stats.dataStoreName", s.dataStoreName)
	checkString(errors, "stats.studioDataStoreName", s.studioDataStoreName)
	if s.dataStoreName == s.studioDataStoreName then
		table.insert(errors, "stats.studioDataStoreName must differ from stats.dataStoreName (Studio must never touch live data)")
	end
	checkBool(errors, "stats.saveInStudio", s.saveInStudio)
	checkNumber(errors, "stats.autosaveInterval", s.autosaveInterval, 30)
	checkNumber(errors, "stats.sessionLockTimeout", s.sessionLockTimeout, 30)
	checkNumber(errors, "stats.loadAttempts", s.loadAttempts, 1)
	checkNumber(errors, "stats.retryDelay", s.retryDelay, 0)
	if checkTable(errors, "stats.defaults", s.defaults) then
		for key, v in pairs(s.defaults) do
			checkNumber(errors, "stats.defaults." .. tostring(key), v)
		end
	end
	if checkTable(errors, "stats.unlocks", s.unlocks) then
		for key, v in pairs(s.unlocks) do
			checkBool(errors, "stats.unlocks." .. tostring(key), v)
		end
	end
	local stats = s.defaults or {}

	if checkTable(errors, "keys", config.keys) then
		local seen = {}
		for name, key in pairs(config.keys) do
			if checkKey(errors, "keys." .. name, key) then
				if seen[key] then
					table.insert(errors, ("keys.%s uses the same key as keys.%s"):format(name, seen[key]))
				end
				seen[key] = name
			end
		end
	end

	local function group(name)
		return checkTable(errors, name, config[name]) and config[name]
	end

	local n = group("network")
	if n then
		checkNumber(errors, "network.maxActionsPerSecond", n.maxActionsPerSecond, 1)
		checkNumber(errors, "network.animationRange", n.animationRange, 0, nil, true)
	end
	local h = group("health")
	if h then
		checkValue(errors, "health.max", h.max, stats, 0, nil, true)
	end
	local r = group("run")
	if r then
		checkValue(errors, "run.walkSpeed", r.walkSpeed, stats, 0)
		checkValue(errors, "run.speed", r.speed, stats, 0)
		checkBool(errors, "run.cancelOnAction", r.cancelOnAction)
		checkNumber(errors, "run.doubleTapWindow", r.doubleTapWindow, 0.05)
	end
	local d = group("dash")
	if d then
		checkValue(errors, "dash.distance", d.distance, stats, 0, nil, true)
		checkValue(errors, "dash.duration", d.duration, stats, 0, nil, true)
		checkValue(errors, "dash.cooldown", d.cooldown, stats, 0)
		checkBool(errors, "dash.iFrames", d.iFrames)
	end
	local j = group("jump")
	if j then
		checkValue(errors, "jump.doubleJumpPower", j.doubleJumpPower, stats, 0, nil, true)
		if checkTable(errors, "jump.skyJump", j.skyJump) then
			checkValue(errors, "jump.skyJump.power", j.skyJump.power, stats, 0, nil, true)
			checkValue(errors, "jump.skyJump.horizontalSpeed", j.skyJump.horizontalSpeed, stats, 0)
			checkValue(errors, "jump.skyJump.cooldown", j.skyJump.cooldown, stats, 0)
		end
	end
	local b = group("block")
	if b then
		checkNumber(errors, "block.arc", b.arc, 0, 360, true)
		checkValue(errors, "block.max", b.max, stats, 0, nil, true)
		checkNumber(errors, "block.regenDelay", b.regenDelay, 0)
		checkValue(errors, "block.regenRate", b.regenRate, stats, 0)
		checkValue(errors, "block.walkSpeed", b.walkSpeed, stats, 0)
		checkValue(errors, "block.guardBreakStun", b.guardBreakStun, stats, 0)
		checkNumber(errors, "block.minRaiseFraction", b.minRaiseFraction, 0, 1)
		checkBool(errors, "block.showToOthers", b.showToOthers)
	end
	local hit = group("hit")
	if hit then
		checkValue(errors, "hit.hitStun", hit.hitStun, stats, 0)
		checkNumber(errors, "hit.reachTolerance", hit.reachTolerance, 0)
		checkNumber(errors, "hit.maxTargets", hit.maxTargets, 1)
		checkBool(errors, "hit.pvp", hit.pvp)
		checkBool(errors, "hit.npcFriendlyFire", hit.npcFriendlyFire)
		checkBool(errors, "hit.lineOfSight", hit.lineOfSight)
		checkNumber(errors, "hit.knockbackTime", hit.knockbackTime, 0.05)
	end
	local dbg = group("debug")
	if dbg then
		checkBool(errors, "debug.showHitboxes", dbg.showHitboxes)
		checkBool(errors, "debug.enabled", dbg.enabled)
		checkBool(errors, "debug.studioOnly", dbg.studioOnly)
		if type(dbg.userIds) ~= "table" then
			table.insert(errors, "debug.userIds must be a table of user ids")
		end
	end
	local hud = group("hud")
	if hud then
		checkNumber(errors, "hud.indicatorDistance", hud.indicatorDistance, 5)
		checkNumber(errors, "hud.shieldWidthStuds", hud.shieldWidthStuds, 0.2)
	end
	local c = group("climb")
	if c then
		checkNumber(errors, "climb.reach", c.reach, 0, nil, true)
		checkValue(errors, "climb.time", c.time, stats, 0, nil, true)
		checkValue(errors, "climb.speed", c.speed, stats, 0, nil, true)
		checkNumber(errors, "climb.ragdollFallHeight", c.ragdollFallHeight, 0)
		checkNumber(errors, "climb.cooldown", c.cooldown, 0)
		checkValue(errors, "climb.jumpPower", c.jumpPower, stats, 0)
		checkValue(errors, "climb.jumpAwaySpeed", c.jumpAwaySpeed, stats, 0)
		checkNumber(errors, "climb.wallCheckInterval", c.wallCheckInterval, 0.05)
		checkNumber(errors, "climb.wallMisses", c.wallMisses, 1)
	end
	local rg = group("ragdoll")
	if rg then
		checkNumber(errors, "ragdoll.minTime", rg.minTime, 0)
		checkNumber(errors, "ragdoll.maxTime", rg.maxTime, 0, nil, true)
	end
	local a = group("anticheat")
	if a then
		checkBool(errors, "anticheat.enabled", a.enabled)
		checkNumber(errors, "anticheat.speedTolerance", a.speedTolerance, 1)
		checkNumber(errors, "anticheat.horizontalSlack", a.horizontalSlack, 0)
		checkNumber(errors, "anticheat.teleportDistance", a.teleportDistance, 0, nil, true)
		checkNumber(errors, "anticheat.verticalTolerance", a.verticalTolerance, 1)
		checkNumber(errors, "anticheat.verticalSlack", a.verticalSlack, 0)
		checkNumber(errors, "anticheat.spawnGrace", a.spawnGrace, 0)
	end

	if checkTable(errors, "weapons", config.weapons) then
		local def = config.weapons[config.defaultWeapon]
		if not def then
			table.insert(errors, ("defaultWeapon '%s' is not in weapons"):format(tostring(config.defaultWeapon)))
		elseif #Validator.validateWeapon(config.defaultWeapon, def, config) > 0 then
			table.insert(errors, ("defaultWeapon '%s' is invalid (see the weapon warning)"):format(config.defaultWeapon))
		end
	end
	checkTable(errors, "npcs", config.npcs)
	return errors
end

return Validator
