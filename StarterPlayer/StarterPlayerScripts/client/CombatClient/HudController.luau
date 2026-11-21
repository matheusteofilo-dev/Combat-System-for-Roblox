--!nonstrict

local RunService = game:GetService("RunService")

local KEY_LABELS = {
	LeftControl = "CTRL",
	RightControl = "CTRL",
	LeftShift = "SHFT",
	RightShift = "SHFT",
	Space = "SPC",
}

local HudController = {}
HudController.__index = HudController

local function keyLabel(name: string): string
	return KEY_LABELS[name] or name
end

function HudController.new(ctx)
	local self = setmetatable({
		ctx = ctx,
		rows = {},
		gui = nil,
		list = nil,
		template = nil,
		weaponName = nil,
		skyUnlocked = nil,
		characterConnection = nil,
	}, HudController)

	local playerGui = ctx.player:WaitForChild("PlayerGui")
	local gui = playerGui:FindFirstChild("CombatHud")
	if not gui then
		local slow = task.delay(15, function()
			warn("[CombatSystem] still waiting for CombatHud in PlayerGui; is it in StarterGui?")
		end)
		gui = playerGui:WaitForChild("CombatHud")
		task.cancel(slow)
	end
	local list = gui and gui:FindFirstChild("AbilityList", true)
	local template = list and list:FindFirstChild("AbilityRow")
	if not template then
		warn("[CombatSystem] CombatHud (with AbilityList/AbilityRow) not found in StarterGui; the ability HUD is disabled.")
		return self
	end
	template.Visible = false
	self.gui, self.list, self.template = gui, list, template

	local function watchCharacter(character)
		if self.characterConnection then
			self.characterConnection:Disconnect()
		end
		self.characterConnection = character:GetAttributeChangedSignal("Weapon"):Connect(function()
			self:rebuild()
		end)
		self:rebuild()
	end
	ctx.player.CharacterAdded:Connect(watchCharacter)
	if ctx.player.Character then
		watchCharacter(ctx.player.Character)
	end
	ctx.player:GetAttributeChangedSignal("Unlock_skyJump"):Connect(function()
		self:rebuild()
	end)
	RunService.RenderStepped:Connect(function()
		self:update()
	end)
	self:rebuild()
	return self
end

function HudController:_entries()
	local ctx = self.ctx
	local keys = ctx.config.keys
	local weaponName, weapon = ctx.currentWeapon()
	local entries = {
		{ kind = "cooldown", id = "M1", key = "M1", title = "Attack" },
		{ kind = "block", key = keyLabel(keys.block), title = "Block" },
		{ kind = "cooldown", id = "Dash", key = keyLabel(keys.dash), title = "Dash" },
	}
	if ctx.hasUnlock("skyJump") then
		table.insert(entries, { kind = "cooldown", id = "SkyJump", key = keyLabel(keys.jump), title = "Sky Jump" })
	end
	if weapon then
		for _, ability in ipairs(weapon.abilities) do
			table.insert(entries, { kind = "cooldown", id = weaponName .. "." .. ability.id, key = keyLabel(ability.key), title = ability.name })
		end
	end
	return entries, weaponName
end

function HudController:rebuild()
	if not self.template then
		return
	end
	for _, row in ipairs(self.rows) do
		row.frame:Destroy()
	end
	table.clear(self.rows)
	local entries, weaponName = self:_entries()
	self.weaponName = weaponName
	for i, entry in ipairs(entries) do
		local frame = self.template:Clone()
		frame.Name = "AbilityRowActive"
		frame.LayoutOrder = i
		frame.Visible = true
		local key = frame:FindFirstChild("Key")
		local row = {
			frame = frame,
			entry = entry,
			title = frame:FindFirstChild("Title"),
			cooldown = key and key:FindFirstChild("Cooldown"),
			timer = key and key:FindFirstChild("Timer"),
		}
		local keyText = key and key:FindFirstChild("KeyLabel")
		if keyText then
			keyText.Text = entry.key
		end
		if row.title then
			row.title.Text = entry.title
		end
		frame.Parent = self.list
		table.insert(self.rows, row)
	end
	self:update()
end

local function setRow(row, fraction: number, timerText: string?, titleText: string?)
	if row.cooldown then
		row.cooldown.Size = UDim2.fromScale(1, math.clamp(fraction, 0, 1))
		row.cooldown.Visible = fraction > 0
	end
	if row.timer then
		row.timer.Visible = timerText ~= nil
		if timerText then
			row.timer.Text = timerText
		end
	end
	if row.title and titleText and row.title.Text ~= titleText then
		row.title.Text = titleText
	end
end

function HudController:update()
	local ctx = self.ctx
	local character = ctx.player.Character
	for _, row in ipairs(self.rows) do
		local entry = row.entry
		if entry.kind == "cooldown" then
			local remaining = ctx.cooldownRemaining(entry.id)
			local duration = ctx.cooldownDurations[entry.id] or 0
			if remaining > 0 and duration > 0 then
				setRow(row, remaining / duration, ("%.1f"):format(remaining))
			else
				setRow(row, 0, nil)
			end
		elseif entry.kind == "block" then
			local shield = character and character:GetAttribute("Shield") or 0
			local max = character and character:GetAttribute("ShieldMax") or 0
			local missing = if max > 0 then 1 - shield / max else 0
			local minRaise = ctx.config.block.minRaiseFraction
			local usable = max > 0 and shield / max >= minRaise
			setRow(row, if usable then 0 else missing, nil)
		end
	end
end

return HudController
