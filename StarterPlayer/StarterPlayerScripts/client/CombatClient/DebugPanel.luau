--!nonstrict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local REFRESH_INTERVAL = 0.1
local SCAN_INTERVAL = 2
local MAX_NPC_ROWS = 6

local DebugPanel = {}
DebugPanel.__index = DebugPanel

function DebugPanel.new(ctx)
	local self = setmetatable({
		ctx = ctx,
		enabled = false,
		hitboxes = false,
		npcs = {},
		lastScan = -math.huge,
		fps = 60,
	}, DebugPanel)
	task.spawn(function()
		self:_bind()
	end)
	return self
end

function DebugPanel:_bind()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild("CombatDebug", 15)
	if not gui then
		warn("[CombatSystem] still waiting for CombatDebug in PlayerGui; is it in StarterGui?")
		gui = playerGui:WaitForChild("CombatDebug")
	end
	local toggle = gui:WaitForChild("Toggle", 5)
	local panel = gui:WaitForChild("Panel", 5)
	local hitboxButton = panel and panel:WaitForChild("HitboxButton", 5)
	local skyButton = panel and panel:WaitForChild("SkyJumpButton", 5)
	local info = panel and panel:WaitForChild("Info", 5)
	if not (toggle and panel and hitboxButton and skyButton and info) then
		warn("[CombatSystem] CombatDebug is missing Toggle/Panel/HitboxButton/SkyJumpButton/Info; the debug panel is disabled.")
		return
	end
	self.gui, self.toggle, self.panel, self.hitboxButton, self.skyButton, self.info = gui, toggle, panel, hitboxButton, skyButton, info
	toggle.Activated:Connect(function()
		self.ctx.send("Debug", not self.enabled)
	end)
	hitboxButton.Activated:Connect(function()
		self.hitboxes = not self.hitboxes
		hitboxButton.Text = if self.hitboxes then "Hitboxes: ON" else "Hitboxes: OFF"
	end)
	skyButton.Activated:Connect(function()
		self.ctx.send("DebugUnlock", "skyJump", not self.ctx.hasUnlock("skyJump"))
	end)
	local elapsed = 0
	RunService.RenderStepped:Connect(function(dt)
		self.fps += (1 / math.max(dt, 1e-3) - self.fps) * 0.1
		elapsed += dt
		if self.enabled and elapsed >= REFRESH_INTERVAL then
			elapsed = 0
			self:_refresh()
		end
	end)
end

function DebugPanel:setEnabled(allowed: boolean)
	self.enabled = allowed
	if self.panel then
		self.panel.Visible = allowed
		self.toggle.Text = if allowed then "DEBUG ON" else "DEBUG"
	end
	if not allowed then
		self.hitboxes = false
		if self.hitboxButton then
			self.hitboxButton.Text = "Hitboxes: OFF"
		end
	end
end

function DebugPanel:wantsHitboxes(): boolean
	return self.hitboxes or self.ctx.config.debug.showHitboxes
end

function DebugPanel:_scan()
	local now = os.clock()
	if now - self.lastScan < SCAN_INTERVAL then
		return
	end
	self.lastScan = now
	table.clear(self.npcs)
	for _, inst in ipairs(Workspace:GetDescendants()) do
		if inst:IsA("Model") and type(inst:GetAttribute("CombatProfile")) == "string" then
			table.insert(self.npcs, inst)
		end
	end
end

function DebugPanel:_refresh()
	local ctx = self.ctx
	self.skyButton.Text = if ctx.hasUnlock("skyJump") then "Sky Jump: ON" else "Sky Jump: OFF"
	local character = ctx.player.Character
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local lines = {}
	table.insert(lines, ("FPS %d  ping %dms"):format(self.fps, ctx.player:GetNetworkPing() * 2000))
	if character and hum and root then
		local weapon = ctx.currentWeapon()
		table.insert(lines, ("state   %s"):format(ctx.combatState()))
		table.insert(lines, ("weapon  %s"):format(weapon))
		table.insert(lines, ("health  %d / %d"):format(hum.Health, hum.MaxHealth))
		table.insert(lines, ("shield  %d / %d"):format(character:GetAttribute("Shield") or 0, character:GetAttribute("ShieldMax") or 0))
		table.insert(lines, ("speed   %.1f (walk %.1f)"):format(root.AssemblyLinearVelocity.Magnitude, hum.WalkSpeed))
		table.insert(lines, ("airJumps %d  skyJump %s"):format(ctx.movement.airJumps or 0, tostring(ctx.hasUnlock("skyJump"))))
	end
	local stats = ctx.stats()
	local keys = {}
	for key in pairs(stats) do
		table.insert(keys, key)
	end
	table.sort(keys)
	local parts = {}
	for _, key in ipairs(keys) do
		table.insert(parts, ("%s=%g"):format(key, stats[key]))
	end
	table.insert(lines, "stats   " .. table.concat(parts, " "))
	table.insert(lines, "-- cooldowns")
	local ids = {}
	for id in pairs(ctx.cooldowns) do
		if ctx.cooldownRemaining(id) > 0 then
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	if #ids == 0 then
		table.insert(lines, "none")
	end
	for _, id in ipairs(ids) do
		table.insert(lines, ("%s %.1fs"):format(id, ctx.cooldownRemaining(id)))
	end
	self:_scan()
	table.insert(lines, "-- npcs")
	local shown = 0
	for _, model in ipairs(self.npcs) do
		local npcRoot = model.Parent and model:FindFirstChild("HumanoidRootPart")
		local npcHum = model:FindFirstChildOfClass("Humanoid")
		if npcRoot and npcHum and root and shown < MAX_NPC_ROWS then
			shown += 1
			table.insert(lines, ("%s %s hp%d %dst %s"):format(
				model:GetAttribute("CombatProfile"),
				tostring(model:GetAttribute("CombatState") or "-"),
				npcHum.Health,
				(npcRoot.Position - root.Position).Magnitude,
				npcRoot.CFrame.UpVector.Y < 0.9 and "TILTED" or "ok"
			))
		end
	end
	self.info.Text = table.concat(lines, "\n")
end

return DebugPanel
