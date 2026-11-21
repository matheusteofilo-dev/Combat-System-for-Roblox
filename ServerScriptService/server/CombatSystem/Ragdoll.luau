--!nonstrict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatShared = require(ReplicatedStorage:WaitForChild("CombatShared"))

local ROOT_JOINTS = { RootJoint = true, Root = true }

local Ragdoll = {}

local rigs = setmetatable({}, { __mode = "k" })

local function newSocket(parent: Instance, a0: Attachment, a1: Attachment)
	local socket = CombatShared.template("Physics", "RagdollSocket")
	if not socket then
		return nil
	end
	socket.Attachment0 = a0
	socket.Attachment1 = a1
	socket.Enabled = false
	socket.Parent = parent
	return socket
end

local function newAttachment(parent: Instance, cframe: CFrame)
	local attachment = CombatShared.template("Physics", "RagdollAttachment")
	if attachment then
		attachment.CFrame = cframe
		attachment.Parent = parent
	end
	return attachment
end

local function build(model: Model)
	local rig = { joints = {}, parts = {} }
	for _, joint in ipairs(model:GetDescendants()) do
		if joint:IsA("AnimationConstraint") and not ROOT_JOINTS[joint.Name] and joint.Attachment0 and joint.Attachment1 then
			local part = joint.Attachment1.Parent
			local socket = joint.Parent and joint.Parent:FindFirstChild(joint.Name .. "BallSocket")
			if not (socket and socket:IsA("BallSocketConstraint")) then
				socket = newSocket(joint.Parent, joint.Attachment0, joint.Attachment1)
			end
			if socket and part and part:IsA("BasePart") then
				table.insert(rig.joints, { motor = joint, socket = socket, part = part, socketWasEnabled = socket.Enabled })
			end
		end
	end
	for _, motor in ipairs(model:GetDescendants()) do
		if motor:IsA("Motor6D") and not ROOT_JOINTS[motor.Name] and motor.Part0 and motor.Part1 then
			local a0 = newAttachment(motor.Part0, motor.C0)
			local a1 = newAttachment(motor.Part1, motor.C1)
			local socket = a0 and a1 and newSocket(motor.Part1, a0, a1)
			if socket then
				table.insert(rig.joints, { motor = motor, socket = socket, part = motor.Part1, socketWasEnabled = false })
			end
		end
	end
	rigs[model] = rig
	return rig
end

function Ragdoll.isActive(model: Model): boolean
	local rig = rigs[model]
	return rig ~= nil and rig.active == true
end

function Ragdoll.enable(model: Model, humanoid: Humanoid, serverOwned: boolean)
	local rig = rigs[model] or build(model)
	if rig.active then
		return
	end
	rig.active = true
	rig.requiresNeck = humanoid.RequiresNeck
	humanoid.RequiresNeck = false
	for _, joint in ipairs(rig.joints) do
		if joint.motor.Parent then
			joint.socket.Enabled = true
			joint.motor.Enabled = false
			rig.parts[joint.part] = joint.part.CanCollide
			joint.part.CanCollide = true
		end
	end
	if serverOwned then
		humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	end
end

function Ragdoll.disable(model: Model, humanoid: Humanoid, serverOwned: boolean)
	local rig = rigs[model]
	if not rig or not rig.active then
		return
	end
	rig.active = false
	for _, joint in ipairs(rig.joints) do
		if joint.motor.Parent then
			joint.motor.Enabled = true
			joint.socket.Enabled = joint.socketWasEnabled == true
		end
		local canCollide = rig.parts[joint.part]
		if canCollide ~= nil and joint.part.Parent then
			joint.part.CanCollide = canCollide
		end
	end
	table.clear(rig.parts)
	if rig.requiresNeck ~= nil then
		humanoid.RequiresNeck = rig.requiresNeck
	end
	if serverOwned and humanoid.Health > 0 then
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
end

return Ragdoll
