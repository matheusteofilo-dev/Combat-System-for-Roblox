--!nonstrict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local CombatShared = require(ReplicatedStorage:WaitForChild("CombatShared"))

local Workspace = game:GetService("Workspace")

local FACE_TIME = 0.45
local AIM_RANGE = 1000
local RESEND_INTERVAL = 0.12
local BLOCK_RETRY_INTERVAL = 0.25

local CombatInput = {}
CombatInput.__index = CombatInput

function CombatInput.new(ctx)
	local self = setmetatable({
		ctx = ctx,
		attackHeld = false,
		blockHeld = false,
		blockSent = false,
		lastM1Sent = -math.huge,
		lastBlockSent = -math.huge,
		blockKey = CombatShared.keyCode(ctx.config.keys.block),
		lastForwardTap = -math.huge,
		running = false,
		faceUntil = 0,
		faceYaw = 0,
		facing = false,
	}, CombatInput)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			self.attackHeld = true
			self:_tryM1()
		elseif input.KeyCode == self.blockKey then
			self.blockHeld = true
			self:_tryBlock()
		elseif input.KeyCode == Enum.KeyCode.W then
			local now = os.clock()
			if now - self.lastForwardTap <= ctx.config.run.doubleTapWindow and not self.running then
				self.running = true
				ctx.send("Run", true)
			end
			self.lastForwardTap = now
		elseif input.KeyCode ~= Enum.KeyCode.Unknown then
			self:_tryAbility(input.KeyCode)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			self.attackHeld = false
		elseif input.KeyCode == Enum.KeyCode.W then
			if self.running then
				self.running = false
				ctx.send("Run", false)
			end
		elseif input.KeyCode == self.blockKey then
			self.blockHeld = false
			if self.blockSent then
				self.blockSent = false
				ctx.send("Block", false)
			end
		end
	end)
	RunService.Heartbeat:Connect(function()
		self:_step()
	end)
	return self
end

function CombatInput:_aim(): (number, number)
	local ctx = self.ctx
	local character = ctx.player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local camera = Workspace.CurrentCamera
	if not root or not camera then
		return 0, 0
	end
	local mouse = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local result = Workspace:Raycast(ray.Origin, ray.Direction * AIM_RANGE, params)
	local origin = root.Position
	local target = if result then result.Position else ray.Origin + ray.Direction * AIM_RANGE
	if result then
		local model = result.Instance:FindFirstAncestorOfClass("Model")
		local targetRoot = model and model:FindFirstChild("HumanoidRootPart")
		if targetRoot and model:FindFirstChildOfClass("Humanoid") then
			target = targetRoot.Position
		end
	end
	local direction = target - origin
	if direction.Magnitude < 2 then
		direction = ray.Direction
	end
	local yaw, pitch = CombatShared.aimAngles(direction)
	if CombatShared.flat(direction).Magnitude < 0.05 then
		yaw = CombatShared.aimAngles(CombatShared.flat(root.CFrame.LookVector))
	end
	return yaw, pitch
end

function CombatInput:_face(yaw: number)
	self.faceYaw = yaw
	self.faceUntil = os.clock() + FACE_TIME
end

function CombatInput:_applyFacing()
	local character = self.ctx.player.Character
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not hum or not root then
		return
	end
	local state = self.ctx.combatState()
	if os.clock() < self.faceUntil and (state == "Attacking" or state == "Idle") then
		if not self.facing then
			self.facing = true
			self.restoreAutoRotate = hum.AutoRotate
		end
		hum.AutoRotate = false
		root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, self.faceYaw, 0)
	elseif self.facing then
		self.facing = false
		hum.AutoRotate = self.restoreAutoRotate ~= false and self.ctx.combatState() ~= "Climbing"
	end
end

function CombatInput:_ready(): boolean
	local ctx = self.ctx
	local character = ctx.player.Character
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0 and ctx.combatState() == "Idle"
end

function CombatInput:_tryM1()
	local ctx = self.ctx
	if not self:_ready() or ctx.cooldownRemaining("M1") > 0 or os.clock() - self.lastM1Sent < RESEND_INTERVAL then
		return
	end
	self.lastM1Sent = os.clock()
	ctx.send("M1")
end

function CombatInput:_tryBlock()
	if not self:_ready() or os.clock() - self.lastBlockSent < BLOCK_RETRY_INTERVAL then
		return
	end
	self.lastBlockSent = os.clock()
	self.blockSent = true
	self.ctx.send("Block", true)
end

function CombatInput:_tryAbility(keyCode: Enum.KeyCode)
	local ctx = self.ctx
	local weaponName, weapon = ctx.currentWeapon()
	if not weapon then
		return
	end
	for _, ability in ipairs(weapon.abilities) do
		if CombatShared.keyCode(ability.key) == keyCode then
			if self:_ready() and ctx.cooldownRemaining(weaponName .. "." .. ability.id) <= 0 then
				if ability.kind == "projectile" then
					local yaw, pitch = self:_aim()
					self:_face(yaw)
					ctx.send("Ability", ability.id, yaw, pitch)
				else
					ctx.send("Ability", ability.id)
				end
			end
			return
		end
	end
end

function CombatInput:_step()
	self:_applyFacing()
	if self.attackHeld then
		self:_tryM1()
	end
	if self.blockHeld and self.ctx.combatState() == "Idle" then
		self:_tryBlock()
	end
end

return CombatInput
