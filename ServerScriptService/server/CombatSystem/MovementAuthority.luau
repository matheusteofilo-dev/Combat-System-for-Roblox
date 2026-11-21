--!nonstrict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CombatShared = require(ReplicatedStorage:WaitForChild("CombatShared"))
local Ragdoll = require(script.Parent.Ragdoll)

local GROUND_MARGIN = 0.9
local AIR_MARGIN = 1.6
local VIOLATION_LOG_INTERVAL = 5
local AIR_JUMP_DEBOUNCE = 0.1

local MovementAuthority = {}
MovementAuthority.__index = MovementAuthority

local flat = CombatShared.flat

function MovementAuthority.new(api, config)
	local self = setmetatable({
		api = api,
		config = config,
		guards = setmetatable({}, { __mode = "k" }),
		params = setmetatable({}, { __mode = "k" }),
	}, MovementAuthority)

	api.RegisterAction("Run", function(c, on)
		if type(on) == "boolean" then
			c.running = on
		end
	end)

	api.RegisterAction("Dash", function(c)
		self:dash(c)
	end)
	api.RegisterAction("AirJump", function(c)
		self:airJump(c)
	end)
	api.RegisterAction("Climb", function(c, on)
		if on == true then
			self:startClimb(c)
		elseif on == false then
			self:stopClimb(c, "released")
		end
	end)
	api.RegisterAction("ClimbJump", function(c)
		self:stopClimb(c, "jump")
	end)
	return self
end

function MovementAuthority:_params(c)
	local p = self.params[c]
	if not p then
		p = RaycastParams.new()
		p.FilterType = Enum.RaycastFilterType.Exclude
		p.FilterDescendantsInstances = { c.model }
		p.IgnoreWater = false
		self.params[c] = p
	end
	return p
end

function MovementAuthority:_reply(c, ...)
	if c.player then
		self.api.Send(c.player, ...)
	end
end

function MovementAuthority:standHeight(c): number
	local hum = c.humanoid
	local legs = if hum.RigType == Enum.HumanoidRigType.R6 then 2 else hum.HipHeight
	return c.root.Size.Y / 2 + legs
end

function MovementAuthority:heightAboveGround(c, maxDistance: number?): number
	local origin = c.root.Position
	local result = Workspace:Raycast(origin, Vector3.new(0, -(maxDistance or 500), 0), self:_params(c))
	if not result then
		return math.huge
	end
	return origin.Y - result.Position.Y - self:standHeight(c)
end

function MovementAuthority:isGrounded(c): boolean
	return self:heightAboveGround(c, 30) <= GROUND_MARGIN
end

function MovementAuthority:_wallRay(c, direction: Vector3, extra: number)
	local reach = self.config.climb.reach + extra
	local params = self:_params(c)
	local origin = c.root.Position
	return Workspace:Raycast(origin, direction.Unit * reach, params) or Workspace:Raycast(origin + Vector3.new(0, 1.5, 0), direction.Unit * reach, params)
end

function MovementAuthority:_jumpRise(c): number
	local hum = c.humanoid
	local power = if hum.UseJumpPower then (c.baseJumpPower or hum.JumpPower) else nil
	if power then
		return power * power / (2 * Workspace.Gravity)
	end
	return c.baseJumpHeight or hum.JumpHeight
end

function MovementAuthority:_guard(c)
	local g = self.guards[c]
	if not g then
		local pos = c.root.Position
		g = {
			lastPos = pos,
			lastSafe = c.root.CFrame,
			debt = 0,
			ceiling = pos.Y + 50,
			allowances = {},
			graceUntil = self.api.now() + self.config.anticheat.spawnGrace,
			lastLog = -math.huge,
			violations = 0,
		}
		self.guards[c] = g
	end
	return g
end

function MovementAuthority:grant(c, horizontalSpeed: number, rise: number, duration: number)
	local g = self:_guard(c)
	local now = self.api.now()
	local entry = nil
	if horizontalSpeed > 0 then
		entry = { speed = horizontalSpeed, untilTime = now + duration }
		table.insert(g.allowances, entry)
	end
	if rise > 0 then
		local ac = self.config.anticheat
		g.ceiling = math.max(g.ceiling, c.root.Position.Y + rise * ac.verticalTolerance + ac.verticalSlack)
	end
	return entry
end

function MovementAuthority:resetGuard(c, grace: number?)
	local g = self:_guard(c)
	g.lastPos = c.root.Position
	g.lastSafe = c.root.CFrame
	g.debt = 0
	g.ceiling = c.root.Position.Y + 50
	g.graceUntil = math.max(g.graceUntil, self.api.now() + (grace or self.config.anticheat.spawnGrace))
end

function MovementAuthority:_violate(c, g, kind: string, detail: string)
	g.violations += 1
	local now = self.api.now()
	if now - g.lastLog >= VIOLATION_LOG_INTERVAL then
		g.lastLog = now
		warn(("[CombatSystem] movement rejected for %s (%s: %s); total %d"):format(c.model.Name, kind, detail, g.violations))
	end
	if c.state == "Climbing" then
		self:stopClimb(c, "correction")
	elseif c.state == "Dashing" then
		c:setState("Idle")
	end
	c.root.CFrame = g.lastSafe
	c.root.AssemblyLinearVelocity = Vector3.zero
	g.lastPos = g.lastSafe.Position
	g.debt = 0
	g.ceiling = g.lastSafe.Position.Y + self:_jumpRise(c) * self.config.anticheat.verticalTolerance + self.config.anticheat.verticalSlack
	table.clear(g.allowances)
	c.changed:Fire("violation", kind)
	self:_reply(c, "correction", kind)
end

function MovementAuthority:_pendingAirRise(c): number
	local state = c.state
	local fallRagdoll = state == "Ragdoll" and c.ragdollReason == "fall"
	if state ~= "Idle" and state ~= "Dashing" and not fallRagdoll then
		return 0
	end
	if c.airJumps >= self:_maxAirJumps(c, not c.isNPC) then
		return 0
	end
	local cfg = self.config.jump
	local power = if c.airJumps >= 1 then c:resolve(cfg.skyJump.power) else c:resolve(cfg.doubleJumpPower)
	local rising = math.max(0, c.root.AssemblyLinearVelocity.Y)
	return power * power / (2 * Workspace.Gravity) * self.config.anticheat.verticalTolerance + rising * 0.25
end

function MovementAuthority:_checkMovement(c, now: number, dt: number, grounded: boolean)
	local ac = self.config.anticheat
	local g = self:_guard(c)
	local pos = c.root.Position
	if c.humanoid.SeatPart or now < g.graceUntil then
		g.lastPos = pos
		g.lastSafe = c.root.CFrame
		g.ceiling = math.max(g.ceiling, pos.Y + self:_jumpRise(c) * ac.verticalTolerance + ac.verticalSlack)
		return
	end

	local delta = pos - g.lastPos
	if delta.Magnitude > ac.teleportDistance then
		self:_violate(c, g, "teleport", ("%.1f studs in one step"):format(delta.Magnitude))
		return
	end

	local allowed = math.max(c.humanoid.WalkSpeed, c:resolve(self.config.run.walkSpeed))
	for i = #g.allowances, 1, -1 do
		local a = g.allowances[i]
		if now > a.untilTime then
			table.remove(g.allowances, i)
		elseif a.speed > allowed then
			allowed = a.speed
		end
	end
	if c.state == "Climbing" then
		allowed = math.max(allowed, c:resolve(self.config.climb.speed))
	end
	g.debt = math.max(0, g.debt + flat(delta).Magnitude - allowed * ac.speedTolerance * dt)
	if g.debt > ac.horizontalSlack and self:_implicitDash(c) then
		g.debt = math.max(0, g.debt - c:resolve(self.config.dash.distance))
	end
	if g.debt > ac.horizontalSlack then
		self:_violate(c, g, "speed", ("%.1f studs over the allowed path"):format(g.debt))
		return
	end

	if grounded then
		g.ceiling = pos.Y + self:_jumpRise(c) * ac.verticalTolerance + ac.verticalSlack
	elseif c.state == "Climbing" then
		g.ceiling = math.max(g.ceiling, pos.Y + c:resolve(self.config.climb.speed) * 0.5 + ac.verticalSlack)
	end
	local top = g.ceiling
	if not grounded and c.state ~= "Climbing" then
		top += self:_pendingAirRise(c)
	end
	if pos.Y > top then
		self:_violate(c, g, "height", ("%.1f studs above the allowed height"):format(pos.Y - top))
		return
	end

	g.lastPos = pos
	if grounded and g.debt < ac.horizontalSlack * 0.5 then
		g.lastSafe = c.root.CFrame
	end
end

function MovementAuthority:speedFor(c): number
	local cfg = self.config
	local state = c.state
	if state == "Stunned" or state == "Ragdoll" then
		return 0
	end
	if state == "Blocking" then
		return c:resolve(cfg.block.walkSpeed)
	end
	if state == "Attacking" and cfg.run.cancelOnAction then
		return c:resolve(cfg.run.walkSpeed)
	end
	if c.running then
		return c:resolve(cfg.run.speed)
	end
	return c:resolve(cfg.run.walkSpeed)
end

function MovementAuthority:_applyJumpLock(c)
	local hum = c.humanoid
	if c.baseJumpPower == nil then
		c.baseJumpPower = hum.JumpPower
		c.baseJumpHeight = hum.JumpHeight
	end
	local state = c.state
	local locked = state == "Stunned" or state == "Ragdoll" or state == "Climbing" or state == "Attacking" or state == "Blocking"
	local power = if locked then 0 else c.baseJumpPower
	local height = if locked then 0 else c.baseJumpHeight
	if hum.JumpPower ~= power then
		hum.JumpPower = power
	end
	if hum.JumpHeight ~= height then
		hum.JumpHeight = height
	end
end

function MovementAuthority:_implicitDash(c): boolean
	if not c:canAct() or c.state ~= "Idle" or not c:isReady("Dash") then
		return false
	end
	if self:_beginDash(c) then
		c.implicitDashAt = self.api.now()
		return true
	end
	return false
end

function MovementAuthority:_beginDash(c): boolean
	local cfg = self.config.dash
	local distance = c:resolve(cfg.distance)
	local duration = c:resolve(cfg.duration)
	c:setState("Dashing", duration)
	c:startCooldown("Dash", c:resolve(cfg.cooldown))
	if cfg.iFrames then
		c.invulnerableUntil = self.api.now() + duration
	end
	self:grant(c, distance / duration, 0, duration + 0.4)
	return true
end

function MovementAuthority:dash(c)
	local cfg = self.config.dash
	if c.implicitDashAt and self.api.now() - c.implicitDashAt < 0.6 then
		c.implicitDashAt = nil
		self:_reply(c, "dash", true, c:resolve(cfg.duration), c:resolve(cfg.distance))
		return true
	end
	if not c:canAct() or c.state ~= "Idle" or not c:isReady("Dash") then
		self:_reply(c, "dash", false)
		return false
	end
	self:_beginDash(c)
	self:_reply(c, "dash", true, c:resolve(cfg.duration), c:resolve(cfg.distance))
	return true
end

function MovementAuthority:_maxAirJumps(c, canSky: boolean): number
	if canSky and c:hasUnlock("skyJump") then
		return math.huge
	end
	return 1
end

function MovementAuthority:airJump(c, direction: Vector3?)
	local cfg = self.config.jump
	local now = self.api.now()
	local fallRagdoll = c.state == "Ragdoll" and c.ragdollReason == "fall"
	local deny = not c:isAlive() or (c.state ~= "Idle" and c.state ~= "Dashing" and not fallRagdoll)
	if not deny and self:heightAboveGround(c, 30) <= AIR_MARGIN then
		deny = true
	end
	if not deny and now - (c.lastAirJumpAt or -math.huge) < AIR_JUMP_DEBOUNCE then
		deny = true
	end
	if not deny and c.airJumps >= 1 and not c:isReady("SkyJump") then
		deny = true
	end
	if not deny and c.airJumps >= self:_maxAirJumps(c, not c.isNPC) then
		deny = true
	end
	if deny then
		self:_reply(c, "airJump", false, c.airJumps)
		return false
	end

	c.airJumps += 1
	c.lastAirJumpAt = now
	local isSky = c.airJumps >= 2
	local power = if isSky then c:resolve(cfg.skyJump.power) else c:resolve(cfg.doubleJumpPower)
	local horizontal = if isSky then c:resolve(cfg.skyJump.horizontalSpeed) else 0
	if isSky then
		c:startCooldown("SkyJump", c:resolve(cfg.skyJump.cooldown))
	end
	if fallRagdoll then
		self:endRagdoll(c)
	end
	local airTime = 2 * power / Workspace.Gravity + 0.5
	self:grant(c, horizontal + c.humanoid.WalkSpeed, power * power / (2 * Workspace.Gravity), airTime)
	if c.isNPC then
		local dir = if direction and flat(direction).Magnitude > 1e-3 then flat(direction).Unit else Vector3.zero
		local v = c.root.AssemblyLinearVelocity
		local h = if isSky then dir * horizontal else Vector3.new(v.X, 0, v.Z)
		c.root.AssemblyLinearVelocity = Vector3.new(h.X, power, h.Z)
	end
	self:_reply(c, "airJump", true, c.airJumps, isSky)
	self.api.Broadcast(c.root.Position, "fx", if isSky then "skyJump" else "doubleJump", c.model)
	return true
end

function MovementAuthority:startClimb(c)
	if not c:canAct() or c.state ~= "Idle" or not c:isReady("Climb") then
		self:_reply(c, "climb", false, "denied")
		return false
	end
	local look = flat(c.root.CFrame.LookVector)
	local hit = look.Magnitude > 1e-3 and self:_wallRay(c, look, 1.5)
	if not hit or math.abs(hit.Normal.Y) > 0.5 then
		self:_reply(c, "climb", false, "no wall")
		return false
	end
	local now = self.api.now()
	local duration = c:resolve(self.config.climb.time)
	c.climb = { normal = hit.Normal, startedAt = now, endsAt = now + duration, nextCheck = now, misses = 0 }
	c.airJumps = 0
	c:setState("Climbing")
	self:_reply(c, "climb", true, c.climb.endsAt, duration, hit.Normal)
	return true
end

function MovementAuthority:stopClimb(c, reason: string)
	if c.state ~= "Climbing" then
		return
	end
	local cfg = self.config.climb
	c.climb = nil
	c:setState("Idle")
	c:startCooldown("Climb", cfg.cooldown)
	c.airJumps = 0
	if reason == "jump" then
		local power = c:resolve(cfg.jumpPower)
		self:grant(c, c:resolve(cfg.jumpAwaySpeed) + c.humanoid.WalkSpeed, power * power / (2 * Workspace.Gravity), 2 * power / Workspace.Gravity + 0.5)
	else
		self:grant(c, c:resolve(cfg.speed), 4, 0.6)
	end
	self:_reply(c, "climb", false, reason)
	if reason == "stamina" or reason == "wall" then
		if self:heightAboveGround(c) > cfg.ragdollFallHeight then
			self:startRagdoll(c, "fall")
		end
	end
end

function MovementAuthority:startRagdoll(c, reason: string)
	if not c:isAlive() then
		return
	end
	c.ragdollReason = reason
	c.ragdollSince = self.api.now()
	c:setState("Ragdoll")
	c.ragdollAllowance = self:grant(c, 25, 0, self.config.ragdoll.maxTime)
	Ragdoll.enable(c.model, c.humanoid, c.isNPC)
	self:_reply(c, "ragdoll", true, reason)
end

function MovementAuthority:endRagdoll(c)
	if c.state ~= "Ragdoll" then
		return
	end
	Ragdoll.disable(c.model, c.humanoid, c.isNPC)
	if c.ragdollAllowance then
		c.ragdollAllowance.untilTime = 0
		c.ragdollAllowance = nil
	end
	c.ragdollReason = nil
	c.ragdollSince = nil
	c:setState("Idle")
	self:_reply(c, "ragdoll", false)
end

function MovementAuthority:_updateClimb(c, now: number)
	local climb = c.climb
	if not climb then
		c:setState("Idle")
		return
	end
	if now >= climb.endsAt then
		self:stopClimb(c, "stamina")
		return
	end
	if now < climb.nextCheck then
		return
	end
	climb.nextCheck = now + self.config.climb.wallCheckInterval
	local function wall(direction: Vector3)
		if direction.Magnitude < 1e-3 then
			return nil
		end
		local result = self:_wallRay(c, direction, 2)
		return if result and math.abs(result.Normal.Y) <= 0.5 then result else nil
	end
	local inward = -flat(climb.normal)
	local side = inward:Cross(Vector3.yAxis)
	local hit = wall(inward) or wall(flat(c.root.CFrame.LookVector)) or wall(side) or wall(-side)
	if hit then
		climb.normal = hit.Normal
		climb.misses = 0
	else
		climb.misses += 1
		if climb.misses >= self.config.climb.wallMisses then
			self:stopClimb(c, "wall")
		end
	end
end

function MovementAuthority:update(c, now: number, dt: number)
	if not c:isAlive() then
		return
	end
	local grounded = self:isGrounded(c)
	if grounded and c.state ~= "Climbing" then
		c.airJumps = 0
	end
	if c.state == "Climbing" then
		self:_updateClimb(c, now)
	elseif c.state == "Ragdoll" then
		local since = c.ragdollSince or now
		local cfg = self.config.ragdoll
		if (grounded and now - since >= cfg.minTime and c.root.AssemblyLinearVelocity.Magnitude < 6) or now - since >= cfg.maxTime then
			self:endRagdoll(c)
		end
	end
	self:_applyJumpLock(c)
	if c.player then
		if grounded or c.state == "Stunned" or c.state == "Ragdoll" then
			local target = self:speedFor(c)
			if c.humanoid.WalkSpeed ~= target then
				c.humanoid.WalkSpeed = target
			end
		end
		if self.config.anticheat.enabled then
			self:_checkMovement(c, now, dt, grounded)
		end
	end
end

function MovementAuthority:forget(c)
	if c.state == "Ragdoll" and c.model.Parent then
		Ragdoll.disable(c.model, c.humanoid, c.isNPC)
	end
	self.guards[c] = nil
	self.params[c] = nil
end

return MovementAuthority
