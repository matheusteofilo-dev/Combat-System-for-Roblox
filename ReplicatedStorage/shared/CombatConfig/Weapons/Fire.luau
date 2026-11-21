--!nonstrict

local CombatShared = require(game:GetService("ReplicatedStorage"):WaitForChild("CombatShared"))

local function damage(base: number, scale: number)
	return function(s)
		return base + s.fire * scale
	end
end

local PUSH = {
	duration = 0.38,
	keyframes = {
		{ t = 0, pose = {} },
		{ t = 0.05, pose = { rightArm = { 40, 0, 8 }, leftArm = { 30, 0, -10 }, torso = { 8, -14, 0 } } },
		{ t = 0.12, pose = { rightArm = { 92, 0, 3 }, leftArm = { 50, 0, -14 }, torso = { -8, 16, 0 }, leftLeg = { 14, 0, 0 } } },
		{ t = 0.22, pose = { rightArm = { 92, 0, 3 }, leftArm = { 50, 0, -14 }, torso = { -8, 16, 0 }, leftLeg = { 14, 0, 0 } } },
		{ t = 0.38, pose = {} },
	},
}

local BLAST = { size = Vector3.new(5, 5, 7), offset = CFrame.new(0, 0, -4) }

return {
	displayName = "Fire",
	effect = "fire",
	m1 = {
		comboResetTime = 1,
		comboEndCooldown = 0.8,
		hits = {
			{ windup = 0.12, recovery = 0.22, hitbox = BLAST, damage = damage(6, 0.1), animation = PUSH },
			{ windup = 0.12, recovery = 0.22, hitbox = BLAST, damage = damage(6, 0.1), animation = CombatShared.mirror(PUSH) },
			{
				windup = 0.19,
				recovery = 0.3,
				hitbox = { size = Vector3.new(7, 6, 9), offset = CFrame.new(0, 0, -5) },
				damage = damage(9, 0.15),
				knockback = 30,
				animation = {
					duration = 0.52,
					keyframes = {
						{ t = 0, pose = {} },
						{ t = 0.12, pose = { rightArm = { 60, 0, 30 }, leftArm = { 60, 0, -30 }, torso = { 14, 0, 0 } } },
						{ t = 0.19, pose = { rightArm = { 92, 0, 6 }, leftArm = { 92, 0, -6 }, torso = { -12, 0, 0 } } },
						{ t = 0.3, pose = { rightArm = { 92, 0, 6 }, leftArm = { 92, 0, -6 }, torso = { -12, 0, 0 } } },
						{ t = 0.52, pose = {} },
					},
				},
			},
		},
	},
	abilities = {
		{
			id = "Fireball",
			key = "Z",
			name = "Fireball",
			kind = "projectile",
			cooldown = 4,
			windup = 0.26,
			recovery = 0.25,
			projectile = {
				speed = 90,
				range = 140,
				radius = 1.5,
				explosionRadius = 7,
			},
			damage = damage(16, 0.25),
			knockback = 35,
			animation = {
				duration = 0.55,
				keyframes = {
					{ t = 0, pose = {} },
					{ t = 0.2, pose = { rightArm = { 150, 0, 12 }, leftArm = { 40, 0, -20 }, torso = { 12, -20, 0 }, leftLeg = { 14, 0, 0 } } },
					{ t = 0.26, pose = { rightArm = { 92, 0, 4 }, leftArm = { 40, 0, -24 }, torso = { -10, 22, 0 }, leftLeg = { 20, 0, 0 } } },
					{ t = 0.38, pose = { rightArm = { 92, 0, 4 }, leftArm = { 40, 0, -24 }, torso = { -10, 22, 0 }, leftLeg = { 20, 0, 0 } } },
					{ t = 0.55, pose = {} },
				},
			},
		},
		{
			id = "FlameBurst",
			key = "X",
			name = "Flame Burst",
			kind = "area",
			cooldown = 9,
			windup = 0.41,
			recovery = 0.4,
			area = { radius = 12 },
			damage = damage(20, 0.3),
			knockback = 55,
			breaksBlock = true,
			animation = {
				duration = 0.85,
				keyframes = {
					{ t = 0, pose = {} },
					{ t = 0.34, pose = { rightArm = { 20, 0, 14 }, leftArm = { 20, 0, -14 }, torso = { 16, 0, 0 }, rightLeg = { -10, 0, 0 }, leftLeg = { -10, 0, 0 } } },
					{ t = 0.41, pose = { rightArm = { 20, 0, 100 }, leftArm = { 20, 0, -100 }, torso = { -14, 0, 0 } } },
					{ t = 0.6, pose = { rightArm = { 20, 0, 100 }, leftArm = { 20, 0, -100 }, torso = { -14, 0, 0 } } },
					{ t = 0.85, pose = {} },
				},
			},
		},
	},
}
