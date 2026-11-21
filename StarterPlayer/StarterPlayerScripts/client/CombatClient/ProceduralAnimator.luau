--!nonstrict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CombatShared = require(ReplicatedStorage:WaitForChild("CombatShared"))

local JOINTS = {
	[Enum.HumanoidRigType.R6] = {
		torso = { "HumanoidRootPart", "RootJoint" },
		head = { "Torso", "Neck" },
		rightArm = { "Torso", "Right Shoulder" },
		leftArm = { "Torso", "Left Shoulder" },
		rightLeg = { "Torso", "Right Hip" },
		leftLeg = { "Torso", "Left Hip" },
	},
	[Enum.HumanoidRigType.R15] = {
		torso = { "UpperTorso", "Waist" },
		head = { "Head", "Neck" },
		rightArm = { "RightUpperArm", "RightShoulder" },
		leftArm = { "LeftUpperArm", "LeftShoulder" },
		rightLeg = { "RightUpperLeg", "RightHip" },
		leftLeg = { "LeftUpperLeg", "LeftHip" },
	},
}

local ZERO = { 0, 0, 0 }
local CLIMB_MIN_SPEED = 1
local CLIMB_CYCLE_RATE = 1.4
local CLIMB_BLEND = 0.12
local GUARD_BLEND = 0.08
local GUARD_POSE = {
	rightArm = { 128, 0, -34 },
	leftArm = { 88, 0, 62 },
}

local ProceduralAnimator = {}

local playing = {}
local motorState = setmetatable({}, { __mode = "k" })
local loadedTracks = setmetatable({}, { __mode = "k" })
local connection = nil

local function findMotors(model: Model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end
	local map = JOINTS[humanoid.RigType]
	if not map then
		return nil
	end
	local motors = {}
	for joint, path in pairs(map) do
		local part = model:FindFirstChild(path[1])
		local motor = part and part:FindFirstChild(path[2])
		if motor and (motor:IsA("Motor6D") or motor:IsA("AnimationConstraint")) then
			motors[joint] = motor
		end
	end
	return motors
end

local function ease(a: number): number
	if a < 0.5 then
		return 2 * a * a
	end
	return 1 - (-2 * a + 2) ^ 2 / 2
end

local function sample(keyframes, t: number)
	local count = #keyframes
	if t <= keyframes[1].t then
		return keyframes[1].pose, keyframes[1].pose, 0
	end
	for i = 1, count - 1 do
		local a, b = keyframes[i], keyframes[i + 1]
		if t >= a.t and t <= b.t then
			local span = b.t - a.t
			local alpha = if span > 0 then (t - a.t) / span else 1
			return a.pose, b.pose, ease(alpha)
		end
	end
	local last = keyframes[count].pose
	return last, last, 0
end

local function blendAngles(a, b, alpha: number)
	a = a or ZERO
	b = b or ZERO
	return math.rad(a[1] + (b[1] - a[1]) * alpha), math.rad(a[2] + (b[2] - a[2]) * alpha), math.rad(a[3] + (b[3] - a[3]) * alpha)
end

local function same(a: CFrame, b: CFrame): boolean
	return (a.Position - b.Position).Magnitude < 1e-3 and a.RightVector:Dot(b.RightVector) > 0.99999 and a.UpVector:Dot(b.UpVector) > 0.99999
end

local function restore(motor: Motor6D)
	local st = motorState[motor]
	if st and same(motor.Transform, st.applied) then
		motor.Transform = st.base
	end
	motorState[motor] = nil
end

local function jointRotation(motor): CFrame
	if motor:IsA("Motor6D") then
		return motor.C0.Rotation
	end
	local a0 = motor.Attachment0
	return if a0 then a0.CFrame.Rotation else CFrame.identity
end

local function apply(motor, x: number, y: number, z: number, absolute: boolean?)
	local st = motorState[motor]
	local base = motor.Transform
	if st and same(base, st.applied) then
		base = st.base
	end
	if absolute then
		base = CFrame.identity
	end
	local rot = jointRotation(motor)
	local offset = rot:Inverse() * CFrame.fromEulerAnglesYXZ(x, y, z) * rot
	local applied = offset * base
	motor.Transform = applied
	motorState[motor] = { base = base, applied = applied }
end

local function finish(model: Model)
	local track = playing[model]
	if not track then
		return
	end
	playing[model] = nil
	for _, motor in pairs(track.motors) do
		restore(motor)
	end
end

local function climbPose(track, dt: number, root: BasePart)
	local v = root.AssemblyLinearVelocity
	local lateral = Vector3.new(v.X, 0, v.Z).Magnitude
	if lateral < CLIMB_MIN_SPEED then
		lateral = 0
	end
	local vertical = if math.abs(v.Y) < CLIMB_MIN_SPEED then 0 else v.Y
	track.phase += (vertical + lateral) * dt * CLIMB_CYCLE_RATE
	local s = math.sin(track.phase)
	return {
		rightArm = { 158 + 24 * s, 0, 14 },
		leftArm = { 158 - 24 * s, 0, -14 },
		rightLeg = { 32 - 24 * s, 0, 8 },
		leftLeg = { 32 + 24 * s, 0, -8 },
		torso = { -4, 5 * s, 0 },
		head = { -18, 0, 0 },
	}
end

local function stepHeld(model: Model, track, now: number)
	local root = model:FindFirstChild("HumanoidRootPart")
	if not root then
		finish(model)
		return
	end
	local dt = math.min(now - track.last, 0.1)
	track.last = now
	local target = if track.stopping then 0 else 1
	track.weight = math.clamp(track.weight + (target - track.weight) * math.min(1, dt / (if track.guard then GUARD_BLEND else CLIMB_BLEND)), 0, 1)
	if track.stopping and track.weight < 0.02 then
		finish(model)
		return
	end
	local pose = if track.guard then GUARD_POSE else climbPose(track, dt, root)
	for joint, motor in pairs(track.motors) do
		local angles = pose[joint]
		if angles then
			local x, y, z = blendAngles(ZERO, angles, track.weight)
			apply(motor, x, y, z, true)
		else
			restore(motor)
		end
	end
end

local function step()
	local now = os.clock()
	for model, track in pairs(playing) do
		if track.climb or track.guard then
			if not model.Parent then
				finish(model)
			else
				stepHeld(model, track, now)
			end
			continue
		end
		local elapsed = (now - track.start) * track.speed
		if not model.Parent or elapsed >= track.animation.duration then
			finish(model)
			continue
		end
		local from, to, alpha = sample(track.animation.keyframes, elapsed)
		for joint, motor in pairs(track.motors) do
			if from[joint] or to[joint] then
				apply(motor, blendAngles(from[joint], to[joint], alpha))
			else
				restore(motor)
			end
		end
	end
end

local function playAsset(model: Model, id: string, speed: number): boolean
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return false
	end
	local cache = loadedTracks[animator]
	if not cache then
		cache = {}
		loadedTracks[animator] = cache
	end
	local track = cache[id]
	if not track then
		local animation = CombatShared.template("Physics", "Animation")
		if not animation then
			return false
		end
		animation.AnimationId = id
		local ok, result = pcall(animator.LoadAnimation, animator, animation)
		if not ok then
			warn(("[CombatSystem] could not load animation %s: %s"):format(id, tostring(result)))
			return false
		end
		track = result
		cache[id] = track
	end
	track:Play(0.05, 1, speed)
	return true
end

function ProceduralAnimator.play(model: Model, animation, speed: number?)
	if type(animation) ~= "table" then
		return
	end
	speed = speed or 1
	if type(animation.id) == "string" and animation.id ~= "" and playAsset(model, animation.id, speed) then
		return
	end
	if type(animation.keyframes) ~= "table" or #animation.keyframes == 0 or type(animation.duration) ~= "number" then
		return
	end
	local current = playing[model]
	if current and current.climb then
		return
	end
	finish(model)
	local motors = findMotors(model)
	if not motors then
		return
	end
	playing[model] = { animation = animation, start = os.clock(), speed = speed, motors = motors }
	if not connection then
		connection = RunService.PreSimulation:Connect(step)
	end
end

function ProceduralAnimator.startClimb(model: Model)
	local current = playing[model]
	if current and current.climb then
		current.stopping = false
		return
	end
	local motors = findMotors(model)
	if not motors then
		return
	end
	finish(model)
	playing[model] = { climb = true, motors = motors, phase = 0, weight = 0, last = os.clock(), stopping = false }
	if not connection then
		connection = RunService.PreSimulation:Connect(step)
	end
end

function ProceduralAnimator.stopClimb(model: Model)
	local current = playing[model]
	if current and current.climb then
		current.stopping = true
	end
end

function ProceduralAnimator.startGuard(model: Model)
	local current = playing[model]
	if current and current.guard then
		current.stopping = false
		return
	end
	if current and current.climb then
		return
	end
	local motors = findMotors(model)
	if not motors then
		return
	end
	finish(model)
	playing[model] = { guard = true, motors = motors, weight = 0, last = os.clock(), stopping = false }
	if not connection then
		connection = RunService.PreSimulation:Connect(step)
	end
end

function ProceduralAnimator.stopGuard(model: Model)
	local current = playing[model]
	if current and current.guard then
		current.stopping = true
	end
end

function ProceduralAnimator.stop(model: Model)
	finish(model)
end

return ProceduralAnimator
