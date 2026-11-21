--!nonstrict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FULL = Color3.fromRGB(120, 255, 140)
local MID = Color3.fromRGB(255, 220, 90)
local LOW = Color3.fromRGB(255, 80, 80)

local ClimbIndicator = {}
ClimbIndicator.__index = ClimbIndicator

function ClimbIndicator.new(distance: number)
	return setmetatable({ gui = nil, distance = distance, warned = false, lastFraction = -1 }, ClimbIndicator)
end

function ClimbIndicator:_ensure(): boolean
	if self.gui and self.gui.Parent then
		return true
	end
	local template = ReplicatedStorage:FindFirstChild("ClimbIndicator")
	if not template or not template:IsA("BillboardGui") then
		if not self.warned then
			self.warned = true
			warn("[CombatSystem] ClimbIndicator (BillboardGui) not found in ReplicatedStorage; the climb stamina ring is disabled.")
		end
		return false
	end
	local gui = template:Clone()
	gui.Enabled = false
	gui.ResetOnSpawn = false
	gui.MaxDistance = self.distance
	local ring = gui:FindFirstChild("Ring")
	local left = ring and ring:FindFirstChild("LeftHalf")
	local right = ring and ring:FindFirstChild("RightHalf")
	local leftStroke = left and left:FindFirstChild("Circle") and left.Circle:FindFirstChild("Stroke")
	local rightStroke = right and right:FindFirstChild("Circle") and right.Circle:FindFirstChild("Stroke")
	local leftGradient = leftStroke and leftStroke:FindFirstChild("Gradient")
	local rightGradient = rightStroke and rightStroke:FindFirstChild("Gradient")
	if not (leftStroke and rightStroke and leftGradient and rightGradient) then
		if not self.warned then
			self.warned = true
			warn("[CombatSystem] ClimbIndicator is missing Ring/LeftHalf/RightHalf/Circle/Stroke/Gradient; the climb stamina ring is disabled.")
		end
		gui:Destroy()
		return false
	end
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	self.gui = gui
	self.strokes = { leftStroke, rightStroke }
	self.leftGradient = leftGradient
	self.rightGradient = rightGradient
	return true
end

function ClimbIndicator:show(root: BasePart)
	if not self:_ensure() then
		return
	end
	self.gui.Adornee = root
	self.gui.Enabled = true
	self.lastFraction = -1
	self:update(1)
end

function ClimbIndicator:update(fraction: number)
	if not self.gui or not self.gui.Enabled then
		return
	end
	fraction = math.clamp(fraction, 0, 1)
	if math.abs(fraction - self.lastFraction) < 0.002 then
		return
	end
	self.lastFraction = fraction
	local angle = fraction * 360
	self.rightGradient.Rotation = math.clamp(angle, 0, 180)
	self.leftGradient.Rotation = math.clamp(angle, 180, 360)
	local color = if fraction > 0.5 then FULL elseif fraction > 0.25 then MID else LOW
	for _, stroke in ipairs(self.strokes) do
		stroke.Color = color
	end
end

function ClimbIndicator:hide()
	if self.gui then
		self.gui.Enabled = false
		self.gui.Adornee = nil
	end
end

return ClimbIndicator
