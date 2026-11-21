--!nonstrict

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local FULL = Color3.fromRGB(150, 205, 255)
local MID = Color3.fromRGB(255, 215, 90)
local LOW = Color3.fromRGB(255, 80, 80)

local ShieldIndicator = {}
ShieldIndicator.__index = ShieldIndicator

local MIN_SCALE = 0.05
local MAX_SCALE = 8

function ShieldIndicator.new(distance: number, widthStuds: number)
	return setmetatable({ active = {}, warned = false, distance = distance, widthStuds = widthStuds, connection = nil }, ShieldIndicator)
end

function ShieldIndicator:_clone(model: Model)
	local template = ReplicatedStorage:FindFirstChild("ShieldIndicator")
	if not template or not template:IsA("BillboardGui") then
		if not self.warned then
			self.warned = true
			warn("[CombatSystem] ShieldIndicator (BillboardGui) not found in ReplicatedStorage; the shield icon is disabled.")
		end
		return nil
	end
	local adornee = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	local holderTemplate = template:FindFirstChild("Holder")
	local slot = holderTemplate and holderTemplate:FindFirstChild("Slot")
	local fill = slot and slot:FindFirstChild("Fill")
	if not adornee or not fill then
		if not adornee then
			return nil
		end
		if not self.warned then
			self.warned = true
			warn("[CombatSystem] ShieldIndicator is missing Holder/Slot/Fill; the shield icon is disabled.")
		end
		return nil
	end
	local gui = template:Clone()
	gui.Adornee = adornee
	gui.Enabled = true
	gui.ResetOnSpawn = false
	gui.MaxDistance = self.distance
	local holder = gui.Holder
	local clonedFill = holder.Slot.Fill
	local paints = {}
	for _, d in ipairs(clonedFill:GetDescendants()) do
		if d:IsA("Frame") and d.Name == "Paint" then
			table.insert(paints, d)
		end
	end
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return { gui = gui, fill = clonedFill, paints = paints, scale = holder:FindFirstChildOfClass("UIScale"), root = adornee, baseWidth = math.max(holder.Size.X.Offset, 1) }
end

function ShieldIndicator:_scaleFor(entry, camera: Camera): number
	local distance = math.max((camera.CFrame.Position - entry.root.Position).Magnitude, 0.5)
	local pixelsPerStud = camera.ViewportSize.Y / (2 * distance * math.tan(math.rad(camera.FieldOfView) / 2))
	return math.clamp(self.widthStuds * pixelsPerStud / entry.baseWidth, MIN_SCALE, MAX_SCALE)
end

function ShieldIndicator:_rescale()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	for _, entry in pairs(self.active) do
		if entry.scale and entry.root.Parent then
			entry.scale.Scale = self:_scaleFor(entry, camera)
		end
	end
end

function ShieldIndicator:_ensureLoop()
	if self.connection then
		return
	end
	self.connection = RunService.RenderStepped:Connect(function()
		if next(self.active) == nil then
			self.connection:Disconnect()
			self.connection = nil
			return
		end
		self:_rescale()
	end)
end

function ShieldIndicator:_paint(entry, model: Model, instant: boolean?)
	local shield = model:GetAttribute("Shield") or 0
	local max = model:GetAttribute("ShieldMax") or 0
	local ratio = if max > 0 then math.clamp(shield / max, 0, 1) else 0
	local color = if ratio > 0.5 then FULL elseif ratio > 0.25 then MID else LOW
	local size = UDim2.new(1, 0, ratio, 0)
	if instant then
		entry.fill.Size = size
	else
		TweenService:Create(entry.fill, TweenInfo.new(0.12), { Size = size }):Play()
	end
	for _, paint in ipairs(entry.paints) do
		paint.BackgroundColor3 = color
	end
end

function ShieldIndicator:set(model, on: boolean)
	if typeof(model) ~= "Instance" or not model:IsA("Model") then
		return
	end
	local entry = self.active[model]
	if on then
		if entry then
			return
		end
		entry = self:_clone(model)
		if not entry then
			return
		end
		entry.connections = {
			model:GetAttributeChangedSignal("Shield"):Connect(function()
				self:_paint(entry, model)
			end),
			model.AncestryChanged:Connect(function()
				if not model.Parent then
					self:set(model, false)
				end
			end),
		}
		self.active[model] = entry
		self:_paint(entry, model, true)
		self:_rescale()
		self:_ensureLoop()
	elseif entry then
		self.active[model] = nil
		for _, c in ipairs(entry.connections) do
			c:Disconnect()
		end
		entry.gui:Destroy()
	end
end

function ShieldIndicator:shatter(model)
	if typeof(model) ~= "Instance" or not model:IsA("Model") then
		return
	end
	self:set(model, false)
	local entry = self:_clone(model)
	if not entry then
		return
	end
	entry.fill.Size = UDim2.fromScale(1, 1)
	local camera = Workspace.CurrentCamera
	if entry.scale and camera then
		entry.scale.Scale = self:_scaleFor(entry, camera)
	end
	for _, paint in ipairs(entry.paints) do
		paint.BackgroundColor3 = LOW
	end
	local info = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for _, d in ipairs(entry.gui:GetDescendants()) do
		if d:IsA("Frame") then
			TweenService:Create(d, info, { BackgroundTransparency = 1 }):Play()
		end
	end
	TweenService:Create(entry.gui.Holder.Slot, info, { Rotation = (if math.random() < 0.5 then -1 else 1) * 25 }):Play()
	Debris:AddItem(entry.gui, 0.5)
end

return ShieldIndicator
