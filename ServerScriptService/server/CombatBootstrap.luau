--!nonstrict

local ServerScriptService = game:GetService("ServerScriptService")

local CombatSystem = require(ServerScriptService:WaitForChild("CombatSystem"))

local ok, err = pcall(CombatSystem.Start)
if not ok then
	warn(err)
end
