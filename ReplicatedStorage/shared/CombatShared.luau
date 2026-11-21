--!nonstrict

local CombatShared = {}

CombatShared.STATES = { "Idle", "Attacking", "Blocking", "Stunned", "Dashing", "Climbing", "Ragdoll" }
CombatShared.ACTOR_TAG = "CombatActor"
CombatShared.RESERVED_ACTIONS = { M1 = true, Block = true, Dash = true, SkyJump = true, Climb = true }

function CombatShared.isFinite(n: any): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

function CombatShared.resolve(value: any, stats: { [string]: number }): any
	if type(value) == "function" then
		return value(stats)
	end
	return value
end

function CombatShared.flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

function CombatShared.isInFront(defenderCFrame: CFrame, attackerPosition: Vector3, arcDegrees: number): boolean
	local toAttacker = CombatShared.flat(attackerPosition - defenderCFrame.Position)
	if toAttacker.Magnitude < 1e-3 then
		return true
	end
	local look = CombatShared.flat(defenderCFrame.LookVector)
	if look.Magnitude < 1e-3 then
		return true
	end
	return look.Unit:Dot(toAttacker.Unit) >= math.cos(math.rad(arcDegrees / 2))
end

function CombatShared.newSignal()
	local handlers = {}
	local signal = {}
	function signal:Connect(fn)
		local key = {}
		handlers[key] = fn
		return {
			Disconnect = function()
				handlers[key] = nil
			end,
		}
	end
	function signal:Fire(...)
		for _, fn in pairs(table.clone(handlers)) do
			task.spawn(fn, ...)
		end
	end
	return signal
end

local warnedTemplates = {}

function CombatShared.template(group: string, name: string): Instance?
	local root = game:GetService("ReplicatedStorage"):FindFirstChild("CombatTemplates")
	local folder = root and root:FindFirstChild(group)
	local template = folder and folder:FindFirstChild(name)
	if not template then
		local key = group .. "/" .. name
		if not warnedTemplates[key] then
			warnedTemplates[key] = true
			warn(("[CombatSystem] template CombatTemplates/%s not found in ReplicatedStorage; the feature that uses it is disabled."):format(key))
		end
		return nil
	end
	return template:Clone()
end

local MIRROR_JOINTS = {
	rightArm = "leftArm",
	leftArm = "rightArm",
	rightLeg = "leftLeg",
	leftLeg = "rightLeg",
}

function CombatShared.mirror(animation)
	local keyframes = {}
	for i, frame in ipairs(animation.keyframes) do
		local pose = {}
		for joint, angles in pairs(frame.pose) do
			pose[MIRROR_JOINTS[joint] or joint] = { angles[1], -angles[2], -angles[3] }
		end
		keyframes[i] = { t = frame.t, pose = pose }
	end
	return { duration = animation.duration, keyframes = keyframes }
end

function CombatShared.aimDirection(yaw: number, pitch: number): Vector3
	return CFrame.fromEulerAnglesYXZ(pitch, yaw, 0).LookVector
end

function CombatShared.aimAngles(direction: Vector3): (number, number)
	local unit = direction.Unit
	return math.atan2(-unit.X, -unit.Z), math.asin(math.clamp(unit.Y, -1, 1))
end

function CombatShared.keyCode(name: string): Enum.KeyCode?
	if type(name) ~= "string" then
		return nil
	end
	local ok, code = pcall(function()
		return Enum.KeyCode[name]
	end)
	if ok then
		return code
	end
	return nil
end

return CombatShared
