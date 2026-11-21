--!nonstrict

local weapons = {}

for _, child in ipairs(script:GetChildren()) do
	if child:IsA("ModuleScript") then
		weapons[child.Name] = require(child)
	end
end

return weapons
