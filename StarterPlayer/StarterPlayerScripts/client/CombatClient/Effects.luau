--!nonstrict

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local CombatShared = require(ReplicatedStorage:WaitForChild("CombatShared"))

local RINGS = {
	doubleJump = { size = 5, time = 0.25, color = Color3.fromRGB(230, 240, 255) },
	skyJump = { size = 9, time = 0.35, color = Color3.fromRGB(255, 255, 255) },
}

local FLASHES = {
	hit = { color = Color3.fromRGB(255, 60, 60), time = 0.15 },
	blocked = { color = Color3.fromRGB(200, 230, 255), time = 0.12 },
	guardBreak = { color = Color3.fromRGB(255, 210, 70), time = 0.35 },
	dodge = { color = Color3.fromRGB(150, 255, 200), time = 0.15 },
}

local ELEMENT_COLORS = {
	fire = Color3.fromRGB(255, 120, 30),
}

local Effects = {}

local projectiles = {}
local projectileConnection = nil

local function effect(name: string)
	return CombatShared.template("Effects", name)
end

local function tweenAway(p: BasePart, time: number, goal)
	goal.Transparency = 1
	TweenService:Create(p, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal):Play()
	Debris:AddItem(p, time + 0.1)
end

local function rootOf(model)
	if typeof(model) ~= "Instance" or not model:IsA("Model") then
		return nil
	end
	return model:FindFirstChild("HumanoidRootPart")
end

local function ring(root: BasePart, style)
	local p = effect("Ring")
	if not p then
		return
	end
	p.Color = style.color
	p.CFrame = CFrame.new(root.Position - Vector3.new(0, 2.8, 0)) * CFrame.Angles(0, 0, math.rad(90))
	p.Parent = Workspace.CurrentCamera
	tweenAway(p, style.time, { Size = Vector3.new(p.Size.X, style.size, style.size) })
end

local function flash(model: Model, style)
	local h = effect("Flash")
	if not h then
		return
	end
	h.FillColor = style.color
	h.OutlineColor = style.color
	h.Parent = model
	TweenService:Create(h, TweenInfo.new(style.time), { FillTransparency = 1, OutlineTransparency = 1 }):Play()
	Debris:AddItem(h, style.time + 0.05)
end

local function sphere(position: Vector3, color: Color3, fromSize: number, toSize: number, time: number)
	local p = effect("Sphere")
	if not p then
		return
	end
	p.Color = color
	p.Size = Vector3.one * fromSize
	p.CFrame = CFrame.new(position)
	p.Parent = Workspace.CurrentCamera
	tweenAway(p, time, { Size = Vector3.one * toSize })
end

local function box(cframe: CFrame, size: Vector3, ball: boolean)
	local p = effect(if ball then "Sphere" else "Hitbox")
	if not p then
		return
	end
	if ball then
		p.Material = Enum.Material.ForceField
		p.Color = Color3.fromRGB(255, 40, 40)
		p.Transparency = 0.75
	end
	p.Size = size
	p.CFrame = cframe
	p.Parent = Workspace.CurrentCamera
	Debris:AddItem(p, 0.3)
end

local function stepProjectiles(dt: number)
	for id, pr in pairs(projectiles) do
		local step = math.min(pr.speed * dt, pr.range - pr.traveled)
		pr.traveled += step
		pr.position += pr.direction * step
		pr.part.CFrame = CFrame.new(pr.position)
		if pr.traveled >= pr.range or os.clock() - pr.born > 10 then
			pr.part:Destroy()
			projectiles[id] = nil
		end
	end
	if next(projectiles) == nil and projectileConnection then
		projectileConnection:Disconnect()
		projectileConnection = nil
	end
end

function Effects.play(kind, model, ...)
	local root = rootOf(model)
	if kind == "hitbox" or kind == "hitsphere" then
		local cframe, size = ...
		if typeof(cframe) == "CFrame" and typeof(size) == "Vector3" then
			box(cframe, size, kind == "hitsphere")
		end
		return
	end
	if not root then
		return
	end
	if RINGS[kind] then
		ring(root, RINGS[kind])
	elseif FLASHES[kind] then
		flash(model, FLASHES[kind])
	elseif kind == "blast" then
		local center, element = ...
		if typeof(center) == "Vector3" then
			sphere(center, ELEMENT_COLORS[element] or Color3.new(1, 1, 1), 1.5, 6, 0.25)
		end
	elseif kind == "burst" then
		local radius, element = ...
		if type(radius) == "number" then
			sphere(root.Position, ELEMENT_COLORS[element] or Color3.new(1, 1, 1), 2, radius * 2, 0.4)
		end
	end
end

function Effects.projectile(id, origin, direction, speed, range, weaponName, config)
	if type(id) ~= "number" or typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" or type(speed) ~= "number" or type(range) ~= "number" then
		return
	end
	local p = effect("Projectile")
	if not p then
		return
	end
	local weapon = config.weapons[weaponName]
	local color = ELEMENT_COLORS[weapon and weapon.effect] or Color3.new(1, 1, 1)
	p.Color = color
	local light = p:FindFirstChildOfClass("PointLight")
	if light then
		light.Color = color
	end
	p.CFrame = CFrame.new(origin)
	p.Parent = Workspace.CurrentCamera
	projectiles[id] = { part = p, position = origin, direction = direction, speed = speed, range = range, traveled = 0, born = os.clock(), color = color }
	if not projectileConnection then
		projectileConnection = RunService.RenderStepped:Connect(stepProjectiles)
	end
end

function Effects.projectileEnd(id, position, exploded)
	local pr = projectiles[id]
	local color = if pr then pr.color else Color3.fromRGB(255, 120, 30)
	if pr then
		pr.part:Destroy()
		projectiles[id] = nil
	end
	if exploded and typeof(position) == "Vector3" then
		sphere(position, color, 2, 14, 0.4)
	end
end

return Effects
