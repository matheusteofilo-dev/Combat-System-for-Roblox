--!nonstrict

local CombatShared = require(game:GetService("ReplicatedStorage"):WaitForChild("CombatShared"))

local STRAIGHT = {
	duration = 0.34,
	keyframes = {
		{ t = 0, pose = {} },
		{ t = 0.04, pose = { rightArm = { -30, 0, 8 }, leftArm = { 55, 0, -14 }, torso = { 0, -20, 0 }, leftLeg = { 18, 0, 0 }, rightLeg = { -12, 0, 0 } } },
		{ t = 0.09, pose = { rightArm = { 88, 0, 4 }, leftArm = { 40, 0, -18 }, torso = { -6, 28, 0 }, leftLeg = { 22, 0, 0 }, rightLeg = { -14, 0, 0 } } },
		{ t = 0.17, pose = { rightArm = { 88, 0, 4 }, leftArm = { 40, 0, -18 }, torso = { -6, 28, 0 }, leftLeg = { 22, 0, 0 }, rightLeg = { -14, 0, 0 } } },
		{ t = 0.34, pose = {} },
	},
}

local HOOK = {
	duration = 0.38,
	keyframes = {
		{ t = 0, pose = {} },
		{ t = 0.05, pose = { rightArm = { 10, -10, 95 }, leftArm = { 60, 0, -14 }, torso = { 0, -35, 0 }, leftLeg = { 16, 0, 0 } } },
		{ t = 0.1, pose = { rightArm = { 10, 105, 95 }, leftArm = { 60, 0, -14 }, torso = { -4, 40, 0 }, leftLeg = { 20, 0, 0 }, rightLeg = { -14, 0, 0 } } },
		{ t = 0.2, pose = { rightArm = { 10, 105, 95 }, leftArm = { 60, 0, -14 }, torso = { -4, 40, 0 }, leftLeg = { 20, 0, 0 }, rightLeg = { -14, 0, 0 } } },
		{ t = 0.38, pose = {} },
	},
}

local UPPERCUT = {
	duration = 0.46,
	keyframes = {
		{ t = 0, pose = {} },
		{ t = 0.1, pose = { rightArm = { -15, 0, 12 }, leftArm = { 70, 0, -16 }, torso = { -14, -18, 0 }, rightLeg = { -10, 0, 0 }, leftLeg = { 14, 0, 0 } } },
		{ t = 0.15, pose = { rightArm = { 165, 0, 4 }, leftArm = { 30, 0, -20 }, torso = { 14, 18, 0 }, leftLeg = { 24, 0, 0 }, rightLeg = { -16, 0, 0 } } },
		{ t = 0.26, pose = { rightArm = { 165, 0, 4 }, leftArm = { 30, 0, -20 }, torso = { 14, 18, 0 }, leftLeg = { 24, 0, 0 }, rightLeg = { -16, 0, 0 } } },
		{ t = 0.46, pose = {} },
	},
}

local HEAVY = {
	duration = 0.7,
	keyframes = {
		{ t = 0, pose = {} },
		{ t = 0.32, pose = { rightArm = { -55, 0, 14 }, leftArm = { 70, 0, -14 }, torso = { 10, -40, 0 }, rightLeg = { -16, 0, 0 }, leftLeg = { 20, 0, 0 } } },
		{ t = 0.37, pose = { rightArm = { 92, 0, 4 }, leftArm = { 30, 0, -22 }, torso = { -14, 38, 0 }, leftLeg = { 30, 0, 0 }, rightLeg = { -20, 0, 0 } } },
		{ t = 0.5, pose = { rightArm = { 92, 0, 4 }, leftArm = { 30, 0, -22 }, torso = { -14, 38, 0 }, leftLeg = { 30, 0, 0 }, rightLeg = { -20, 0, 0 } } },
		{ t = 0.7, pose = {} },
	},
}

return {
	displayName = "Fists",
	m1 = {
		comboResetTime = 1,
		comboEndCooldown = 0.8,
		hits = {
			{
				windup = 0.09,
				recovery = 0.2,
				hitbox = { size = Vector3.new(4, 5, 4), offset = CFrame.new(0, 0, -2.5) },
				damage = function(s)
					return 5 + s.strength * 0.1
				end,
				animation = STRAIGHT,
			},
			{
				windup = 0.09,
				recovery = 0.2,
				hitbox = { size = Vector3.new(4, 5, 4), offset = CFrame.new(0, 0, -2.5) },
				damage = function(s)
					return 5 + s.strength * 0.1
				end,
				animation = CombatShared.mirror(STRAIGHT),
			},
			{
				windup = 0.1,
				recovery = 0.22,
				hitbox = { size = Vector3.new(5, 5, 4), offset = CFrame.new(0, 0, -2.5) },
				damage = function(s)
					return 6 + s.strength * 0.1
				end,
				animation = HOOK,
			},
			{
				windup = 0.15,
				recovery = 0.3,
				hitbox = { size = Vector3.new(4, 6, 4), offset = CFrame.new(0, 0.5, -2.5) },
				damage = function(s)
					return 8 + s.strength * 0.15
				end,
				knockback = 35,
				animation = UPPERCUT,
			},
		},
	},
	abilities = {
		{
			id = "HeavyPunch",
			key = "Z",
			name = "Heavy Punch",
			kind = "melee",
			cooldown = 5,
			windup = 0.37,
			recovery = 0.33,
			hitbox = { size = Vector3.new(5, 5, 5), offset = CFrame.new(0, 0, -3) },
			damage = function(s)
				return 14 + s.strength * 0.25
			end,
			knockback = 50,
			breaksBlock = true,
			animation = HEAVY,
		},
	},
}
