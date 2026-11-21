--!nonstrict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local CombatShared = require(ReplicatedStorage:WaitForChild("CombatShared"))
local ClimbIndicator = require(script.Parent.ClimbIndicator)

local WALL_GAP = 0.6
local STICK_GAIN = 8
local MANTLE_UP = 35
local MANTLE_FORWARD = 12
local AIR_JUMP_DEBOUNCE = 0.1
local CORNER_DOT = 0.7
local CORNER_PROBE = 0.4
local TURN_TIME = 0.22
local TURN_OUT = 0.5
local TURN_COOLDOWN = 0.05
local MISS_GRACE = 0.2

local flat = CombatShared.flat

local MovementController = {}
MovementController.__index = MovementController

function MovementController.new(ctx)
	local keys = ctx.config.keys
	local self = setmetatable({
		ctx = ctx,
		character = nil,
		humanoid = nil,
		root = nil,
		attachment = nil,
		params = RaycastParams.new(),
		airJumps = 0,
		lastAirJumpAt = -math.huge,
		dashing = nil,
		climbing = nil,
		climbPending = false,
		ragdolled = false,
		ragdollReason = nil,
		charConnections = {},
		indicator = ClimbIndicator.new(ctx.config.hud.indicatorDistance),
		keys = {
			dash = CombatShared.keyCode(keys.dash),
			jump = CombatShared.keyCode(keys.jump),
			climb = CombatShared.keyCode(keys.climb),
		},
	}, MovementController)
	self.params.FilterType = Enum.RaycastFilterType.Exclude

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not self.root then
			return
		end
		local key = input.KeyCode
		if key == self.keys.dash then
			self:dash()
		elseif key == self.keys.jump then
			self:jump()
		elseif key == self.keys.climb then
			self:toggleClimb()
		end
	end)
	RunService.PreSimulation:Connect(function()
		self:step()
	end)
	return self
end

function MovementController:_clearCharacter()
	for _, c in ipairs(self.charConnections) do
		c:Disconnect()
	end
	table.clear(self.charConnections)
	self:_stopDash()
	if self.climbing then
		self:_endClimb("respawn")
	end
	self.indicator:hide()
	self.character, self.humanoid, self.root, self.attachment = nil, nil, nil, nil
	self.airJumps = 0
	self.climbPending = false
	self.ragdolled = false
	self.ragdollReason = nil
end

function MovementController:bind(character: Model)
	self:_clearCharacter()
	local humanoid = character:WaitForChild("Humanoid", 10)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not humanoid or not root or character.Parent == nil then
		return
	end
	self.character = character
	self.humanoid = humanoid
	self.root = root
	self.params.FilterDescendantsInstances = { character }
	local attachment = CombatShared.template("Physics", "CombatMovement")
	if attachment then
		attachment.Parent = root
	end
	self.attachment = attachment
	table.insert(self.charConnections, humanoid.StateChanged:Connect(function(_, new)
		if (new == Enum.HumanoidStateType.Landed or new == Enum.HumanoidStateType.Running) and not self.climbing then
			self.airJumps = 0
		end
	end))
	table.insert(self.charConnections, humanoid.Died:Connect(function()
		self:_clearCharacter()
	end))
end

function MovementController:_alive(): boolean
	return self.humanoid ~= nil and self.humanoid.Health > 0 and self.root ~= nil and self.root.Parent ~= nil
end

function MovementController:_stopDash()
	if self.dashing then
		self.dashing.constraint:Destroy()
		self.dashing = nil
	end
end

function MovementController:dash()
	local ctx = self.ctx
	if not self:_alive() or self.climbing or self.ragdolled or self.dashing or ctx.combatState() ~= "Idle" then
		return
	end
	if ctx.cooldownRemaining("Dash") > 0 then
		return
	end
	local cfg = ctx.config.dash
	local distance = ctx.resolve(cfg.distance)
	local duration = ctx.resolve(cfg.duration)
	local dir = flat(self.humanoid.MoveDirection)
	if dir.Magnitude < 0.1 then
		dir = flat(self.root.CFrame.LookVector)
	end
	if dir.Magnitude < 1e-3 then
		return
	end
	dir = dir.Unit
	ctx.send("Dash")
	local dashCooldown = ctx.resolve(cfg.cooldown)
	ctx.setCooldown("Dash", ctx.now() + dashCooldown, dashCooldown)

	local constraint = self:_planeVelocity("CombatDash", dir * (distance / duration))
	if constraint then
		self.dashing = { constraint = constraint, untilTime = os.clock() + duration, brake = true }
	end
end

function MovementController:_planeVelocity(name: string, velocity: Vector3)
	if not self.attachment then
		return nil
	end
	local constraint = CombatShared.template("Physics", "PlaneVelocity")
	if not constraint then
		return nil
	end
	constraint.Name = name
	constraint.Attachment0 = self.attachment
	constraint.PlaneVelocity = Vector2.new(velocity.X, velocity.Z)
	constraint.Parent = self.root
	return constraint
end

function MovementController:_maxAirJumps(): number
	if self.ctx.hasUnlock("skyJump") then
		return math.huge
	end
	return 1
end

function MovementController:jump()
	if self.climbing then
		self:_climbJump()
		return
	end
	local ctx = self.ctx
	if not self:_alive() then
		return
	end
	local state = ctx.combatState()
	local fallRagdoll = self.ragdolled and self.ragdollReason == "fall"
	if not fallRagdoll and self.humanoid.FloorMaterial ~= Enum.Material.Air then
		return
	end
	if state ~= "Idle" and state ~= "Dashing" and not fallRagdoll then
		return
	end
	local cfg = ctx.config.jump
	if os.clock() - self.lastAirJumpAt < AIR_JUMP_DEBOUNCE or self.airJumps >= self:_maxAirJumps() then
		return
	end
	if self.airJumps >= 1 and ctx.cooldownRemaining("SkyJump") > 0 then
		return
	end
	self.airJumps += 1
	self.lastAirJumpAt = os.clock()
	local isSky = self.airJumps >= 2
	ctx.send("AirJump")
	if isSky then
		local skyCooldown = ctx.resolve(cfg.skyJump.cooldown)
		ctx.setCooldown("SkyJump", ctx.now() + skyCooldown, skyCooldown)
	end
	if self.ragdolled then
		self:_setRagdoll(false)
	end
	local power = if isSky then ctx.resolve(cfg.skyJump.power) else ctx.resolve(cfg.doubleJumpPower)
	local v = self.root.AssemblyLinearVelocity
	local horizontal = Vector3.new(v.X, 0, v.Z)
	if isSky then
		local dir = flat(self.humanoid.MoveDirection)
		horizontal = if dir.Magnitude > 0.1 then dir.Unit * ctx.resolve(cfg.skyJump.horizontalSpeed) else Vector3.zero
	end
	self.root.AssemblyLinearVelocity = Vector3.new(horizontal.X, power, horizontal.Z)
	self.humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	ctx.effects.play(if isSky then "skyJump" else "doubleJump", self.character)
end

function MovementController:_wallHit(direction: Vector3, origin: Vector3?)
	local reach = self.ctx.config.climb.reach + 1
	local hit = Workspace:Raycast(origin or self.root.Position, direction.Unit * reach, self.params)
	if hit and math.abs(hit.Normal.Y) <= 0.5 then
		return hit
	end
	return nil
end

function MovementController:toggleClimb()
	local ctx = self.ctx
	if self.climbing then
		ctx.send("Climb", false)
		self:_endClimb("released")
		return
	end
	if not self:_alive() or self.climbPending or self.ragdolled or ctx.combatState() ~= "Idle" or ctx.cooldownRemaining("Climb") > 0 then
		return
	end
	local look = flat(self.root.CFrame.LookVector)
	if look.Magnitude < 1e-3 or not self:_wallHit(look) then
		return
	end
	self.climbPending = true
	ctx.send("Climb", true)
	task.delay(2, function()
		self.climbPending = false
	end)
end

function MovementController:_startClimb(normal: Vector3, endsAt: number, duration: number)
	if not self:_alive() then
		return
	end
	local velocity = self.attachment and CombatShared.template("Physics", "VectorVelocity")
	local orientation = self.attachment and CombatShared.template("Physics", "ClimbOrientation")
	if not velocity or not orientation then
		if velocity then
			velocity:Destroy()
		end
		if orientation then
			orientation:Destroy()
		end
		self.ctx.send("Climb", false)
		return
	end
	self:_stopDash()
	local hum = self.humanoid
	hum.AutoRotate = false
	hum.PlatformStand = true

	velocity.Name = "CombatClimb"
	velocity.Attachment0 = self.attachment
	velocity.VectorVelocity = Vector3.zero
	velocity.Parent = self.root

	orientation.Name = "CombatClimb"
	orientation.Attachment0 = self.attachment
	orientation.CFrame = CFrame.lookAt(Vector3.zero, -flat(normal).Unit)
	orientation.Parent = self.root

	self.climbing = { normal = normal, endsAt = endsAt, duration = duration, velocity = velocity, orientation = orientation }
	self.airJumps = 0
	self.indicator:show(self.root)
	self.ctx.animator.startClimb(self.character)
end

function MovementController:_endClimb(reason: string)
	local climb = self.climbing
	if not climb then
		return
	end
	self.climbing = nil
	climb.velocity:Destroy()
	climb.orientation:Destroy()
	self.indicator:hide()
	if self.character then
		self.ctx.animator.stopClimb(self.character)
	end
	self.airJumps = 0
	local climbCooldown = self.ctx.config.climb.cooldown
	self.ctx.setCooldown("Climb", self.ctx.now() + climbCooldown, climbCooldown)
	local hum = self.humanoid
	if hum and hum.Parent then
		hum.PlatformStand = false
		hum.AutoRotate = true
		if reason ~= "respawn" and hum.Health > 0 then
			hum:ChangeState(Enum.HumanoidStateType.Freefall)
		end
	end
	return climb
end

function MovementController:_climbJump()
	local ctx = self.ctx
	local climb = self:_endClimb("jump")
	if not climb then
		return
	end
	ctx.send("ClimbJump")
	local cfg = ctx.config.climb
	local away = flat(climb.normal)
	away = if away.Magnitude > 1e-3 then away.Unit else Vector3.zero
	self.root.AssemblyLinearVelocity = away * ctx.resolve(cfg.jumpAwaySpeed) + Vector3.yAxis * ctx.resolve(cfg.jumpPower)
end

function MovementController:_cornerHit(climb, side: number, onWall: boolean)
	local root = self.root
	local normal = flat(climb.normal)
	if normal.Magnitude < 1e-3 then
		return nil, false
	end
	normal = normal.Unit
	local facing = -normal
	local right = facing:Cross(Vector3.yAxis) * side
	local function valid(hit)
		return hit ~= nil and math.abs(hit.Normal.Y) <= 0.5 and flat(hit.Normal).Unit:Dot(normal) < CORNER_DOT
	end
	if onWall then
		local inner = Workspace:Raycast(root.Position, right * (root.Size.X / 2 + WALL_GAP + CORNER_PROBE), self.params)
		return if valid(inner) then inner else nil, false
	end
	local origin = root.Position + facing * (root.Size.Z / 2 + WALL_GAP + CORNER_PROBE)
	local outer = Workspace:Raycast(origin, -right * (self.ctx.config.climb.reach + 1), self.params)
	return if valid(outer) then outer else nil, true
end

local function easeTurn(a: number): number
	return 1 - (1 - a) * (1 - a)
end

function MovementController:_beginTurn(climb, hit, outer: boolean)
	local root = self.root
	local normal = flat(hit.Normal).Unit
	local desired = root.Size.Z / 2 + WALL_GAP
	local position
	if outer then
		position = Vector3.new(hit.Position.X, root.Position.Y, hit.Position.Z) + normal * desired
	else
		position = root.Position - normal * ((root.Position - hit.Position):Dot(normal) - desired)
	end
	climb.turn = {
		from = root.CFrame,
		to = CFrame.lookAt(position, position - normal),
		start = os.clock(),
	}
	climb.normal = hit.Normal
	climb.missSince = nil
end

function MovementController:_stepTurn(climb): boolean
	local turn = climb.turn
	local alpha = math.clamp((os.clock() - turn.start) / TURN_TIME, 0, 1)
	local eased = easeTurn(alpha)
	local frame = turn.from:Lerp(turn.to, eased)
	local lift = math.sin(alpha * math.pi) * TURN_OUT
	local out = flat(turn.from.LookVector + turn.to.LookVector)
	if lift > 0 and out.Magnitude > 1e-3 then
		frame = frame - out.Unit * lift
	end
	climb.velocity.VectorVelocity = Vector3.zero
	climb.orientation.CFrame = frame.Rotation
	self.root.CFrame = frame
	self.root.AssemblyLinearVelocity = Vector3.zero
	if alpha >= 1 then
		climb.turn = nil
		return false
	end
	return true
end

function MovementController:_stepClimb()
	local climb = self.climbing
	local ctx = self.ctx
	local cfg = ctx.config.climb
	local root = self.root
	self.indicator:update((climb.endsAt - ctx.now()) / climb.duration)
	if climb.turn and self:_stepTurn(climb) then
		return
	end
	local up = (if UserInputService:IsKeyDown(Enum.KeyCode.W) then 1 else 0) - (if UserInputService:IsKeyDown(Enum.KeyCode.S) then 1 else 0)
	local side = (if UserInputService:IsKeyDown(Enum.KeyCode.D) then 1 else 0) - (if UserInputService:IsKeyDown(Enum.KeyCode.A) then 1 else 0)
	if side ~= 0 then
		climb.lastSide = side
	end
	local hit = self:_wallHit(-climb.normal)
	if hit and side ~= 0 and os.clock() >= (climb.turnReadyAt or 0) then
		local inner = self:_cornerHit(climb, side, true)
		if inner then
			self:_beginTurn(climb, inner, false)
			climb.turnReadyAt = os.clock() + TURN_TIME + TURN_COOLDOWN
			return
		end
	end
	if not hit then
		local feet = self:_wallHit(-climb.normal, root.Position - Vector3.new(0, 2.5, 0))
		if feet then
			local facing = -flat(climb.normal).Unit
			ctx.send("Climb", false)
			self:_endClimb("mantle")
			root.AssemblyLinearVelocity = Vector3.yAxis * MANTLE_UP + facing * MANTLE_FORWARD
			return
		end
		local first = if side ~= 0 then side else (climb.lastSide or 1)
		for _, probe in ipairs({ first, -first }) do
			local outer = self:_cornerHit(climb, probe, false)
			if outer then
				self:_beginTurn(climb, outer, true)
				climb.turnReadyAt = os.clock() + TURN_TIME + TURN_COOLDOWN
				return
			end
		end
		local now = os.clock()
		climb.missSince = climb.missSince or now
		if now - climb.missSince < MISS_GRACE then
			climb.velocity.VectorVelocity = Vector3.yAxis * up * ctx.resolve(cfg.speed) * 0.5
			return
		end
		ctx.send("Climb", false)
		self:_endClimb("wall")
		return
	end
	climb.missSince = nil
	climb.normal = hit.Normal
	local facing = -flat(hit.Normal).Unit
	local right = facing:Cross(Vector3.yAxis)
	local distance = (root.Position - hit.Position):Dot(hit.Normal)
	local desired = root.Size.Z / 2 + WALL_GAP
	local move = Vector3.yAxis * up + right * side
	if move.Magnitude > 1 then
		move = move.Unit
	end
	climb.velocity.VectorVelocity = move * ctx.resolve(cfg.speed) - hit.Normal * (distance - desired) * STICK_GAIN
	climb.orientation.CFrame = CFrame.lookAt(Vector3.zero, facing)
end

function MovementController:_setRagdoll(on: boolean, reason: string?)
	self.ragdolled = on
	self.ragdollReason = if on then reason else nil
	local hum = self.humanoid
	if not hum or hum.Health <= 0 then
		return
	end
	if on then
		self:_stopDash()
		if self.climbing then
			self:_endClimb("ragdoll")
		end
		hum:ChangeState(Enum.HumanoidStateType.Physics)
	else
		hum:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
end

function MovementController:_knockback(velocity: Vector3, duration: number)
	if not self:_alive() then
		return
	end
	self:_stopDash()
	if self.climbing then
		self:_endClimb("hit")
	end
	local constraint = self:_planeVelocity("CombatKnockback", velocity)
	if constraint then
		self.dashing = { constraint = constraint, untilTime = os.clock() + duration }
	end
	if velocity.Y > 0 then
		local v = self.root.AssemblyLinearVelocity
		self.root.AssemblyLinearVelocity = Vector3.new(v.X, velocity.Y, v.Z)
		self.humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	end
end

function MovementController:onServer(kind, ...)
	if kind == "dash" then
		local ok = ...
		if ok == false then
			self:_stopDash()
		end
	elseif kind == "airJump" then
		local ok, count = ...
		if type(count) == "number" then
			self.airJumps = count
		end
		if ok == false and self.ctx.combatState() == "Ragdoll" and not self.ragdolled then
			self:_setRagdoll(true, "fall")
		end
	elseif kind == "climb" then
		local on, a, b, c = ...
		self.climbPending = false
		if on == true and typeof(c) == "Vector3" and type(a) == "number" and type(b) == "number" then
			self:_startClimb(c, a, b)
		elseif on == false and self.climbing and a ~= "jump" and a ~= "released" then
			self:_endClimb(a)
		end
	elseif kind == "ragdoll" then
		local on, reason = ...
		if on == true then
			self:_setRagdoll(true, reason)
		elseif on == false and self.ragdolled then
			self:_setRagdoll(false)
		end
	elseif kind == "knockback" then
		local velocity, duration = ...
		if typeof(velocity) == "Vector3" and type(duration) == "number" then
			self:_knockback(velocity, duration)
		end
	elseif kind == "correction" then
		self:_stopDash()
		if self.climbing then
			self:_endClimb("correction")
		end
	elseif kind == "synced" then
		local _, airJumps = ...
		if type(airJumps) == "number" then
			self.airJumps = airJumps
		end
	end
end

function MovementController:step()
	if not self.root then
		return
	end
	if self.dashing and os.clock() >= self.dashing.untilTime then
		local brake = self.dashing.brake
		self:_stopDash()
		if brake and self:_alive() then
			local v = self.root.AssemblyLinearVelocity
			local horizontal = Vector3.new(v.X, 0, v.Z)
			local limit = self.humanoid.WalkSpeed
			if horizontal.Magnitude > limit then
				horizontal = horizontal.Unit * limit
				self.root.AssemblyLinearVelocity = Vector3.new(horizontal.X, v.Y, horizontal.Z)
			end
		end
	end
	if self.climbing then
		if self:_alive() then
			self:_stepClimb()
		else
			self:_endClimb("respawn")
		end
	end
end

return MovementController
